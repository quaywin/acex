defmodule AcexGateway.Web.Router do
  @moduledoc """
  HTTP Router powered by Plug and Bandit.
  Provides:
  - Streaming `/live` (with channel slug or content_id)
  - M3U Playlist generator `/playlist.m3u`
  - REST API for channels (`/api/channels`)
  - Real-time telemetry (`/stat`)
  - Ultra-modern Web Management Dashboard (`/`)
  """

  use Plug.Router
  require Logger

  alias AcexGateway.Config
  alias AcexGateway.Stream.Broadcaster
  alias AcexGateway.Engine.TelnetClient
  alias AcexGateway.Channels.Store
  alias AcexGateway.Web.DashboardView

  plug(:match)
  plug(Plug.Parsers, parsers: [:urlencoded, :json], json_decoder: Jason)
  plug(:dispatch)

  options _ do
    conn
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_header("access-control-allow-methods", "GET, POST, PUT, DELETE, OPTIONS, HEAD")
    |> put_resp_header("access-control-allow-headers", "content-type, authorization")
    |> send_resp(204, "")
  end

  get "/playlist.m3u" do
    base_url = request_base_url(conn)
    m3u_content = Store.export_m3u(base_url)

    conn
    |> put_resp_header("content-type", "application/x-mpegurl; charset=utf-8")
    |> put_resp_header("content-disposition", "inline; filename=\"acex_playlist.m3u\"")
    |> put_resp_header("access-control-allow-origin", "*")
    |> send_resp(200, m3u_content)
  end

  get "/api/channels" do
    channels = Store.list_channels()

    conn
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(channels, pretty: true))
  end

  get "/api/channels/export" do
    conn = fetch_query_params(conn)
    format = conn.query_params["format"] || "txt"

    case format do
      "m3u" ->
        base_url = request_base_url(conn)
        m3u = Store.export_m3u(base_url)

        conn
        |> put_resp_header("content-type", "application/x-mpegurl; charset=utf-8")
        |> put_resp_header("content-disposition", "attachment; filename=\"acex_channels.m3u\"")
        |> put_resp_header("access-control-allow-origin", "*")
        |> send_resp(200, m3u)

      "json" ->
        channels = Store.list_channels()
        json = Jason.encode!(channels, pretty: true)

        conn
        |> put_resp_header("content-type", "application/json; charset=utf-8")
        |> put_resp_header("content-disposition", "attachment; filename=\"acex_channels.json\"")
        |> put_resp_header("access-control-allow-origin", "*")
        |> send_resp(200, json)

      _ ->
        txt = Store.export_txt()

        conn
        |> put_resp_header("content-type", "text/plain; charset=utf-8")
        |> put_resp_header("content-disposition", "attachment; filename=\"acex_channels.txt\"")
        |> put_resp_header("access-control-allow-origin", "*")
        |> send_resp(200, txt)
    end
  end

  post "/api/channels" do
    case Store.save_channel(conn.body_params) do
      {:ok, channel} ->
        conn
        |> put_resp_header("access-control-allow-origin", "*")
        |> put_resp_content_type("application/json")
        |> send_resp(201, Jason.encode!(%{status: "created", channel: channel}))

      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(%{error: "Invalid channel payload"}))
    end
  end

  post "/api/channels/preview" do
    params = conn.body_params
    content = params["content"] || ""
    default_group = params["default_group"] || "General"
    default_country = params["default_country"] || ""

    parsed = Store.parse_import_text(content, default_group, default_country)

    conn
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(%{count: length(parsed), channels: parsed}))
  end

  post "/api/channels/import" do
    params = conn.body_params
    content = params["content"] || ""
    default_group = params["default_group"] || "General"
    default_country = params["default_country"] || ""
    mode = params["mode"] || "merge"

    input =
      cond do
        is_list(params["channels"]) -> params["channels"]
        is_binary(content) and content != "" -> content
        true -> ""
      end

    case Store.import_channels(input, %{
           default_group: default_group,
           default_country: default_country,
           mode: mode
         }) do
      {:ok, imported} ->
        conn
        |> put_resp_header("access-control-allow-origin", "*")
        |> put_resp_content_type("application/json")
        |> send_resp(
          200,
          Jason.encode!(%{status: "imported", count: length(imported), channels: imported})
        )

      {:error, reason} ->
        conn
        |> put_resp_header("access-control-allow-origin", "*")
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(%{error: "Import failed", reason: to_string(reason)}))
    end
  end

  put "/api/channels/:id" do
    params = Map.put(conn.body_params, "id", id)

    case Store.save_channel(params) do
      {:ok, channel} ->
        conn
        |> put_resp_header("access-control-allow-origin", "*")
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{status: "updated", channel: channel}))

      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(%{error: "Invalid channel payload"}))
    end
  end

  delete "/api/channels/:id" do
    Store.delete_channel(id)

    conn
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(%{status: "deleted", id: id}))
  end

  head "/live" do
    conn
    |> put_resp_header("content-type", "video/mp2t")
    |> put_resp_header("cache-control", "no-cache, no-store, must-revalidate")
    |> put_resp_header("connection", "keep-alive")
    |> put_resp_header("access-control-allow-origin", "*")
    |> send_resp(200, "")
  end

  get "/live" do
    conn = fetch_query_params(conn)
    query = conn.query_params

    {target, source_type} =
      cond do
        Map.has_key?(query, "channel") and query["channel"] != "" ->
          {query["channel"], :channel}

        Map.has_key?(query, "id") and query["id"] != "" ->
          {Store.sanitize_hash(query["id"]), :content_id}

        true ->
          {Config.default_channel_id(), :content_id}
      end

    Logger.info("[Router] Client connected to /live for #{source_type}: #{target}")

    case Broadcaster.subscribe(target, source_type) do
      {:ok, broadcaster_pid} ->
        conn =
          conn
          |> put_resp_header("content-type", "video/mp2t")
          |> put_resp_header("cache-control", "no-cache, no-store, must-revalidate")
          |> put_resp_header("connection", "keep-alive")
          |> put_resp_header("access-control-allow-origin", "*")
          |> send_chunked(200)

        stream_loop(conn, broadcaster_pid)

      {:error, reason} ->
        Logger.error("[Router] Stream subscription failed: #{inspect(reason)}")

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          502,
          Jason.encode!(%{error: "Stream initiation failed", reason: to_string(reason)})
        )
    end
  end

  get "/stat" do
    engine_stats = TelnetClient.get_stats()
    session_info = Broadcaster.get_session_info()

    uptime =
      case :erlang.statistics(:wall_clock) do
        {ms, _} -> div(ms, 1000)
      end

    peers =
      if session_info.peers > 0, do: session_info.peers, else: engine_stats.peers

    speed_kbps =
      if session_info.speed_kbps > 0, do: session_info.speed_kbps, else: engine_stats.speed_kbps

    response = %{
      version: "0.1.0",
      engine: "AcexGateway (Elixir/OTP)",
      status: session_info.status,
      active_target: session_info.active_target,
      active_channel: session_info.active_channel,
      active_channel_name: session_info[:active_channel_name] || session_info.active_channel,
      source_type: session_info.source_type,
      client_count: session_info.client_count,
      bytes_transferred: session_info.bytes_transferred,
      buffered_bytes: session_info.buffered_bytes,
      source_index: session_info.source_index,
      total_sources: session_info.total_sources,
      peers: peers,
      speed_kbps: speed_kbps,
      engine_connected: engine_stats.connected,
      engine_authenticated: engine_stats.authenticated,
      uptime_seconds: uptime,
      active_channels_count: session_info.active_channels_count,
      channels: session_info.channels
    }

    conn
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(response, pretty: true))
  end

  match "/restart" do
    conn = fetch_query_params(conn)
    channel = conn.query_params["channel"]
    Logger.info("[Router] Manual reset requested (channel: #{inspect(channel)}).")
    Broadcaster.force_reset(channel)

    conn
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(%{status: "ok", message: "Stream reset successfully"}))
  end

  get "/favicon.ico" do
    conn
    |> put_resp_header("content-type", "image/svg+xml")
    |> put_resp_header("cache-control", "public, max-age=604800, immutable")
    |> send_resp(200, DashboardView.favicon_svg())
  end

  get "/health" do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, "OK")
  end

  get "/" do
    base_url = request_base_url(conn)
    channels = Store.list_channels()
    html = DashboardView.render(base_url, channels)

    conn
    |> put_resp_content_type("text/html; charset=utf-8")
    |> send_resp(200, html)
  end

  match _ do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(404, Jason.encode!(%{error: "Not found"}))
  end

  # Helpers

  defp request_base_url(conn) do
    host =
      case Plug.Conn.get_req_header(conn, "host") do
        [h | _] -> h
        [] -> "#{conn.host}:#{conn.port}"
      end

    "http://#{host}"
  end

  defp stream_loop(conn, broadcaster_pid) do
    receive do
      {:stream_chunk, chunk} ->
        case chunk(conn, chunk) do
          {:ok, conn} ->
            stream_loop(conn, broadcaster_pid)

          {:error, :closed} ->
            Broadcaster.unsubscribe(broadcaster_pid, self())
            conn

          {:error, reason} ->
            Logger.warning("[Router] Downstream write error: #{inspect(reason)}")
            Broadcaster.unsubscribe(broadcaster_pid, self())
            conn
        end

      {:stream_closed, reason} ->
        Logger.info("[Router] Upstream stream closed: #{inspect(reason)}")
        conn
    after
      45_000 ->
        stream_loop(conn, broadcaster_pid)
    end
  end
end
