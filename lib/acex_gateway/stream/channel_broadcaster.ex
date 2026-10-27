defmodule AcexGateway.Stream.ChannelBroadcaster do
  @moduledoc """
  Independent Channel Broadcaster process managing an isolated AceStream session,
  RingBuffer cache, upstream fetch, and subscriber fan-out.
  """

  use GenServer, restart: :transient
  require Logger

  alias AcexGateway.Config
  alias AcexGateway.Channels.Store
  alias AcexGateway.Engine.Protocol
  alias AcexGateway.Stream.RingBuffer

  # Client API

  def via_tuple(channel_key) do
    {:via, Registry, {AcexGateway.ChannelRegistry, channel_key}}
  end

  def start_link(opts) do
    channel_key = Keyword.fetch!(opts, :channel_key)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(channel_key))
  end

  def subscribe(server, client_pid \\ self(), timeout \\ 70_000) do
    GenServer.call(server, {:subscribe, client_pid}, timeout)
  end

  def unsubscribe(server, client_pid \\ self()) do
    GenServer.cast(server, {:unsubscribe, client_pid})
  end

  def dispatch_chunk(server, chunk) when is_binary(chunk) do
    GenServer.cast(server, {:dispatch_chunk, chunk})
  end

  def get_info(server) do
    GenServer.call(server, :get_info)
  end

  def force_stop(server) do
    ref = Process.monitor(server)

    try do
      GenServer.call(server, :force_stop)
    catch
      :exit, _ -> :ok
    end

    receive do
      {:DOWN, ^ref, :process, ^server, _} -> :ok
    after
      2000 -> :ok
    end
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    channel_key = Keyword.fetch!(opts, :channel_key)
    target = Keyword.get(opts, :target, channel_key)
    sources = Keyword.get(opts, :sources, [target])
    source_type = Keyword.get(opts, :source_type, :content_id)
    channel_name = Keyword.get(opts, :channel_name) || resolve_channel_name(channel_key, target)

    state = %{
      channel_key: channel_key,
      channel_name: channel_name,
      target: target,
      sources: sources,
      source_index: 0,
      source_type: source_type,
      status: :starting,
      socket: nil,
      authenticated: false,
      http_port: 6878,
      playback_url: nil,
      active_hash: nil,
      canonical_hash: nil,
      consumers: %{},
      pending_subscribers: [],
      upstream_task: nil,
      cooldown_timer: nil,
      start_timer: nil,
      early_failover_timer: nil,
      ring_buffer: RingBuffer.new(Config.ring_buffer_bytes()),
      bytes_transferred: 0,
      peers: 0,
      speed_kbps: 0,
      progress: 0,
      engine_state: :idle,
      source_promoted: false,
      cycle_count: 0
    }

    send(self(), :connect_telnet)
    {:ok, state}
  end

  @impl true
  def handle_call({:subscribe, client_pid}, from, state) do
    cond do
      state.status in [:streaming, :cooldown] ->
        state = cancel_cooldown(state)
        ref = Process.monitor(client_pid)
        new_consumers = Map.put(state.consumers, client_pid, ref)

        # Flush RingBuffer keyframe chunks for instant playback as a consolidated burst
        chunks = RingBuffer.to_chunks(state.ring_buffer)

        if chunks != [] do
          send(client_pid, {:stream_burst, chunks})
        end

        Logger.info(
          "[ChannelBroadcaster:#{state.channel_key}] Client #{inspect(client_pid)} subscribed. Total: #{map_size(new_consumers)}"
        )

        {:reply, {:ok, :joined_active_stream},
         %{state | consumers: new_consumers, status: :streaming}}

      state.status == :starting ->
        Logger.info(
          "[ChannelBroadcaster:#{state.channel_key}] Client #{inspect(client_pid)} queued for pending stream"
        )

        new_pending = [{client_pid, from} | state.pending_subscribers]
        {:noreply, %{state | pending_subscribers: new_pending}}
    end
  end

  def handle_call(:get_info, _from, state) do
    client_count = map_size(state.consumers) + length(state.pending_subscribers)

    {resolved_name, resolved_logo} =
      case Store.get_channel(state.channel_key) do
        %{"name" => name, "logo" => logo} ->
          {name || state.channel_name, logo}

        %{"name" => name} ->
          {name || state.channel_name, nil}

        nil ->
          {state.channel_name, nil}
      end

    info = %{
      channel_key: state.channel_key,
      channel_name: resolved_name,
      channel_logo: resolved_logo,
      target: state.target,
      status: state.status,
      active_channel: state.active_hash || state.channel_key,
      source_type: state.source_type,
      client_count: client_count,
      bytes_transferred: state.bytes_transferred,
      buffered_bytes: state.ring_buffer.total_bytes,
      source_index: state.source_index,
      total_sources: length(state.sources),
      peers: state.peers,
      speed_kbps: state.speed_kbps,
      progress: state.progress,
      engine_state: state.engine_state,
      playback_url: state.playback_url
    }

    {:reply, info, state}
  end

  def handle_call(:force_stop, _from, state) do
    Logger.info("[ChannelBroadcaster:#{state.channel_key}] Force stop requested.")
    {:stop, :normal, :ok, state}
  end

  @impl true
  def handle_cast({:unsubscribe, pid}, state) do
    new_state = handle_consumer_disconnect(pid, state)
    {:noreply, new_state}
  end

  def handle_cast(
        {:dispatch_chunk, chunk},
        %{status: :streaming, source_promoted: false} = state
      ) do
    state = maybe_promote_source(state)
    handle_cast({:dispatch_chunk, chunk}, state)
  end

  def handle_cast({:dispatch_chunk, chunk}, %{status: :streaming} = state) do
    new_ring_buffer = RingBuffer.push(state.ring_buffer, chunk)

    # Fan-out to all active consumers (zero-copy refc binaries)
    for {pid, _ref} <- state.consumers do
      send(pid, {:stream_chunk, chunk})
    end

    new_bytes = state.bytes_transferred + byte_size(chunk)
    {:noreply, %{state | ring_buffer: new_ring_buffer, bytes_transferred: new_bytes}}
  end

  def handle_cast({:dispatch_chunk, _chunk}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info(:connect_telnet, state) do
    host = to_charlist(Config.telnet_host())
    port = Config.telnet_port()

    case :gen_tcp.connect(host, port, [:binary, packet: :line, active: true], 5000) do
      {:ok, socket} ->
        :gen_tcp.send(socket, "HELLOBG version=4\r\n")
        timer = Process.send_after(self(), :start_timeout, Config.start_timeout_ms())
        {:noreply, %{state | socket: socket, authenticated: false, start_timer: timer}}

      {:error, reason} ->
        Logger.error(
          "[ChannelBroadcaster:#{state.channel_key}] Failed to connect to AceStream Telnet at #{Config.telnet_host()}:#{port}: #{inspect(reason)}"
        )

        abort_pending_subscribers(state.pending_subscribers, {:error, :engine_not_connected})
        {:stop, :normal, state}
    end
  end

  def handle_info(:start_timeout, state) do
    Logger.error(
      "[ChannelBroadcaster:#{state.channel_key}] Stream start timed out after #{Config.start_timeout_ms()}ms"
    )

    trigger_failover(state, :start_timeout)
  end

  def handle_info(:early_failover_check, state) do
    if state.status == :starting do
      has_backup = state.source_index + 1 < length(state.sources)

      if has_backup and state.peers == 0 and state.speed_kbps == 0 do
        Logger.warning(
          "[ChannelBroadcaster:#{state.channel_key}] Fast failover: Source #{state.source_index + 1} has 0 peers after #{Config.early_failover_timeout_ms()}ms. Switching to fallback #{state.source_index + 2}/#{length(state.sources)}..."
        )

        trigger_failover(state, :zero_peers_fast_failover)
      else
        if state.peers > 0 do
          Logger.info(
            "[ChannelBroadcaster:#{state.channel_key}] Early check passed: #{state.peers} peer(s) found. Continuing startup."
          )
        end

        {:noreply, %{state | early_failover_timer: nil}}
      end
    else
      {:noreply, %{state | early_failover_timer: nil}}
    end
  end

  def handle_info({:tcp, socket, line}, %{socket: socket} = state) do
    line_clean = String.trim(line)

    case process_telnet_line(line_clean, state) do
      {:stop, reason, new_state} ->
        {:stop, reason, new_state}

      {:noreply, new_state} ->
        {:noreply, new_state}

      %{} = new_state ->
        {:noreply, new_state}
    end
  end

  def handle_info({:tcp_closed, socket}, %{socket: socket} = state) do
    Logger.warning(
      "[ChannelBroadcaster:#{state.channel_key}] Telnet connection closed by engine."
    )

    if state.status == :starting do
      abort_pending_subscribers(state.pending_subscribers, {:error, :engine_disconnected})
      {:stop, :normal, %{state | socket: nil}}
    else
      {:stop, :normal, %{state | socket: nil}}
    end
  end

  def handle_info({:tcp_error, socket, reason}, %{socket: socket} = state) do
    Logger.error(
      "[ChannelBroadcaster:#{state.channel_key}] Telnet socket error: #{inspect(reason)}"
    )

    if state.status == :starting do
      abort_pending_subscribers(state.pending_subscribers, {:error, reason})
      {:stop, :normal, %{state | socket: nil}}
    else
      {:stop, :normal, %{state | socket: nil}}
    end
  end

  def handle_info({:DOWN, ref, :process, pid, _reason}, state) do
    Process.demonitor(ref, [:flush])
    new_state = handle_consumer_disconnect(pid, state)
    {:noreply, new_state}
  end

  def handle_info(:grace_period_expired, state) do
    if map_size(state.consumers) == 0 do
      Logger.info(
        "[ChannelBroadcaster:#{state.channel_key}] Grace period expired with 0 viewers. Shutting down stream."
      )

      {:stop, :normal, state}
    else
      {:noreply, %{state | status: :streaming, cooldown_timer: nil}}
    end
  end

  def handle_info({:upstream_completed, reason}, state) do
    Logger.warning(
      "[ChannelBroadcaster:#{state.channel_key}] Upstream stream completed: #{inspect(reason)}"
    )

    trigger_failover(state, reason)
  end

  def handle_info(_other, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    Registry.unregister(AcexGateway.ChannelRegistry, state.channel_key)

    if state.cooldown_timer, do: Process.cancel_timer(state.cooldown_timer)
    if state.start_timer, do: Process.cancel_timer(state.start_timer)
    if state.early_failover_timer, do: Process.cancel_timer(state.early_failover_timer)

    if state.upstream_task do
      Process.exit(state.upstream_task, :shutdown)
    end

    for {pid, ref} <- state.consumers do
      Process.demonitor(ref, [:flush])
      send(pid, {:stream_closed, :stream_terminated})
    end

    abort_pending_subscribers(state.pending_subscribers, {:error, :stream_terminated})

    if state.socket do
      safe_tcp_send(state.socket, "STOP\r\n")
      safe_tcp_send(state.socket, "STOPDL\r\n")
      safe_tcp_close(state.socket)
    end

    :ok
  end

  # Telnet Protocol Processing

  defp process_telnet_line("HELLOTS " <> _ = line, state) do
    %{key: req_key, http_port: http_port} = Protocol.parse_hellots(line)
    ready_key = Protocol.compute_ready_key(req_key, Config.product_key())
    safe_tcp_send(state.socket, "READY key=#{ready_key}\r\n")
    %{state | http_port: http_port}
  end

  defp process_telnet_line("AUTH " <> _auth_info, state) do
    safe_tcp_send(state.socket, "SETOPTIONS use_stop_notifications=1\r\n")
    dispatch_load_for_current_source(%{state | authenticated: true})
  end

  defp process_telnet_line("NOTREADY", state) do
    Logger.error("[ChannelBroadcaster:#{state.channel_key}] Engine returned NOTREADY.")
    trigger_failover(state, :not_ready)
  end

  defp process_telnet_line("LOADRESP " <> _ = line, state) do
    case Protocol.parse_loadresp(line) do
      {:error, reason} ->
        Logger.warning(
          "[ChannelBroadcaster:#{state.channel_key}] Engine reported LOAD error: #{inspect(reason)}. Fast failover."
        )

        trigger_failover(state, {:load_error, reason})

      {:ok, canonical_hash} ->
        dispatch_start_stream(state, canonical_hash)

      :none ->
        dispatch_start_stream(state, state.canonical_hash)
    end
  end

  defp process_telnet_line("START " <> _ = line, state) do
    Logger.info("[ChannelBroadcaster:#{state.channel_key}] Received START response: #{line}")

    case Protocol.parse_start_url(line) do
      {:ok, playback_url} ->
        if state.start_timer, do: Process.cancel_timer(state.start_timer)
        if state.early_failover_timer, do: Process.cancel_timer(state.early_failover_timer)

        current_hash = Enum.at(state.sources, state.source_index)

        # Register all pending subscribers while keeping any existing viewers
        new_consumers =
          Enum.reduce(state.pending_subscribers, state.consumers, fn {pid, from}, acc ->
            ref = Process.monitor(pid)
            GenServer.reply(from, {:ok, :stream_started})
            Map.put(acc, pid, ref)
          end)

        task = start_upstream_fetch(playback_url)

        %{
          state
          | status: :streaming,
            playback_url: playback_url,
            active_hash: current_hash,
            consumers: new_consumers,
            pending_subscribers: [],
            upstream_task: task,
            start_timer: nil,
            early_failover_timer: nil
        }

      :error ->
        trigger_failover(state, :invalid_start_url)
    end
  end

  defp process_telnet_line("STATE " <> _ = line, state) do
    case Protocol.parse_state(line) do
      {:ok, engine_state, _code} ->
        Logger.info(
          "[ChannelBroadcaster:#{state.channel_key}] Engine state changed: #{engine_state}"
        )

        %{state | engine_state: engine_state}

      {:error, :engine_error, _code} ->
        Logger.warning(
          "[ChannelBroadcaster:#{state.channel_key}] Engine reported fatal error (STATE 6)."
        )

        trigger_failover(state, :engine_state_error)

      _ ->
        state
    end
  end

  defp process_telnet_line("EVENT showdialog" <> rest = line, state) do
    Logger.warning("[ChannelBroadcaster:#{state.channel_key}] Engine returned dialog: #{line}")

    reason =
      case Regex.run(~r/text=([^\s]+)/, rest) do
        [_, encoded] -> URI.decode(encoded)
        _ -> "dialog_constraint"
      end

    trigger_failover(state, reason)
  end

  defp process_telnet_line("EVENT download_stopped" <> _, state) do
    if state.status == :starting do
      Logger.warning(
        "[ChannelBroadcaster:#{state.channel_key}] Engine stopped download prematurely during startup."
      )

      trigger_failover(state, :download_stopped)
    else
      state
    end
  end

  defp process_telnet_line("STATUS " <> _ = line, state) do
    stats = Protocol.parse_status(line)
    new_peers = Map.get(stats, :peers, state.peers)
    new_speed = Map.get(stats, :speed_kbps, state.speed_kbps)
    new_progress = Map.get(stats, :progress, state.progress)
    new_engine_state = Map.get(stats, :engine_state, state.engine_state)

    updated_state = %{
      state
      | peers: new_peers,
        speed_kbps: new_speed,
        progress: new_progress,
        engine_state: new_engine_state
    }

    if new_engine_state == :error do
      Logger.warning(
        "[ChannelBroadcaster:#{state.channel_key}] Engine reported error status (STATUS main:error)."
      )

      trigger_failover(updated_state, :engine_status_error)
    else
      updated_state
    end
  end

  defp process_telnet_line(_other, state) do
    state
  end

  # Helpers

  defp dispatch_start_stream(state, canonical_hash) do
    current_hash = Enum.at(state.sources, state.source_index)

    start_cmd =
      if canonical_hash do
        "START INFOHASH #{canonical_hash} 0 0 0 0 output_format=http\r\n"
      else
        "START PID #{current_hash} 0 output_format=http\r\n"
      end

    Logger.info(
      "[ChannelBroadcaster:#{state.channel_key}] Dispatching: #{String.trim(start_cmd)}"
    )

    safe_tcp_send(state.socket, start_cmd)

    if state.start_timer, do: Process.cancel_timer(state.start_timer)
    if state.early_failover_timer, do: Process.cancel_timer(state.early_failover_timer)

    new_timer = Process.send_after(self(), :start_timeout, Config.start_timeout_ms())

    new_early_timer =
      Process.send_after(self(), :early_failover_check, Config.early_failover_timeout_ms())

    %{
      state
      | canonical_hash: canonical_hash,
        start_timer: new_timer,
        early_failover_timer: new_early_timer
    }
  end

  defp trigger_failover(state, reason) do
    if state.start_timer, do: Process.cancel_timer(state.start_timer)
    if state.early_failover_timer, do: Process.cancel_timer(state.early_failover_timer)

    if state.socket do
      safe_tcp_send(state.socket, "STOP\r\n")
      safe_tcp_send(state.socket, "STOPDL\r\n")
    end

    if state.upstream_task do
      Process.exit(state.upstream_task, :shutdown)
    end

    {state, next_index, total_sources} =
      case reason do
        {:load_error, err} when length(state.sources) > 1 ->
          dead_source = Enum.at(state.sources, state.source_index)

          if dead_source do
            Logger.warning(
              "[ChannelBroadcaster:#{state.channel_key}] Fatal LOAD error for source #{dead_source}: #{inspect(err)}. Auto-pruning dead source from Store..."
            )

            Store.prune_dead_source(state.channel_key, dead_source)
            remaining = Enum.reject(state.sources, &(&1 == dead_source))
            {%{state | sources: remaining}, state.source_index, length(remaining)}
          else
            {state, state.source_index + 1, length(state.sources)}
          end

        _ ->
          {state, state.source_index + 1, length(state.sources)}
      end

    cond do
      # 1. Advance to next backup source in the list
      next_index < total_sources ->
        Logger.warning(
          "[ChannelBroadcaster:#{state.channel_key}] Source #{state.source_index + 1} failed (#{inspect(reason)}). Trying fallback #{next_index + 1}/#{total_sources}..."
        )

        new_state = %{
          state
          | status: :starting,
            source_index: next_index,
            source_promoted: false,
            peers: 0,
            speed_kbps: 0,
            progress: 0,
            engine_state: :idle,
            canonical_hash: nil,
            playback_url: nil,
            upstream_task: nil,
            start_timer: nil,
            early_failover_timer: nil
        }

        {:noreply, dispatch_load_for_current_source(new_state)}

      # 2. Reached end of source list, but viewers are actively watching and cycle_count < 1: wrap around ONCE
      next_index >= total_sources and total_sources > 1 and map_size(state.consumers) > 0 and
          state.cycle_count < 1 ->
        Logger.warning(
          "[ChannelBroadcaster:#{state.channel_key}] Reached end of backup sources. Active viewers: #{map_size(state.consumers)}. Attempting 1 bounded wrap-around cycle starting from primary source..."
        )

        new_state = %{
          state
          | status: :starting,
            source_index: 0,
            cycle_count: state.cycle_count + 1,
            source_promoted: false,
            peers: 0,
            speed_kbps: 0,
            progress: 0,
            engine_state: :idle,
            canonical_hash: nil,
            playback_url: nil,
            upstream_task: nil,
            start_timer: nil,
            early_failover_timer: nil
        }

        {:noreply, dispatch_load_for_current_source(new_state)}

      # 3. Exhausted all attempts or no consumers watching: terminate cleanly
      true ->
        Logger.error(
          "[ChannelBroadcaster:#{state.channel_key}] Stream ended or all #{total_sources} source(s) exhausted (cycles: #{state.cycle_count}). Final error: #{inspect(reason)}"
        )

        for {pid, ref} <- state.consumers do
          Process.demonitor(ref, [:flush])
          send(pid, {:stream_closed, reason})
        end

        abort_pending_subscribers(state.pending_subscribers, {:error, reason})

        {:stop, :normal,
         %{
           state
           | status: :stopped,
             start_timer: nil,
             early_failover_timer: nil,
             consumers: %{},
             pending_subscribers: []
         }}
    end
  end

  defp maybe_promote_source(%{active_hash: hash, source_index: idx} = state)
       when is_binary(hash) and idx > 0 do
    Store.promote_channel_source(state.channel_key, hash)
    promoted_sources = [hash | Enum.reject(state.sources, &(&1 == hash))]

    %{
      state
      | source_promoted: true,
        sources: promoted_sources,
        source_index: 0,
        cycle_count: 0
    }
  end

  defp maybe_promote_source(state) do
    %{state | source_promoted: true, cycle_count: 0}
  end

  defp dispatch_load_for_current_source(state) do
    current_hash = Enum.at(state.sources, state.source_index)
    cmd = "LOADASYNC 0 PID #{current_hash}\r\n"

    Logger.info(
      "[ChannelBroadcaster:#{state.channel_key}] Attempting source #{state.source_index + 1}/#{length(state.sources)}: #{current_hash}"
    )

    if state.socket do
      safe_tcp_send(state.socket, cmd)
    end

    canonical_hash = nil

    if state.start_timer, do: Process.cancel_timer(state.start_timer)
    if state.early_failover_timer, do: Process.cancel_timer(state.early_failover_timer)

    new_timer = Process.send_after(self(), :start_timeout, Config.start_timeout_ms())

    %{
      state
      | canonical_hash: canonical_hash,
        start_timer: new_timer,
        early_failover_timer: nil
    }
  end

  defp abort_pending_subscribers(pending, reason) do
    for {_pid, from} <- pending do
      GenServer.reply(from, reason)
    end
  end

  defp cancel_cooldown(state) do
    if state.cooldown_timer do
      Process.cancel_timer(state.cooldown_timer)
    end

    %{state | cooldown_timer: nil}
  end

  defp handle_consumer_disconnect(pid, state) do
    case Map.pop(state.consumers, pid) do
      {nil, _} ->
        state

      {ref, remaining_consumers} ->
        Process.demonitor(ref, [:flush])
        new_count = map_size(remaining_consumers)

        Logger.info(
          "[ChannelBroadcaster:#{state.channel_key}] Consumer disconnected. Remaining: #{new_count}"
        )

        if new_count == 0 and state.status == :streaming do
          delay = Config.grace_period_ms()

          Logger.info(
            "[ChannelBroadcaster:#{state.channel_key}] 0 viewers left. Entering #{delay}ms grace cooldown."
          )

          timer = Process.send_after(self(), :grace_period_expired, delay)
          %{state | consumers: remaining_consumers, status: :cooldown, cooldown_timer: timer}
        else
          %{state | consumers: remaining_consumers}
        end
    end
  end

  defp start_upstream_fetch(playback_url) do
    broadcaster = self()

    spawn_link(fn ->
      Logger.info("[ChannelBroadcaster.Upstream] Connecting to upstream: #{playback_url}")

      try do
        Req.get!(
          playback_url,
          into: fn {:data, chunk}, acc ->
            dispatch_chunk(broadcaster, chunk)
            {:cont, acc}
          end,
          receive_timeout: 30_000
        )

        send(broadcaster, {:upstream_completed, :eof})
      catch
        :exit, :shutdown ->
          :ok

        error, reason ->
          Logger.error(
            "[ChannelBroadcaster.Upstream] Upstream error: #{inspect(error)} #{inspect(reason)}"
          )

          send(broadcaster, {:upstream_completed, reason})
      end
    end)
  end

  defp resolve_channel_name(channel_key, target) do
    case Store.get_channel(channel_key) || Store.get_channel(target) do
      %{"name" => name} when is_binary(name) and name != "" ->
        name

      _ ->
        clean = Store.sanitize_hash(target)

        case Store.find_channel_by_source(clean) do
          %{"name" => name} when is_binary(name) and name != "" ->
            name

          _ ->
            if String.length(clean) == 40 do
              "Direct Stream (#{String.slice(clean, 0, 8)}...)"
            else
              channel_key
            end
        end
    end
  end

  defp safe_tcp_send(socket, data) when socket != nil do
    try do
      :gen_tcp.send(socket, data)
    catch
      _, _ -> :error
    end
  end

  defp safe_tcp_send(_socket, _data), do: :ok

  defp safe_tcp_close(socket) when socket != nil do
    try do
      :gen_tcp.close(socket)
    catch
      _, _ -> :error
    end
  end

  defp safe_tcp_close(_socket), do: :ok
end
