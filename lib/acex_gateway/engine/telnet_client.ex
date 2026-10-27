defmodule AcexGateway.Engine.TelnetClient do
  @moduledoc """
  GenServer that maintains the persistent singleton Telnet API connection to the AceStream engine.
  Handles authentication handshake and parses engine telemetry (peers, download speed).
  """

  use GenServer
  require Logger

  alias AcexGateway.Config
  alias AcexGateway.Engine.Protocol

  @reconnect_interval_ms 2000

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns current engine status and telemetry.
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    state = %{
      socket: nil,
      authenticated: false,
      http_port: Config.http_port(),
      peers: 0,
      speed_kbps: 0,
      retry_count: 0
    }

    send(self(), :connect)
    {:ok, state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      connected: state.socket != nil,
      authenticated: state.authenticated,
      http_port: state.http_port,
      peers: state.peers,
      speed_kbps: state.speed_kbps
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_info(:connect, state) do
    host = to_charlist(Config.telnet_host())
    port = Config.telnet_port()

    if state.retry_count == 0 do
      Logger.info(
        "[TelnetClient] Connecting to AceStream API at #{Config.telnet_host()}:#{port}..."
      )
    else
      Logger.debug(
        "[TelnetClient] Retrying connection to #{Config.telnet_host()}:#{port} (attempt #{state.retry_count})..."
      )
    end

    case :gen_tcp.connect(host, port, [:binary, packet: :line, active: true], 5000) do
      {:ok, socket} ->
        Logger.info(
          "[TelnetClient] Connected to AceStream Engine socket. Initiating handshake..."
        )

        :gen_tcp.send(socket, "HELLOBG version=4\r\n")
        {:noreply, %{state | socket: socket, authenticated: false, retry_count: 0}}

      {:error, reason} ->
        if state.retry_count == 0 do
          Logger.warning(
            "[TelnetClient] AceStream Engine is not currently reachable at #{Config.telnet_host()}:#{port} (#{inspect(reason)}). Waiting for engine in background..."
          )
        end

        delay = min(@reconnect_interval_ms + state.retry_count * 1000, 5000)
        Process.send_after(self(), :connect, delay)

        {:noreply,
         %{state | socket: nil, authenticated: false, retry_count: state.retry_count + 1}}
    end
  end

  def handle_info({:tcp, socket, line}, %{socket: socket} = state) do
    line_clean = String.trim(line)
    new_state = process_line(line_clean, state)
    {:noreply, new_state}
  end

  def handle_info({:tcp_closed, socket}, %{socket: socket} = state) do
    Logger.warning("[TelnetClient] Telnet socket closed by remote. Scheduling reconnect...")
    Process.send_after(self(), :connect, @reconnect_interval_ms)
    {:noreply, %{state | socket: nil, authenticated: false, retry_count: 0}}
  end

  def handle_info({:tcp_error, socket, reason}, %{socket: socket} = state) do
    Logger.error("[TelnetClient] Telnet socket error: #{inspect(reason)}")
    :gen_tcp.close(socket)
    Process.send_after(self(), :connect, @reconnect_interval_ms)
    {:noreply, %{state | socket: nil, authenticated: false, retry_count: 0}}
  end

  def handle_info(_other, state) do
    {:noreply, state}
  end

  # Line Processing

  defp process_line("HELLOTS " <> _ = line, state) do
    %{key: req_key, http_port: http_port} = Protocol.parse_hellots(line)
    Logger.info("[TelnetClient] Handshake HELLOTS received. http_port=#{http_port}")

    ready_key = Protocol.compute_ready_key(req_key, Config.product_key())
    :gen_tcp.send(state.socket, "READY key=#{ready_key}\r\n")

    %{state | http_port: http_port}
  end

  defp process_line("AUTH " <> auth_info, state) do
    Logger.info("[TelnetClient] AceStream Authenticated successfully: #{auth_info}")
    :gen_tcp.send(state.socket, "SETOPTIONS use_stop_notifications=1\r\n")
    %{state | authenticated: true}
  end

  defp process_line("NOTREADY", state) do
    Logger.error("[TelnetClient] Engine returned NOTREADY during auth handshake.")
    %{state | authenticated: false}
  end

  defp process_line("STATUS " <> _ = line, state) do
    stats = Protocol.parse_status(line)
    new_peers = Map.get(stats, :peers, state.peers)
    new_speed = Map.get(stats, :speed_kbps, state.speed_kbps)

    %{state | peers: new_peers, speed_kbps: new_speed}
  end

  defp process_line(_unhandled, state) do
    state
  end
end
