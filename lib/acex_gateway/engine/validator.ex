defmodule AcexGateway.Engine.Validator do
  @moduledoc """
  Validates AceStream Content IDs and torrent health using lightweight Telnet LOADASYNC queries.
  Does not buffer video or start HTTP streams. Memoizes validation results in ETS.
  """

  require Logger
  alias AcexGateway.Channels.Store
  alias AcexGateway.Config
  alias AcexGateway.Engine.Protocol

  @cache_table :acex_validator_cache
  @cache_ttl_seconds 60
  @default_timeout_ms 6000

  @doc """
  Ensures the ETS cache table exists.
  """
  def ensure_cache do
    case :ets.whereis(@cache_table) do
      :undefined ->
        try do
          :ets.new(@cache_table, [:set, :public, :named_table, read_concurrency: true])
        catch
          :error, :badarg -> @cache_table
        end

      _tid ->
        @cache_table
    end
  end

  @doc """
  Validates a single Content ID or source hash.
  Options:
    - `:force` (boolean) - Bypasses ETS cache if true. Default: false.
    - `:timeout` (pos_integer) - Socket timeout in milliseconds. Default: 6000.
    - `:host` - Engine Telnet host. Default: Config.telnet_host().
    - `:port` - Engine Telnet port. Default: Config.telnet_port().
  """
  def validate_source(source, opts \\ []) do
    ensure_cache()
    force = Keyword.get(opts, :force, false)
    clean_hash = Store.sanitize_hash(source)

    if String.length(clean_hash) != 40 do
      {:ok,
       %{
         source: source,
         clean_source: clean_hash,
         valid: false,
         infohash: nil,
         response_time_ms: 0,
         error: "invalid_hash_format"
       }}
    else
      now = System.monotonic_time(:second)

      if not force and match?([_], :ets.lookup(@cache_table, clean_hash)) do
        [{^clean_hash, cached_result, expires_at}] = :ets.lookup(@cache_table, clean_hash)

        if expires_at > now do
          {:ok, cached_result}
        else
          do_validate(clean_hash, source, opts)
        end
      else
        do_validate(clean_hash, source, opts)
      end
    end
  end

  @doc """
  Validates a list of sources concurrently.
  """
  def validate_sources(sources, opts \\ []) when is_list(sources) do
    sources
    |> Enum.uniq()
    |> Task.async_stream(
      fn src ->
        case validate_source(src, opts) do
          {:ok, res} ->
            res

          {:error, reason} ->
            %{
              source: src,
              clean_source: Store.sanitize_hash(src),
              valid: false,
              infohash: nil,
              response_time_ms: 0,
              error: inspect(reason)
            }
        end
      end,
      max_concurrency: 5,
      timeout: Keyword.get(opts, :batch_timeout, 15_000)
    )
    |> Enum.map(fn
      {:ok, res} ->
        res

      {:exit, reason} ->
        %{
          source: "unknown",
          clean_source: "",
          valid: false,
          infohash: nil,
          response_time_ms: 0,
          error: "timeout_or_exit: #{inspect(reason)}"
        }
    end)
  end

  @doc """
  Validates all sources of a channel stored in Store.
  """
  def validate_channel(channel_id, opts \\ []) when is_binary(channel_id) do
    case Store.get_channel(channel_id) do
      nil ->
        {:error, :channel_not_found}

      %{"sources" => sources} when is_list(sources) and sources != [] ->
        results = validate_sources(sources, opts)
        alive_count = Enum.count(results, & &1.valid)
        dead_count = length(results) - alive_count

        {:ok,
         %{
           channel_id: channel_id,
           total_sources: length(sources),
           alive_count: alive_count,
           dead_count: dead_count,
           results: results
         }}

      _ ->
        {:ok,
         %{
           channel_id: channel_id,
           total_sources: 0,
           alive_count: 0,
           dead_count: 0,
           results: []
         }}
    end
  end

  # Internal validation execution

  defp do_validate(clean_hash, original_source, opts) do
    start_time = :erlang.monotonic_time(:millisecond)
    timeout = Keyword.get(opts, :timeout, @default_timeout_ms)
    host = Keyword.get(opts, :host, Config.telnet_host())
    port = Keyword.get(opts, :port, Config.telnet_port())

    case query_engine(host, port, clean_hash, timeout) do
      {:ok, infohash} ->
        elapsed = :erlang.monotonic_time(:millisecond) - start_time

        result = %{
          source: original_source,
          clean_source: clean_hash,
          valid: true,
          infohash: infohash,
          response_time_ms: elapsed,
          error: nil
        }

        cache_result(clean_hash, result)
        {:ok, result}

      {:dead, reason} ->
        elapsed = :erlang.monotonic_time(:millisecond) - start_time

        result = %{
          source: original_source,
          clean_source: clean_hash,
          valid: false,
          infohash: nil,
          response_time_ms: elapsed,
          error: reason
        }

        cache_result(clean_hash, result)
        {:ok, result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp cache_result(clean_hash, result) do
    expires_at = System.monotonic_time(:second) + @cache_ttl_seconds
    :ets.insert(@cache_table, {clean_hash, result, expires_at})
  end

  defp query_engine(host, port, clean_hash, timeout) do
    host_charlist = to_charlist(host)

    case :gen_tcp.connect(
           host_charlist,
           port,
           [:binary, packet: :line, active: false],
           min(timeout, 3000)
         ) do
      {:ok, socket} ->
        try do
          # 1. Send handshake
          :ok = :gen_tcp.send(socket, "HELLOBG version=4\r\n")

          # 2. Negotiate protocol and query LOADASYNC
          negotiate_and_load(socket, clean_hash, timeout)
        after
          try do
            :gen_tcp.send(socket, "STOPDL\r\n")
            :gen_tcp.close(socket)
          catch
            _, _ -> :ok
          end
        end

      {:error, reason} ->
        {:error, {:connect_failed, reason}}
    end
  end

  defp negotiate_and_load(socket, clean_hash, timeout) do
    deadline = :erlang.monotonic_time(:millisecond) + timeout
    do_loop_recv(socket, clean_hash, deadline, :awaiting_hellots)
  end

  defp do_loop_recv(socket, clean_hash, deadline, state) do
    remaining = deadline - :erlang.monotonic_time(:millisecond)

    if remaining <= 0 do
      {:dead, "engine_timeout"}
    else
      recv_timeout = min(remaining, 3000)

      case :gen_tcp.recv(socket, 0, recv_timeout) do
        {:ok, raw_line} ->
          line = String.trim(raw_line)
          handle_telnet_step(socket, line, clean_hash, deadline, state)

        {:error, :timeout} ->
          {:dead, "engine_timeout"}

        {:error, reason} ->
          {:error, {:socket_error, reason}}
      end
    end
  end

  defp handle_telnet_step(socket, "HELLOTS " <> _ = line, clean_hash, deadline, :awaiting_hellots) do
    %{key: req_key} = Protocol.parse_hellots(line)
    ready_key = Protocol.compute_ready_key(req_key, Config.product_key())
    :ok = :gen_tcp.send(socket, "READY key=#{ready_key}\r\n")
    do_loop_recv(socket, clean_hash, deadline, :awaiting_auth)
  end

  defp handle_telnet_step(socket, "AUTH " <> _, clean_hash, deadline, :awaiting_auth) do
    # Authenticated: dispatch LOADASYNC query
    :ok = :gen_tcp.send(socket, "LOADASYNC 1 PID #{clean_hash}\r\n")
    do_loop_recv(socket, clean_hash, deadline, :awaiting_loadresp)
  end

  defp handle_telnet_step(_socket, "NOTREADY", _clean_hash, _deadline, _state) do
    {:error, :not_ready}
  end

  defp handle_telnet_step(
         _socket,
         "LOADRESP " <> _ = line,
         _clean_hash,
         _deadline,
         :awaiting_loadresp
       ) do
    case Protocol.parse_loadresp(line) do
      {:ok, infohash} ->
        {:ok, infohash}

      {:error, reason} ->
        {:dead, reason}

      :none ->
        {:dead, "torrent_not_resolved"}
    end
  end

  defp handle_telnet_step(socket, _other_line, clean_hash, deadline, state) do
    do_loop_recv(socket, clean_hash, deadline, state)
  end
end
