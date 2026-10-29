defmodule AcexGateway.Stream.CastRemuxer do
  @moduledoc """
  Manages on-demand HLS remuxing for Google Cast (Chromecast / Google TV) devices.

  Chromecast hardware decoders natively require HLS (.m3u8) container streams and
  standard AAC audio. This GenServer coordinates on-demand FFmpeg processes that
  remux raw MPEG-TS feeds using `-c:v copy` (zero video transcoding, ~0.2% CPU)
  and lightweight audio passthrough/AAC encoding.

  Processes run strictly on-demand when a Cast session requests HLS segments,
  and automatically terminate after 30 seconds of viewer inactivity to release resources.
  """

  use GenServer
  require Logger

  alias AcexGateway.Stream.SegmentObfuscator

  @sweep_interval_ms 10_000
  @inactivity_timeout_s 60
  @prewarm_interval_ms 1_500
  @max_startup_wait_ms 20_000
  @manifest_table :acex_cast_manifests

  # --- Client API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Ensures the ETS manifest and segment cache table exists.
  """
  def ensure_cache do
    case :ets.whereis(@manifest_table) do
      :undefined ->
        try do
          :ets.new(@manifest_table, [:set, :public, :named_table, read_concurrency: true])
        catch
          :error, :badarg -> @manifest_table
        end

      _tid ->
        @manifest_table
    end
  end

  @doc """
  Checks if FFmpeg binary is installed and executable on the host system.
  """
  def ffmpeg_available? do
    System.find_executable("ffmpeg") != nil
  end

  @doc """
  Ensures an HLS remuxer process is running for the given stream target,
  waits for initial manifest creation on cold start, and returns `{:ok, manifest_content}`.
  Manifest is served directly from ETS in memory with dynamic segment aggregation,
  eliminating disk race conditions and empty-playlist stalls.
  Accepts optional `base_url` for CDN segment pre-warming.
  """
  def get_manifest(target, base_url \\ nil) do
    if ffmpeg_available?() do
      clean_target = sanitize_target(target)

      case GenServer.call(__MODULE__, {:ensure_remuxer, clean_target, base_url}, 15_000) do
        {:ok, m3u8_path} ->
          job_dir = Path.dirname(m3u8_path)
          fetch_or_wait_manifest(clean_target, job_dir)

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :ffmpeg_not_found}
    end
  end

  @doc """
  Ensures an HLS remuxer process is running for the given stream target,
  waits for initial manifest creation on cold start, and returns the path to `live.m3u8`.
  Maintained for backwards compatibility.
  """
  def get_playlist(target, base_url \\ nil) do
    if ffmpeg_available?() do
      clean_target = sanitize_target(target)

      case GenServer.call(__MODULE__, {:ensure_remuxer, clean_target, base_url}, 15_000) do
        {:ok, m3u8_path} ->
          job_dir = Path.dirname(m3u8_path)

          case fetch_or_wait_manifest(clean_target, job_dir) do
            {:ok, _content} -> {:ok, m3u8_path}
            {:error, reason} -> {:error, reason}
          end

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :ffmpeg_not_found}
    end
  end

  @doc """
  Looks up the current cached manifest metadata for a target from ETS.
  """
  def lookup_manifest(target) do
    clean_target = sanitize_target(target)

    case :ets.lookup(@manifest_table, clean_target) do
      [{^clean_target, data}] -> {:ok, data}
      _ -> :error
    end
  rescue
    _ -> :error
  end

  @doc """
  Returns the list of active segment filenames for a target from ETS.
  """
  def get_active_segments(target) do
    case lookup_manifest(target) do
      {:ok, %{segments: segments}} ->
        Enum.map(segments, fn
          {name, _dur} -> name
          name when is_binary(name) -> name
        end)

      _ ->
        []
    end
  end

  @doc """
  Returns the absolute path of the requested segment file.
  Fast path checks ETS for job directory to bypass GenServer mailbox queuing.
  """
  def get_segment(target, segment_name) do
    clean_target = sanitize_target(target)
    raw_segment = SegmentObfuscator.deobfuscate(Path.basename(segment_name))

    case lookup_manifest(clean_target) do
      {:ok, %{dir: dir}} when is_binary(dir) ->
        segment_path = Path.join(dir, raw_segment)

        if File.exists?(segment_path) do
          {:ok, segment_path}
        else
          if running?(clean_target) do
            {:error, :not_found}
          else
            fallback_path = Path.join([cast_base_dir(), clean_target, raw_segment])

            if File.exists?(fallback_path) do
              {:ok, fallback_path}
            else
              {:error, :not_running}
            end
          end
        end

      _ ->
        GenServer.call(__MODULE__, {:get_segment, target, segment_name})
    end
  end

  @doc """
  Checks if a remuxer job is currently running for the target.
  """
  def running?(target) do
    clean_target = sanitize_target(target)
    GenServer.call(__MODULE__, {:is_running?, clean_target}, 3_000)
  catch
    :exit, _ -> false
  end

  @doc """
  Manually stops the remuxer for a target.
  """
  def stop_remuxer(target) do
    GenServer.cast(__MODULE__, {:stop_remuxer, target})
  end

  # --- GenServer Callbacks ---

  @impl true
  def init(_opts) do
    Process.flag(:trap_exit, true)
    ensure_cache()
    schedule_sweep()
    schedule_prewarm()
    # Clean up stale temp directories from previous runs on boot
    cleanup_dir(cast_base_dir())
    {:ok, %{jobs: %{}}}
  end

  @impl true
  def handle_call({:ensure_remuxer, clean_target, base_url}, _from, state) do
    now = System.monotonic_time(:second)

    case Map.get(state.jobs, clean_target) do
      %{dir: dir} = job ->
        new_base_url =
          cond do
            prewarm_eligible?(base_url) -> base_url
            is_binary(job[:base_url]) and job[:base_url] != "" -> job[:base_url]
            true -> effective_base_url(base_url)
          end

        updated_job = Map.merge(job, %{last_accessed: now, base_url: new_base_url})
        new_jobs = Map.put(state.jobs, clean_target, updated_job)
        m3u8_path = Path.join(dir, "live.m3u8")

        touch_ets_job_dir(clean_target, dir)

        {:reply, {:ok, m3u8_path}, %{state | jobs: new_jobs}}

      nil ->
        case start_ffmpeg_job(clean_target, base_url) do
          {:ok, job} ->
            new_jobs = Map.put(state.jobs, clean_target, job)
            m3u8_path = Path.join(job.dir, "live.m3u8")

            touch_ets_job_dir(clean_target, job.dir)

            {:reply, {:ok, m3u8_path}, %{state | jobs: new_jobs}}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  @impl true
  def handle_call({:is_running?, clean_target}, _from, state) do
    {:reply, Map.has_key?(state.jobs, clean_target), state}
  end

  @impl true
  def handle_call({:get_segment, target, segment_name}, _from, state) do
    clean_target = sanitize_target(target)
    # De-obfuscate deceptive asset names (e.g. avatar_xxx.webp -> seg_xxx.ts)
    raw_segment = SegmentObfuscator.deobfuscate(Path.basename(segment_name))

    segment_path =
      case Map.get(state.jobs, clean_target) do
        %{dir: dir} ->
          Path.join(dir, raw_segment)

        nil ->
          # Check fallback directory if job just exited or restarted
          Path.join([cast_base_dir(), clean_target, raw_segment])
      end

    if File.exists?(segment_path) do
      {:reply, {:ok, segment_path}, state}
    else
      if Map.has_key?(state.jobs, clean_target) do
        {:reply, {:error, :not_found}, state}
      else
        {:reply, {:error, :not_running}, state}
      end
    end
  end

  @impl true
  def handle_cast({:stop_remuxer, target}, state) do
    clean_target = sanitize_target(target)

    case Map.get(state.jobs, clean_target) do
      %{port: port, os_pid: os_pid, dir: dir} ->
        terminate_job(port, os_pid, dir, clean_target)
        {:noreply, %{state | jobs: Map.delete(state.jobs, clean_target)}}

      nil ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:sweep, state) do
    now = System.monotonic_time(:second)

    {kept_jobs, expired_jobs} =
      Enum.split_with(state.jobs, fn {_target, job} ->
        now - job.last_accessed <= @inactivity_timeout_s
      end)

    Enum.each(expired_jobs, fn {target, job} ->
      Logger.info(
        "[CastRemuxer] Inactivity timeout (#{@inactivity_timeout_s}s) reached for '#{target}'. Terminating remuxer."
      )

      terminate_job(job.port, job.os_pid, job.dir, target)
    end)

    schedule_sweep()
    {:noreply, %{state | jobs: Map.new(kept_jobs)}}
  end

  @impl true
  def handle_info(:prewarm_tick, state) do
    # Continuously refresh in-memory ETS manifests for active streams in the background
    Enum.each(state.jobs, fn {target, job} ->
      sync_manifest(target, job.dir)
    end)

    new_jobs =
      Enum.into(state.jobs, %{}, fn {target, job} ->
        updated_job = maybe_prewarm_job(target, job)
        {target, updated_job}
      end)

    schedule_prewarm()
    {:noreply, %{state | jobs: new_jobs}}
  end

  @benign_ffmpeg_warnings [
    "decode_slice_header",
    "no frame!",
    "non-existing PPS",
    "Last message repeated"
  ]

  @impl true
  def handle_info({port, {:data, msg}}, state) when is_port(port) do
    if is_binary(msg) and String.contains?(msg, ["Error", "error", "Fatal", "fatal"]) do
      # Ignore transient H.264 slice decoding warnings before first keyframe
      is_benign = Enum.any?(@benign_ffmpeg_warnings, &String.contains?(msg, &1))

      unless is_benign do
        Logger.warning("[CastRemuxer:FFmpeg] #{String.trim(msg)}")
      end
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({port, {:exit_status, status}}, state) when is_port(port) do
    case Enum.find(state.jobs, fn {_target, job} -> job.port == port end) do
      {target, job} ->
        Logger.warning(
          "[CastRemuxer] FFmpeg remuxer for '#{target}' exited with status #{status}"
        )

        # Do not delete segments immediately on process exit; players need to drain existing segments
        # while reconnecting or restarting. Schedule a delayed purge if not restarted.
        Process.send_after(self(), {:delayed_cleanup_dir, job.dir, target}, 60_000)
        {:noreply, %{state | jobs: Map.delete(state.jobs, target)}}

      nil ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:delayed_cleanup_dir, dir, target}, state) do
    # Only clean up if target has not been restarted
    unless Map.has_key?(state.jobs, target) do
      :ets.delete(@manifest_table, target)
      cleanup_dir(dir)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:EXIT, _pid, _reason}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    Logger.info("[CastRemuxer] Application stopping. Cleaning up active Chromecast remuxers...")

    Enum.each(state.jobs, fn {target, job} ->
      terminate_job(job.port, job.os_pid, job.dir, target)
    end)

    :ok
  end

  # --- Internal Helpers ---

  @doc false
  def cast_base_dir do
    case System.get_env("CAST_CACHE_DIR") do
      dir when is_binary(dir) and dir != "" ->
        dir

      _ ->
        # Prefer RAM-disk (/dev/shm) on Linux for zero disk wear and ultra-fast I/O
        if File.dir?("/dev/shm") do
          "/dev/shm/acex_cast"
        else
          Path.join(System.tmp_dir!(), "acex_cast")
        end
    end
  end

  defp start_ffmpeg_job(target, base_url) do
    ffmpeg_bin = System.find_executable("ffmpeg")

    if ffmpeg_bin == nil do
      {:error, :ffmpeg_not_found}
    else
      base_dir = cast_base_dir()
      job_dir = Path.join(base_dir, target)
      File.mkdir_p!(job_dir)

      port_num =
        case AcexGateway.Config.proxy_port() do
          p when is_integer(p) and p > 0 -> p
          _ -> 8686
        end

      input_url =
        if AcexGateway.Config.auth_enabled?() do
          user = AcexGateway.Config.auth_username()
          pass = AcexGateway.Config.auth_password()

          "http://127.0.0.1:#{port_num}/live/#{URI.encode_www_form(user)}/#{URI.encode_www_form(pass)}/#{target}.ts"
        else
          "http://127.0.0.1:#{port_num}/live/#{target}.ts"
        end

      session_epoch = System.system_time(:second)
      output_m3u8 = Path.join(job_dir, "live.m3u8")
      segment_pattern = Path.join(job_dir, "seg_#{session_epoch}_%05d.ts")

      args = [
        "-hide_banner",
        "-loglevel",
        "warning",
        "-err_detect",
        "ignore_err",
        "-fflags",
        "+nobuffer+flush_packets+genpts+discardcorrupt",
        "-probesize",
        "1000000",
        "-analyzeduration",
        "1000000",
        "-reconnect",
        "1",
        "-reconnect_at_eof",
        "1",
        "-reconnect_streamed",
        "1",
        "-reconnect_delay_max",
        "2",
        "-i",
        input_url,
        "-c:v",
        "copy",
        "-bsf:v",
        "dump_extra",
        "-c:a",
        "aac",
        "-b:a",
        "128k",
        "-af",
        "aresample=async=1000",
        "-sn",
        "-dn",
        "-f",
        "hls",
        "-hls_time",
        "3",
        "-hls_list_size",
        "20",
        "-hls_delete_threshold",
        "15",
        "-hls_base_url",
        "/cast/#{target}/",
        "-hls_flags",
        "delete_segments+temp_file+independent_segments+omit_endlist+append_list",
        "-hls_segment_type",
        "mpegts",
        "-hls_segment_filename",
        segment_pattern,
        output_m3u8
      ]

      Logger.info("[CastRemuxer] Spawning on-demand FFmpeg remuxer for '#{target}'...")

      try do
        port =
          Port.open(
            {:spawn_executable, ffmpeg_bin},
            [:binary, :exit_status, :stderr_to_stdout, args: args]
          )

        os_pid =
          case Port.info(port, :os_pid) do
            {:os_pid, pid} -> pid
            _ -> nil
          end

        {:ok,
         %{
           port: port,
           os_pid: os_pid,
           dir: job_dir,
           last_accessed: System.monotonic_time(:second),
           base_url: effective_base_url(base_url),
           prewarmed: MapSet.new()
         }}
      rescue
        e ->
          Logger.error("[CastRemuxer] Failed to spawn FFmpeg: #{inspect(e)}")
          cleanup_dir(job_dir)
          {:error, :spawn_failed}
      end
    end
  end

  defp touch_ets_job_dir(target, dir) do
    case :ets.lookup(@manifest_table, target) do
      [{^target, data}] ->
        :ets.insert(@manifest_table, {target, Map.put(data, :dir, dir)})

      [] ->
        :ets.insert(
          @manifest_table,
          {target,
           %{
             dir: dir,
             manifest: nil,
             segments: [],
             media_sequence: 0,
             target_duration: 4,
             updated_at: 0
           }}
        )
    end
  rescue
    _ -> :ok
  end

  defp fetch_or_wait_manifest(
         clean_target,
         job_dir,
         start_time \\ System.monotonic_time(:millisecond)
       ) do
    elapsed = System.monotonic_time(:millisecond) - start_time

    # Fast path: check if ETS already holds an ultra-fresh manifest (< 500ms)
    fast_cached =
      case lookup_manifest(clean_target) do
        {:ok, %{manifest: manifest, updated_at: updated_at}}
        when is_binary(manifest) and manifest != "" ->
          now = System.monotonic_time(:millisecond)
          if now - updated_at < 500, do: {:ok, manifest}, else: :stale

        _ ->
          :none
      end

    case fast_cached do
      {:ok, manifest} ->
        {:ok, manifest}

      _ ->
        case sync_manifest(clean_target, job_dir) do
          {:ok, manifest} ->
            {:ok, manifest}

          {:error, _reason} ->
            cond do
              not running?(clean_target) ->
                case lookup_manifest(clean_target) do
                  {:ok, %{manifest: manifest}} when is_binary(manifest) and manifest != "" ->
                    {:ok, manifest}

                  _ ->
                    {:error, :remuxer_exited}
                end

              elapsed > @max_startup_wait_ms ->
                case lookup_manifest(clean_target) do
                  {:ok, %{manifest: manifest}} when is_binary(manifest) and manifest != "" ->
                    {:ok, manifest}

                  _ ->
                    {:error, :manifest_timeout}
                end

              true ->
                Process.sleep(100)
                fetch_or_wait_manifest(clean_target, job_dir, start_time)
            end
        end
    end
  end

  @doc """
  Synchronizes the manifest for a target from disk (`live.m3u8` or completed `.ts` segments)
  into ETS. If disk `live.m3u8` is empty or mid-flush, falls back safely to cached ETS manifest
  or dynamically generates the manifest from finished disk segments.
  """
  def sync_manifest(target, dir) do
    clean_target = sanitize_target(target)
    m3u8_path = Path.join(dir, "live.m3u8")

    disk_result =
      case File.read(m3u8_path) do
        {:ok, content} when byte_size(content) > 0 ->
          if String.contains?(content, "#EXTINF") do
            {:ok, content}
          else
            :invalid
          end

        _ ->
          :invalid
      end

    case disk_result do
      {:ok, content} ->
        manifest_data = parse_manifest_data(clean_target, content, dir)
        :ets.insert(@manifest_table, {clean_target, manifest_data})
        {:ok, manifest_data.manifest}

      :invalid ->
        # Disk manifest is invalid/empty or currently being rewritten by FFmpeg.
        # Fallback to existing ETS cache (zero-stall fallback)
        case lookup_manifest(clean_target) do
          {:ok, %{manifest: manifest}} when is_binary(manifest) and manifest != "" ->
            {:ok, manifest}

          _ ->
            # No cached manifest in ETS yet (e.g. cold start).
            # Build dynamically from finished disk segments
            case build_dynamic_manifest_from_disk(clean_target, dir) do
              {:ok, dynamic_data} ->
                :ets.insert(@manifest_table, {clean_target, dynamic_data})
                {:ok, dynamic_data.manifest}

              :empty ->
                {:error, :no_segments_yet}
            end
        end
    end
  rescue
    _ -> {:error, :sync_failed}
  end

  @doc """
  Builds an HLS live manifest directly from finished `.ts` segment files in the job directory.
  Excludes the actively writing segment to avoid serving incomplete chunks.
  """
  def build_dynamic_manifest_from_disk(target, dir) do
    segments = list_disk_segments(dir)

    completed_segments =
      case segments do
        [] ->
          []

        [_single] ->
          []

        segs ->
          # Exclude the very latest segment which FFmpeg is actively recording into
          Enum.drop(segs, -1)
      end

    case completed_segments do
      [] ->
        :empty

      segs ->
        # Sliding window: keep up to 20 recent segments
        window_segs = Enum.take(segs, -20)
        {_first_name, first_seq, _size} = List.first(window_segs)

        formatted_segments =
          Enum.map(window_segs, fn {filename, _seq, _size} ->
            {filename, 3.0}
          end)

        manifest = build_manifest_string(target, 4, first_seq, formatted_segments)

        {:ok,
         %{
           target: target,
           dir: dir,
           manifest: manifest,
           segments: formatted_segments,
           media_sequence: first_seq,
           target_duration: 4,
           updated_at: System.monotonic_time(:millisecond)
         }}
    end
  end

  @doc """
  Lists all valid `.ts` segment files in a directory sorted by sequence number.
  """
  def list_disk_segments(dir) do
    case File.ls(dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".ts"))
        |> Enum.filter(&String.starts_with?(&1, "seg_"))
        |> Enum.map(fn filename ->
          path = Path.join(dir, filename)

          size =
            case File.stat(path) do
              {:ok, %File.Stat{size: s}} -> s
              _ -> 0
            end

          seq = parse_seq_from_filename(filename)
          {filename, seq, size}
        end)
        |> Enum.filter(fn {_name, _seq, size} -> size > 0 end)
        |> Enum.sort_by(fn {_name, seq, _size} -> seq end)

      _ ->
        []
    end
  end

  defp parse_seq_from_filename(filename) do
    case Regex.run(~r/_(\d+)\.ts$/, filename) do
      [_, seq_str] -> String.to_integer(seq_str)
      _ -> 0
    end
  end

  @doc """
  Composes a standard HLS v3 live playlist string from segment metadata.
  """
  def build_manifest_string(target, target_duration, media_sequence, segments) do
    header = [
      "#EXTM3U",
      "#EXT-X-VERSION:3",
      "#EXT-X-TARGETDURATION:#{target_duration}",
      "#EXT-X-MEDIA-SEQUENCE:#{media_sequence}",
      "#EXT-X-INDEPENDENT-SEGMENTS"
    ]

    entries =
      Enum.flat_map(segments, fn {filename, duration} ->
        dur_val = if is_number(duration), do: duration * 1.0, else: 3.0
        dur_str = :erlang.float_to_binary(dur_val, decimals: 6)

        [
          "#EXTINF:#{dur_str},",
          "/cast/#{target}/#{filename}"
        ]
      end)

    Enum.join(header ++ entries, "\n") <> "\n"
  end

  @doc """
  Parses an existing HLS manifest string into structured metadata.
  """
  def parse_manifest_data(target, content, dir) do
    lines = String.split(content, ["\r\n", "\n"], trim: true)
    target_duration = parse_target_duration(lines)
    media_sequence = parse_media_sequence(lines)
    segments = extract_segments_with_duration(lines)

    %{
      target: target,
      dir: dir,
      manifest: content,
      segments: segments,
      media_sequence: media_sequence,
      target_duration: target_duration,
      updated_at: System.monotonic_time(:millisecond)
    }
  end

  defp parse_target_duration(lines) do
    Enum.find_value(lines, 4, fn line ->
      case Regex.run(~r/#EXT-X-TARGETDURATION:(\d+)/, line) do
        [_, dur] -> String.to_integer(dur)
        _ -> nil
      end
    end)
  end

  defp parse_media_sequence(lines) do
    Enum.find_value(lines, 0, fn line ->
      case Regex.run(~r/#EXT-X-MEDIA-SEQUENCE:(\d+)/, line) do
        [_, seq] -> String.to_integer(seq)
        _ -> nil
      end
    end)
  end

  defp extract_segments_with_duration(lines) do
    {segments, _current_dur} =
      Enum.reduce(lines, {[], 3.0}, fn line, {acc, cur_dur} ->
        cond do
          String.starts_with?(line, "#EXTINF:") ->
            dur =
              case Regex.run(~r/#EXTINF:([0-9\.]+)/, line) do
                [_, d] ->
                  case Float.parse(d) do
                    {val, _} -> val
                    _ -> 3.0
                  end

                _ ->
                  3.0
              end

            {acc, dur}

          String.ends_with?(line, ".ts") and not String.starts_with?(line, "#") ->
            filename = Path.basename(line)
            {[{filename, cur_dur} | acc], 3.0}

          true ->
            {acc, cur_dur}
        end
      end)

    Enum.reverse(segments)
  end

  defp terminate_job(port, os_pid, dir, target) do
    if is_integer(os_pid) and os_pid > 0 do
      System.cmd("kill", ["-15", to_string(os_pid)], stderr_to_stdout: true)
      Process.sleep(100)
      System.cmd("kill", ["-9", to_string(os_pid)], stderr_to_stdout: true)
    end

    if is_port(port) do
      try do
        Port.close(port)
      rescue
        _ -> :ok
      end
    end

    if is_binary(target) do
      :ets.delete(@manifest_table, target)
    end

    cleanup_dir(dir)
  end

  defp cleanup_dir(dir) do
    if is_binary(dir) and File.exists?(dir) do
      File.rm_rf(dir)
    end
  end

  defp sanitize_target(target) when is_binary(target) do
    target
    |> String.trim()
    |> String.replace("..", "")
    |> String.replace(~r/[^a-zA-Z0-9_\-\.]/, "_")
  end

  defp sanitize_target(target), do: to_string(target)

  defp schedule_sweep do
    Process.send_after(self(), :sweep, @sweep_interval_ms)
  end

  defp schedule_prewarm do
    Process.send_after(self(), :prewarm_tick, @prewarm_interval_ms)
  end

  defp maybe_prewarm_job(target, %{dir: dir, base_url: base_url, prewarmed: prewarmed} = job) do
    warm_url = effective_base_url(base_url)

    if prewarm_eligible?(warm_url) do
      segments =
        case lookup_manifest(target) do
          {:ok, %{segments: seg_entries}} when is_list(seg_entries) and seg_entries != [] ->
            Enum.map(seg_entries, fn
              {name, _dur} -> name
              name when is_binary(name) -> name
            end)

          _ ->
            m3u8_path = Path.join(dir, "live.m3u8")

            case File.read(m3u8_path) do
              {:ok, content} -> parse_segments_from_manifest(content)
              {:error, _} -> []
            end
        end

      new_segments = Enum.reject(segments, &MapSet.member?(prewarmed, &1))

      Enum.each(new_segments, fn raw_segment ->
        # Pre-warm using the same obfuscated asset URL that clients receive
        obfuscated_name = SegmentObfuscator.obfuscate(raw_segment)
        trigger_prewarm_request(warm_url, target, obfuscated_name)
      end)

      # Retain only current segments in set to keep memory footprint minimal
      current_segment_set = MapSet.new(segments)

      updated_prewarmed =
        prewarmed
        |> MapSet.union(MapSet.new(new_segments))
        |> MapSet.intersection(current_segment_set)

      %{job | prewarmed: updated_prewarmed}
    else
      job
    end
  end

  defp maybe_prewarm_job(_target, job), do: job

  defp parse_segments_from_manifest(content) do
    content
    |> String.split(["\n", "\r\n"], trim: true)
    |> Enum.filter(&String.ends_with?(&1, ".ts"))
    |> Enum.map(&Path.basename/1)
  end

  defp trigger_prewarm_request(base_url, target, segment_name) do
    clean_base = String.trim_trailing(base_url, "/")
    url = "#{clean_base}/cast/#{target}/#{segment_name}"

    Task.start(fn ->
      try do
        Logger.debug("[CastRemuxer] Pre-warming CDN segment: #{url}")

        Req.get(url,
          headers: [
            {"user-agent", "AcexGateway-Prewarmer/1.0"},
            {"x-purpose", "preview"}
          ],
          into: fn {:data, _chunk}, acc -> {:cont, acc} end,
          receive_timeout: 10_000,
          connect_options: [timeout: 5_000]
        )
      rescue
        _ -> :ok
      catch
        :exit, _ -> :ok
      end
    end)
  end

  defp prewarm_eligible?(base_url) when is_binary(base_url) and base_url != "" do
    if AcexGateway.Config.prewarm_enabled?() do
      uri = URI.parse(base_url)
      host = uri.host || ""

      uri.scheme in ["http", "https"] and not private_ip_or_local?(host)
    else
      false
    end
  end

  defp prewarm_eligible?(_), do: false

  defp private_ip_or_local?(host) when is_binary(host) do
    host in ["localhost", "127.0.0.1", "0.0.0.0", ""] or
      String.ends_with?(host, ".local") or
      String.starts_with?(host, ["10.", "192.168.", "169.254."]) or
      Regex.match?(~r/^172\.(1[6-9]|2[0-9]|3[0-1])\./, host)
  end

  defp private_ip_or_local?(_), do: true

  defp effective_base_url(base_url) do
    System.get_env("CAST_PREWARM_BASE_URL") || base_url
  end
end
