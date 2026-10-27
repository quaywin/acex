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

  @sweep_interval_ms 10_000
  @inactivity_timeout_s 30
  @max_startup_wait_ms 4_000

  # --- Client API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Checks if FFmpeg binary is installed and executable on the host system.
  """
  def ffmpeg_available? do
    System.find_executable("ffmpeg") != nil
  end

  @doc """
  Ensures an HLS remuxer process is running for the given stream target,
  waits for initial manifest creation, and returns the path to `live.m3u8`.
  """
  def get_playlist(target) do
    if ffmpeg_available?() do
      GenServer.call(__MODULE__, {:get_playlist, target}, 10_000)
    else
      {:error, :ffmpeg_not_found}
    end
  end

  @doc """
  Touches the target to refresh its last-accessed timestamp and returns
  the absolute path of the requested segment file.
  """
  def get_segment(target, segment_name) do
    GenServer.call(__MODULE__, {:get_segment, target, segment_name})
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
    schedule_sweep()
    {:ok, %{jobs: %{}}}
  end

  @impl true
  def handle_call({:get_playlist, target}, _from, state) do
    clean_target = sanitize_target(target)
    now = System.monotonic_time(:second)

    case Map.get(state.jobs, clean_target) do
      %{dir: dir} = job ->
        updated_job = %{job | last_accessed: now}
        new_jobs = Map.put(state.jobs, clean_target, updated_job)
        m3u8_path = Path.join(dir, "live.m3u8")

        case wait_for_manifest(m3u8_path) do
          :ok ->
            {:reply, {:ok, m3u8_path}, %{state | jobs: new_jobs}}

          {:error, reason} ->
            {:reply, {:error, reason}, %{state | jobs: new_jobs}}
        end

      nil ->
        case start_ffmpeg_job(clean_target) do
          {:ok, job} ->
            new_jobs = Map.put(state.jobs, clean_target, job)
            m3u8_path = Path.join(job.dir, "live.m3u8")

            case wait_for_manifest(m3u8_path) do
              :ok ->
                {:reply, {:ok, m3u8_path}, %{state | jobs: new_jobs}}

              {:error, reason} ->
                {:reply, {:error, reason}, %{state | jobs: new_jobs}}
            end

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  @impl true
  def handle_call({:get_segment, target, segment_name}, _from, state) do
    clean_target = sanitize_target(target)
    clean_segment = Path.basename(segment_name)
    now = System.monotonic_time(:second)

    case Map.get(state.jobs, clean_target) do
      %{dir: dir} = job ->
        updated_job = %{job | last_accessed: now}
        new_jobs = Map.put(state.jobs, clean_target, updated_job)
        segment_path = Path.join(dir, clean_segment)

        if File.exists?(segment_path) do
          {:reply, {:ok, segment_path}, %{state | jobs: new_jobs}}
        else
          {:reply, {:error, :not_found}, %{state | jobs: new_jobs}}
        end

      nil ->
        {:reply, {:error, :not_running}, state}
    end
  end

  @impl true
  def handle_cast({:stop_remuxer, target}, state) do
    clean_target = sanitize_target(target)

    case Map.get(state.jobs, clean_target) do
      %{port: port, os_pid: os_pid, dir: dir} ->
        terminate_job(port, os_pid, dir)
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
        "[CastRemuxer] Inactivity timeout (30s) reached for '#{target}'. Terminating remuxer."
      )

      terminate_job(job.port, job.os_pid, job.dir)
    end)

    schedule_sweep()
    {:noreply, %{state | jobs: Map.new(kept_jobs)}}
  end

  @impl true
  def handle_info({port, {:data, _msg}}, state) when is_port(port) do
    {:noreply, state}
  end

  @impl true
  def handle_info({port, {:exit_status, status}}, state) when is_port(port) do
    case Enum.find(state.jobs, fn {_target, job} -> job.port == port end) do
      {target, job} ->
        Logger.warning(
          "[CastRemuxer] FFmpeg remuxer for '#{target}' exited with status #{status}"
        )

        cleanup_dir(job.dir)
        {:noreply, %{state | jobs: Map.delete(state.jobs, target)}}

      nil ->
        {:noreply, state}
    end
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

    Enum.each(state.jobs, fn {_target, job} ->
      terminate_job(job.port, job.os_pid, job.dir)
    end)

    :ok
  end

  # --- Internal Helpers ---

  defp start_ffmpeg_job(target) do
    ffmpeg_bin = System.find_executable("ffmpeg")

    if ffmpeg_bin == nil do
      {:error, :ffmpeg_not_found}
    else
      base_dir = Path.join(System.tmp_dir!(), "acex_cast")
      job_dir = Path.join(base_dir, target)
      File.mkdir_p!(job_dir)

      # Clean existing stale files in target dir
      cleanup_manifests(job_dir)

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

      output_m3u8 = Path.join(job_dir, "live.m3u8")
      segment_pattern = Path.join(job_dir, "seg_%03d.ts")

      args = [
        "-hide_banner",
        "-loglevel",
        "warning",
        "-re",
        "-i",
        input_url,
        "-c:v",
        "copy",
        "-c:a",
        "aac",
        "-b:a",
        "128k",
        "-f",
        "hls",
        "-hls_time",
        "2",
        "-hls_list_size",
        "4",
        "-hls_flags",
        "delete_segments+temp_file",
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
           last_accessed: System.monotonic_time(:second)
         }}
      rescue
        e ->
          Logger.error("[CastRemuxer] Failed to spawn FFmpeg: #{inspect(e)}")
          cleanup_dir(job_dir)
          {:error, :spawn_failed}
      end
    end
  end

  defp wait_for_manifest(m3u8_path, start_time \\ System.monotonic_time(:millisecond)) do
    elapsed = System.monotonic_time(:millisecond) - start_time

    cond do
      manifest_ready?(m3u8_path) ->
        :ok

      elapsed > @max_startup_wait_ms ->
        # If manifest exists even partially, allow it; else timeout
        if File.exists?(m3u8_path) do
          :ok
        else
          {:error, :manifest_timeout}
        end

      true ->
        Process.sleep(150)
        wait_for_manifest(m3u8_path, start_time)
    end
  end

  defp manifest_ready?(path) do
    if File.exists?(path) do
      case File.read(path) do
        {:ok, content} ->
          String.contains?(content, "#EXTINF")

        _ ->
          false
      end
    else
      false
    end
  end

  defp terminate_job(port, os_pid, dir) do
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

    cleanup_dir(dir)
  end

  defp cleanup_dir(dir) do
    if is_binary(dir) and File.exists?(dir) do
      File.rm_rf(dir)
    end
  end

  defp cleanup_manifests(dir) do
    if File.exists?(dir) do
      case File.ls(dir) do
        {:ok, files} ->
          Enum.each(files, fn f -> File.rm(Path.join(dir, f)) end)

        _ ->
          :ok
      end
    end
  end

  defp sanitize_target(target) when is_binary(target) do
    target
    |> String.trim()
    |> String.replace(~r/[^a-zA-Z0-9_\-\.]/, "_")
  end

  defp sanitize_target(target), do: to_string(target)

  defp schedule_sweep do
    Process.send_after(self(), :sweep, @sweep_interval_ms)
  end
end
