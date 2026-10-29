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
  alias AcexGateway.Engine.Validator
  alias AcexGateway.Channels.Store
  alias AcexGateway.Events.Store, as: EventsStore
  alias AcexGateway.Sync.PlaylistSync
  alias AcexGateway.Settings.Store, as: SettingsStore
  alias AcexGateway.System.Updater
  alias AcexGateway.Stream.CastRemuxer
  alias AcexGateway.Stream.SegmentObfuscator
  alias AcexGateway.Web.DashboardView
  alias AcexGateway.Web.XtreamCodes

  plug(:match)
  plug(Plug.Parsers, parsers: [:urlencoded, :json], json_decoder: Jason)
  plug(:dispatch)

  options _ do
    conn
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_header(
      "access-control-allow-methods",
      "GET, POST, PUT, PATCH, DELETE, OPTIONS, HEAD"
    )
    |> put_resp_header("access-control-allow-headers", "content-type, authorization")
    |> put_resp_header("access-control-max-age", "86400")
    |> send_resp(204, "")
  end

  # --- Short M3U8 Playlist routes (path-based auth) ---
  get "/hls/:username/:password/channels.m3u8" do
    if Config.authenticate?(username, password) do
      serve_custom_playlist(conn, :hls, %{"username" => username, "password" => password}, :channels)
    else
      send_unauthorized(conn)
    end
  end

  get "/hls/:username/:password/events.m3u8" do
    if Config.authenticate?(username, password) do
      serve_custom_playlist(conn, :hls, %{"username" => username, "password" => password}, :events)
    else
      send_unauthorized(conn)
    end
  end

  get "/hls/:username/:password.m3u8" do
    if Config.authenticate?(username, password) do
      serve_custom_playlist(conn, :hls, %{"username" => username, "password" => password}, :all)
    else
      send_unauthorized(conn)
    end
  end

  get "/ts/:username/:password/channels.m3u8" do
    if Config.authenticate?(username, password) do
      serve_custom_playlist(conn, :ts, %{"username" => username, "password" => password}, :channels)
    else
      send_unauthorized(conn)
    end
  end

  get "/ts/:username/:password/events.m3u8" do
    if Config.authenticate?(username, password) do
      serve_custom_playlist(conn, :ts, %{"username" => username, "password" => password}, :events)
    else
      send_unauthorized(conn)
    end
  end

  get "/ts/:username/:password.m3u8" do
    if Config.authenticate?(username, password) do
      serve_custom_playlist(conn, :ts, %{"username" => username, "password" => password}, :all)
    else
      send_unauthorized(conn)
    end
  end

  # Short M3U8 Playlist routes (no credentials in path)
  get "/hls/channels.m3u8" do
    serve_typed_playlist(conn, :channels, :hls)
  end

  get "/hls/events.m3u8" do
    serve_typed_playlist(conn, :events, :hls)
  end

  get "/hls.m3u8" do
    case authenticate_request(conn) do
      :ok ->
        auth_opts = get_playlist_auth_opts(conn)
        serve_custom_playlist(conn, :hls, auth_opts, :all)

      :unauthorized ->
        send_unauthorized(conn)
    end
  end

  get "/ts/channels.m3u8" do
    serve_typed_playlist(conn, :channels, :ts)
  end

  get "/ts/events.m3u8" do
    serve_typed_playlist(conn, :events, :ts)
  end

  get "/ts.m3u8" do
    case authenticate_request(conn) do
      :ok ->
        auth_opts = get_playlist_auth_opts(conn)
        serve_custom_playlist(conn, :ts, auth_opts, :all)

      :unauthorized ->
        send_unauthorized(conn)
    end
  end

  # Standard /get.php Xtream Codes M3U endpoint
  get "/get.php" do
    conn = fetch_query_params(conn)
    username = conn.query_params["username"] || conn.query_params["user"] || ""
    password = conn.query_params["password"] || conn.query_params["pass"] || ""
    output = conn.query_params["output"] || "ts"
    type_param = conn.query_params["type"] || conn.query_params["filter"]

    type =
      case type_param do
        "events" -> :events
        "channels" -> :channels
        _ -> :all
      end

    format = if output in ["hls", "m3u8"], do: :hls, else: :ts

    if Config.authenticate?(username, password) do
      serve_custom_playlist(conn, format, %{"username" => username, "password" => password}, type)
    else
      send_unauthorized(conn)
    end
  end

  # Typed Playlists (Channels / Events)
  get "/channels.m3u" do
    serve_typed_playlist(conn, :channels)
  end

  get "/channels.m3u8" do
    serve_typed_playlist(conn, :channels)
  end

  get "/events.m3u" do
    serve_typed_playlist(conn, :events)
  end

  get "/events.m3u8" do
    serve_typed_playlist(conn, :events)
  end

  get "/playlist.m3u" do
    serve_playlist(conn)
  end

  get "/playlist.m3u8" do
    serve_playlist(conn)
  end

  get "/player_api.php" do
    conn = fetch_query_params(conn)
    base_url = request_base_url(conn)

    case XtreamCodes.handle_request(conn.query_params, base_url) do
      {:ok, data} ->
        conn
        |> put_resp_header("access-control-allow-origin", "*")
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(data))

      {:unauthorized, data} ->
        conn
        |> put_resp_header("access-control-allow-origin", "*")
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(data))
    end
  end

  defp serve_typed_playlist(conn, type, fixed_format \\ nil) do
    case authenticate_request(conn) do
      :ok ->
        conn = fetch_query_params(conn)
        output = conn.query_params["output"] || conn.query_params["format"]

        format =
          cond do
            fixed_format != nil -> fixed_format
            output in ["hls", "m3u8"] -> :hls
            output in ["ts"] -> :ts
            true -> nil
          end

        auth_opts = get_playlist_auth_opts(conn)
        serve_custom_playlist(conn, format, auth_opts, type)

      :unauthorized ->
        send_unauthorized(conn)
    end
  end

  defp serve_playlist(conn) do
    case authenticate_request(conn) do
      :ok ->
        conn = fetch_query_params(conn)
        output = conn.query_params["output"] || conn.query_params["format"]

        format =
          cond do
            output in ["hls", "m3u8"] -> :hls
            output in ["ts"] -> :ts
            true -> nil
          end

        type_param = conn.query_params["type"] || conn.query_params["filter"]

        type =
          case type_param do
            "events" -> :events
            "channels" -> :channels
            _ -> :all
          end

        auth_opts = get_playlist_auth_opts(conn)
        serve_custom_playlist(conn, format, auth_opts, type)

      :unauthorized ->
        send_unauthorized(conn)
    end
  end

  defp serve_custom_playlist(conn, format, auth_opts, type) do
    base_url = request_base_url(conn)
    opts = if format, do: Map.put(auth_opts, "format", format), else: auth_opts

    m3u_content =
      case type do
        :events ->
          EventsStore.export_m3u(base_url, opts)

        :channels ->
          Store.export_m3u(base_url, opts)

        :all ->
          combined_channels = Store.list_channels() ++ EventsStore.list_events()
          Store.generate_m3u(combined_channels, base_url, opts)
      end

    filename =
      case {type, format} do
        {:events, :hls} ->
          "acex_events_hls.m3u8"

        {:events, :ts} ->
          "acex_events_ts.m3u8"

        {:events, _} ->
          if String.ends_with?(conn.request_path, ".m3u"),
            do: "acex_events.m3u",
            else: "acex_events.m3u8"

        {:channels, :hls} ->
          "acex_channels_hls.m3u8"

        {:channels, :ts} ->
          "acex_channels_ts.m3u8"

        {:channels, _} ->
          if String.ends_with?(conn.request_path, ".m3u"),
            do: "acex_channels.m3u",
            else: "acex_channels.m3u8"

        {:all, :hls} ->
          "acex_hls_playlist.m3u8"

        {:all, :ts} ->
          "acex_ts_playlist.m3u8"

        {:all, _} ->
          if String.ends_with?(conn.request_path, ".m3u"),
            do: "acex_playlist.m3u",
            else: "acex_playlist.m3u8"
      end

    conn
    |> put_resp_header("content-type", "application/x-mpegurl; charset=utf-8")
    |> put_resp_header("content-disposition", "inline; filename=\"#{filename}\"")
    |> put_resp_header("access-control-allow-origin", "*")
    |> send_resp(200, m3u_content)
  end

  defp get_playlist_auth_opts(conn) do
    conn = fetch_query_params(conn)
    username = conn.query_params["username"] || conn.query_params["user"]
    password = conn.query_params["password"] || conn.query_params["pass"]

    cond do
      is_binary(username) and is_binary(password) and username != "" and password != "" ->
        %{"username" => username, "password" => password}

      Config.auth_enabled?() ->
        %{"username" => Config.auth_username(), "password" => Config.auth_password()}

      true ->
        %{}
    end
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
      f when f in ["m3u", "m3u8"] ->
        base_url = request_base_url(conn)
        auth_opts = get_playlist_auth_opts(conn)
        m3u = Store.export_m3u(base_url, auth_opts)
        filename = if f == "m3u8", do: "acex_channels.m3u8", else: "acex_channels.m3u"

        conn
        |> put_resp_header("content-type", "application/x-mpegurl; charset=utf-8")
        |> put_resp_header("content-disposition", "attachment; filename=\"#{filename}\"")
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

  patch "/api/channels/:id/group" do
    params = conn.body_params || %{}
    target_group = params["group"] || params[:group] || "General"

    case Store.get_channel(id) do
      nil ->
        conn
        |> put_resp_header("access-control-allow-origin", "*")
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "Channel not found"}))

      _channel ->
        {:ok, result} = Store.set_channel_group(id, target_group)
        updated_channel = Store.get_channel(id)

        conn
        |> put_resp_header("access-control-allow-origin", "*")
        |> put_resp_content_type("application/json")
        |> send_resp(
          200,
          Jason.encode!(Map.merge(result, %{status: "ok", channel: updated_channel}))
        )
    end
  end

  post "/api/channels/bulk-move" do
    params = conn.body_params || %{}
    channel_ids = params["channel_ids"] || params[:channel_ids] || []
    target_group = params["group"] || params[:group] || "General"

    if is_list(channel_ids) and channel_ids != [] do
      {:ok, result} = Store.move_channels_group(channel_ids, target_group)

      conn
      |> put_resp_header("access-control-allow-origin", "*")
      |> put_resp_content_type("application/json")
      |> send_resp(200, Jason.encode!(Map.put(result, :status, "ok")))
    else
      conn
      |> put_resp_header("access-control-allow-origin", "*")
      |> put_resp_content_type("application/json")
      |> send_resp(400, Jason.encode!(%{error: "channel_ids must be a non-empty list"}))
    end
  end

  post "/api/channels/bulk-delete" do
    params = conn.body_params || %{}
    channel_ids = params["channel_ids"] || params[:channel_ids] || []

    if is_list(channel_ids) and channel_ids != [] do
      Enum.each(channel_ids, &Store.delete_channel/1)

      conn
      |> put_resp_header("access-control-allow-origin", "*")
      |> put_resp_content_type("application/json")
      |> send_resp(200, Jason.encode!(%{status: "ok", deleted_count: length(channel_ids)}))
    else
      conn
      |> put_resp_header("access-control-allow-origin", "*")
      |> put_resp_content_type("application/json")
      |> send_resp(400, Jason.encode!(%{error: "channel_ids must be a non-empty list"}))
    end
  end

  get "/api/groups" do
    groups = Store.list_groups()

    conn
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(groups))
  end

  post "/api/groups" do
    params = conn.body_params || %{}
    name = params["name"] || params[:name] || ""

    case Store.create_group(name) do
      {:ok, group} ->
        conn
        |> put_resp_header("access-control-allow-origin", "*")
        |> put_resp_content_type("application/json")
        |> send_resp(201, Jason.encode!(%{status: "created", group: group}))

      {:error, :already_exists} ->
        conn
        |> put_resp_header("access-control-allow-origin", "*")
        |> put_resp_content_type("application/json")
        |> send_resp(409, Jason.encode!(%{error: "Group already exists"}))

      {:error, reason} ->
        conn
        |> put_resp_header("access-control-allow-origin", "*")
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(%{error: "Invalid group", reason: inspect(reason)}))
    end
  end

  put "/api/groups/:id" do
    params = conn.body_params || %{}
    name = params["name"] || params[:name] || ""

    case Store.rename_group(id, name) do
      {:ok, group} ->
        conn
        |> put_resp_header("access-control-allow-origin", "*")
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{status: "updated", group: group}))

      {:error, :not_found} ->
        conn
        |> put_resp_header("access-control-allow-origin", "*")
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "Group not found"}))

      {:error, :already_exists} ->
        conn
        |> put_resp_header("access-control-allow-origin", "*")
        |> put_resp_content_type("application/json")
        |> send_resp(409, Jason.encode!(%{error: "Group name already taken"}))

      {:error, reason} ->
        conn
        |> put_resp_header("access-control-allow-origin", "*")
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(%{error: "Invalid update", reason: inspect(reason)}))
    end
  end

  delete "/api/groups/:id" do
    conn = fetch_query_params(conn)
    fallback = conn.query_params["fallback_group"] || "General"

    case Store.delete_group(id, fallback) do
      {:ok, result} ->
        conn
        |> put_resp_header("access-control-allow-origin", "*")
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(Map.put(result, :status, "deleted")))

      {:error, :cannot_delete_last_group} ->
        conn
        |> put_resp_header("access-control-allow-origin", "*")
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(%{error: "Cannot delete the only remaining group"}))

      {:error, :not_found} ->
        conn
        |> put_resp_header("access-control-allow-origin", "*")
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "Group not found"}))
    end
  end

  post "/api/channels/validate-source" do
    params = conn.body_params || %{}
    source = params["source"] || params[:source] || ""
    force = params["force"] == true or params[:force] == true

    case Validator.validate_source(source, force: force) do
      {:ok, result} ->
        conn
        |> put_resp_header("access-control-allow-origin", "*")
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{status: "ok", result: result}))

      {:error, reason} ->
        conn
        |> put_resp_header("access-control-allow-origin", "*")
        |> put_resp_content_type("application/json")
        |> send_resp(503, Jason.encode!(%{status: "error", error: inspect(reason)}))
    end
  end

  post "/api/channels/:id/validate" do
    params = conn.body_params || %{}
    force = params["force"] == true or params[:force] == true

    case Validator.validate_channel(id, force: force) do
      {:ok, report} ->
        conn
        |> put_resp_header("access-control-allow-origin", "*")
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{status: "ok", report: report}))

      {:error, :channel_not_found} ->
        conn
        |> put_resp_header("access-control-allow-origin", "*")
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "Channel not found"}))
    end
  end

  post "/api/channels/:id/prune-dead" do
    params = conn.body_params || %{}
    dead_sources = params["dead_sources"] || params[:dead_sources]

    channel = Store.get_channel(id)

    case channel do
      nil ->
        conn
        |> put_resp_header("access-control-allow-origin", "*")
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "Channel not found"}))

      %{"sources" => sources} when length(sources) <= 1 ->
        conn
        |> put_resp_header("access-control-allow-origin", "*")
        |> put_resp_content_type("application/json")
        |> send_resp(
          400,
          Jason.encode!(%{
            error: "Cannot prune single-source channel",
            reason: "channel must retain at least 1 source"
          })
        )

      _ ->
        to_prune =
          if is_list(dead_sources) and dead_sources != [] do
            dead_sources
          else
            case Validator.validate_channel(id, force: true) do
              {:ok, %{results: results}} ->
                results
                |> Enum.filter(&(&1.valid == false))
                |> Enum.map(& &1.source)

              _ ->
                []
            end
          end

        pruned_list =
          Enum.reduce(to_prune, [], fn src, acc ->
            case Store.remove_channel_source(id, src) do
              {:ok, _} -> [src | acc]
              _ -> acc
            end
          end)

        updated_channel = Store.get_channel(id)

        conn
        |> put_resp_header("access-control-allow-origin", "*")
        |> put_resp_content_type("application/json")
        |> send_resp(
          200,
          Jason.encode!(%{
            status: "ok",
            channel_id: id,
            pruned_count: length(pruned_list),
            pruned_sources: Enum.reverse(pruned_list),
            channel: updated_channel
          })
        )
    end
  end

  post "/api/channels/prune-all-dead" do
    channels = Store.list_channels()
    multi_source_channels = Enum.filter(channels, fn c -> length(c["sources"] || []) > 1 end)

    results_acc =
      Enum.reduce(multi_source_channels, %{pruned_sources_count: 0, affected_channels: 0}, fn ch,
                                                                                              acc ->
        ch_id = ch["id"]

        case Validator.validate_channel(ch_id, force: true) do
          {:ok, %{results: results}} ->
            dead_sources =
              results
              |> Enum.filter(&(&1.valid == false))
              |> Enum.map(& &1.source)

            # Re-fetch channel to get fresh sources count before pruning each
            pruned =
              Enum.reduce(dead_sources, 0, fn src, p_acc ->
                case Store.remove_channel_source(ch_id, src) do
                  {:ok, _} -> p_acc + 1
                  _ -> p_acc
                end
              end)

            if pruned > 0 do
              %{
                pruned_sources_count: acc.pruned_sources_count + pruned,
                affected_channels: acc.affected_channels + 1
              }
            else
              acc
            end

          _ ->
            acc
        end
      end)

    conn
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_content_type("application/json")
    |> send_resp(
      200,
      Jason.encode!(%{
        status: "ok",
        total_checked_channels: length(multi_source_channels),
        affected_channels: results_acc.affected_channels,
        pruned_sources_count: results_acc.pruned_sources_count,
        channels: Store.list_channels()
      })
    )
  end

  get "/api/settings" do
    settings = SettingsStore.get_all_settings()

    conn
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(settings, pretty: true))
  end

  post "/api/settings" do
    handle_update_settings(conn)
  end

  put "/api/settings" do
    handle_update_settings(conn)
  end

  get "/api/system/version" do
    conn = fetch_query_params(conn)
    force = conn.query_params["force"] in ["true", "1", true]
    version_info = Updater.check_update(force: force)

    conn
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(version_info))
  end

  post "/api/system/update" do
    {:ok, resp} = Updater.trigger_update()

    conn
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(resp))
  end

  get "/api/events" do
    events = EventsStore.list_events()

    conn
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(events))
  end

  post "/api/sync/events" do
    case PlaylistSync.sync_events(force: true) do
      {:ok, count} ->
        conn
        |> put_resp_header("access-control-allow-origin", "*")
        |> put_resp_content_type("application/json")
        |> send_resp(
          200,
          Jason.encode!(%{
            status: "ok",
            count: count,
            message: "Successfully synced #{count} live sports events"
          })
        )

      {:error, reason} ->
        conn
        |> put_resp_header("access-control-allow-origin", "*")
        |> put_resp_content_type("application/json")
        |> send_resp(500, Jason.encode!(%{status: "error", error: to_string(reason)}))
    end
  end

  post "/api/sync/channels" do
    case PlaylistSync.sync_channels(force: true) do
      {:ok, count} ->
        conn
        |> put_resp_header("access-control-allow-origin", "*")
        |> put_resp_content_type("application/json")
        |> send_resp(
          200,
          Jason.encode!(%{
            status: "ok",
            count: count,
            message: "Successfully synced #{count} channels"
          })
        )

      {:error, reason} ->
        conn
        |> put_resp_header("access-control-allow-origin", "*")
        |> put_resp_content_type("application/json")
        |> send_resp(500, Jason.encode!(%{status: "error", error: to_string(reason)}))
    end
  end

  get "/api/sync/status" do
    status = PlaylistSync.get_status()

    conn
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(status))
  end

  defp handle_update_settings(conn) do
    case SettingsStore.update_settings(conn.body_params) do
      {:ok, settings} ->
        conn
        |> put_resp_header("access-control-allow-origin", "*")
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{status: "updated", settings: settings}))

      {:error, reason} ->
        conn
        |> put_resp_header("access-control-allow-origin", "*")
        |> put_resp_content_type("application/json")
        |> send_resp(
          400,
          Jason.encode!(%{error: "Failed to update settings", reason: to_string(reason)})
        )
    end
  end

  head "/live" do
    case authenticate_request(conn) do
      :ok -> send_head_live(conn)
      :unauthorized -> send_unauthorized(conn)
    end
  end

  head "/live/:target_name" do
    case authenticate_request(conn) do
      :ok ->
        if String.ends_with?(target_name, ".m3u8"),
          do: send_head_m3u8(conn),
          else: send_head_live(conn)

      :unauthorized ->
        send_unauthorized(conn)
    end
  end

  head "/live/:username/:password/:target_name" do
    if Config.authenticate?(username, password) do
      if String.ends_with?(target_name, ".m3u8"),
        do: send_head_m3u8(conn),
        else: send_head_live(conn)
    else
      send_unauthorized(conn)
    end
  end

  head "/h/:target_name" do
    case authenticate_request(conn) do
      :ok -> send_head_m3u8(conn)
      :unauthorized -> send_unauthorized(conn)
    end
  end

  head "/h/:username/:password/:target_name" do
    if Config.authenticate?(username, password) do
      send_head_m3u8(conn)
    else
      send_unauthorized(conn)
    end
  end

  head "/t/:target_name" do
    case authenticate_request(conn) do
      :ok -> send_head_live(conn)
      :unauthorized -> send_unauthorized(conn)
    end
  end

  head "/t/:username/:password/:target_name" do
    if Config.authenticate?(username, password) do
      send_head_live(conn)
    else
      send_unauthorized(conn)
    end
  end

  defp send_head_live(conn) do
    conn
    |> put_resp_header("content-type", "video/mp2t")
    |> put_resp_header("cache-control", "no-cache, no-store, must-revalidate")
    |> put_resp_header("connection", "keep-alive")
    |> put_resp_header("access-control-allow-origin", "*")
    |> send_resp(200, "")
  end

  defp send_head_m3u8(conn) do
    conn
    |> put_resp_header("content-type", "application/vnd.apple.mpegurl; charset=utf-8")
    |> put_resp_header("cache-control", "no-cache, no-store, must-revalidate")
    |> put_resp_header("access-control-allow-origin", "*")
    |> send_resp(200, "")
  end

  defp send_unauthorized(conn) do
    conn
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_header("www-authenticate", "Basic realm=\"AcexGateway\"")
    |> put_resp_content_type("application/json")
    |> send_resp(
      401,
      Jason.encode!(%{error: "Unauthorized", message: "Invalid or missing credentials"})
    )
  end

  defp authenticate_request(conn) do
    if Config.auth_enabled?() do
      conn = fetch_query_params(conn)
      username = conn.query_params["username"] || conn.query_params["user"]
      password = conn.query_params["password"] || conn.query_params["pass"]

      cond do
        is_binary(username) and is_binary(password) and Config.authenticate?(username, password) ->
          :ok

        match_basic_auth?(conn) ->
          :ok

        true ->
          :unauthorized
      end
    else
      :ok
    end
  end

  defp match_basic_auth?(conn) do
    case get_req_header(conn, "authorization") do
      ["Basic " <> encoded] ->
        case Base.decode64(encoded) do
          {:ok, decoded} ->
            case String.split(decoded, ":", parts: 2) do
              [u, p] -> Config.authenticate?(u, p)
              _ -> false
            end

          _ ->
            false
        end

      _ ->
        false
    end
  end

  get "/live" do
    case authenticate_request(conn) do
      :ok ->
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

        handle_live_stream(conn, target, source_type)

      :unauthorized ->
        send_unauthorized(conn)
    end
  end

  # --- Short Stream Routes: HLS (/h/...) ---
  get "/h/:username/:password/:target_name" do
    if Config.authenticate?(username, password) do
      clean_target = String.replace_suffix(target_name, ".m3u8", "")
      handle_cast_playlist(conn, clean_target)
    else
      send_unauthorized(conn)
    end
  end

  get "/h/:target_name" do
    case authenticate_request(conn) do
      :ok ->
        clean_target = String.replace_suffix(target_name, ".m3u8", "")
        handle_cast_playlist(conn, clean_target)

      :unauthorized ->
        send_unauthorized(conn)
    end
  end

  # --- Short Stream Routes: TS (/t/...) ---
  get "/t/:username/:password/:target_name" do
    if Config.authenticate?(username, password) do
      {target, source_type} = parse_stream_target(target_name)
      handle_live_stream(conn, target, source_type)
    else
      send_unauthorized(conn)
    end
  end

  get "/t/:target_name" do
    case authenticate_request(conn) do
      :ok ->
        {target, source_type} = parse_stream_target(target_name)
        handle_live_stream(conn, target, source_type)

      :unauthorized ->
        send_unauthorized(conn)
    end
  end

  get "/live/:target_name" do
    case authenticate_request(conn) do
      :ok ->
        if String.ends_with?(target_name, ".m3u8") do
          clean_target = String.replace_suffix(target_name, ".m3u8", "")
          handle_cast_playlist(conn, clean_target)
        else
          {target, source_type} = parse_stream_target(target_name)
          handle_live_stream(conn, target, source_type)
        end

      :unauthorized ->
        send_unauthorized(conn)
    end
  end

  get "/live/:username/:password/:target_name" do
    if Config.authenticate?(username, password) do
      if String.ends_with?(target_name, ".m3u8") do
        clean_target = String.replace_suffix(target_name, ".m3u8", "")
        handle_cast_playlist(conn, clean_target)
      else
        {target, source_type} = parse_stream_target(target_name)
        handle_live_stream(conn, target, source_type)
      end
    else
      send_unauthorized(conn)
    end
  end

  # --- Chromecast HLS Remuxer Routes ---

  get "/cast/:target_name/live.m3u8" do
    case authenticate_request(conn) do
      :ok ->
        handle_cast_playlist(conn, target_name)

      :unauthorized ->
        send_unauthorized(conn)
    end
  end

  get "/cast/:target_name/:segment_name" do
    handle_cast_segment(conn, target_name, segment_name)
  end

  defp handle_cast_playlist(conn, target_name) do
    clean_target =
      target_name
      |> String.replace_suffix(".m3u8", "")
      |> String.replace_suffix(".ts", "")

    Logger.debug("[Router] Cast playlist requested for '#{clean_target}'")

    base_url = request_base_url(conn)

    case CastRemuxer.get_manifest(clean_target, base_url) do
      {:ok, content} ->
        obfuscated_content =
          SegmentObfuscator.obfuscate_manifest(content)

        conn
        |> put_resp_header("content-type", "application/vnd.apple.mpegurl; charset=utf-8")
        |> put_resp_header(
          "cache-control",
          "no-cache, no-store, must-revalidate, max-age=0, s-maxage=0"
        )
        |> put_resp_header("pragma", "no-cache")
        |> put_resp_header("expires", "0")
        |> put_resp_header("access-control-allow-origin", "*")
        |> send_resp(200, obfuscated_content)

      {:error, :ffmpeg_not_found} ->
        conn
        |> put_resp_header("access-control-allow-origin", "*")
        |> send_resp(503, "FFmpeg is required on server for Chromecast HLS remuxing")

      {:error, reason} ->
        Logger.error("[Router] Cast playlist error for '#{clean_target}': #{inspect(reason)}")

        conn
        |> put_resp_header("access-control-allow-origin", "*")
        |> send_resp(503, "Chromecast remuxer error: #{inspect(reason)}")
    end
  end

  defp handle_cast_segment(conn, target_name, segment_name) do
    clean_target =
      target_name
      |> String.replace_suffix(".m3u8", "")
      |> String.replace_suffix(".ts", "")

    case CastRemuxer.get_segment(clean_target, segment_name) do
      {:ok, segment_path} ->
        mime_type = SegmentObfuscator.content_type_for(segment_name)

        conn
        |> put_resp_header("content-type", mime_type)
        |> put_resp_header("cache-control", "public, max-age=180, s-maxage=180, immutable")
        |> put_resp_header("access-control-allow-origin", "*")
        |> send_file(200, segment_path)

      {:error, reason} ->
        Logger.warning(
          "[Router] Cast segment not found: target='#{clean_target}', segment='#{segment_name}', reason=#{inspect(reason)}"
        )

        conn
        |> put_resp_header("access-control-allow-origin", "*")
        |> send_resp(404, "Segment not found")
    end
  end

  defp parse_stream_target(target_name) do
    raw = String.replace_suffix(target_name, ".ts", "")

    if String.length(raw) == 40 and Regex.match?(~r/^[a-fA-F0-9]{40}$/, raw) do
      {Store.sanitize_hash(raw), :content_id}
    else
      {raw, :channel}
    end
  end

  defp handle_live_stream(conn, target, source_type) do
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

      {:error, :max_channels_reached} ->
        Logger.warning("[Router] Max active channels limit reached.")

        conn
        |> put_resp_header("access-control-allow-origin", "*")
        |> put_resp_content_type("application/json")
        |> send_resp(
          503,
          Jason.encode!(%{
            error: "Max active channels limit reached",
            message:
              "Engine concurrency limit reached. All streaming slots are currently occupied.",
            max_active_channels: Config.max_active_channels()
          })
        )

      {:error, reason} ->
        Logger.error("[Router] Stream subscription failed: #{inspect(reason)}")

        conn
        |> put_resp_header("access-control-allow-origin", "*")
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
      version: AcexGateway.version(),
      engine: "AcexGateway",
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
      progress: session_info[:progress] || 0,
      engine_state: session_info[:engine_state] || :idle,
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

  get "/api/live-stats" do
    conn =
      conn
      |> put_resp_header("content-type", "text/event-stream")
      |> put_resp_header("cache-control", "no-cache, no-store, must-revalidate")
      |> put_resp_header("connection", "keep-alive")
      |> put_resp_header("access-control-allow-origin", "*")
      |> send_chunked(200)

    sse_stats_loop(conn, nil)
  end

  defp sse_stats_loop(conn, last_payload) do
    data = fetch_current_stats()
    payload = Jason.encode!(data)

    new_conn =
      if payload != last_payload do
        case chunk(conn, "data: #{payload}\n\n") do
          {:ok, c} -> c
          {:error, _} -> nil
        end
      else
        case chunk(conn, ": ping\n\n") do
          {:ok, c} -> c
          {:error, _} -> nil
        end
      end

    if new_conn do
      receive do
      after
        1_500 -> sse_stats_loop(new_conn, payload)
      end
    else
      conn
    end
  end

  defp fetch_current_stats do
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

    %{
      version: AcexGateway.version(),
      engine: "AcexGateway",
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
      progress: session_info[:progress] || 0,
      engine_state: session_info[:engine_state] || :idle,
      engine_connected: engine_stats.connected,
      engine_authenticated: engine_stats.authenticated,
      uptime_seconds: uptime,
      active_channels_count: session_info.active_channels_count,
      channels: session_info.channels
    }
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
    case authenticate_request(conn) do
      :ok ->
        base_url = request_base_url(conn)
        channels = Store.list_channels()
        groups = Store.list_groups()
        events = EventsStore.list_events()
        html = DashboardView.render(base_url, channels, groups, events)

        conn
        |> put_resp_content_type("text/html; charset=utf-8")
        |> send_resp(200, html)

      :unauthorized ->
        send_unauthorized(conn)
    end
  end

  options _ do
    conn
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_header("access-control-allow-methods", "GET, POST, PUT, DELETE, HEAD, OPTIONS")
    |> put_resp_header("access-control-allow-headers", "*")
    |> put_resp_header("access-control-max-age", "86400")
    |> send_resp(204, "")
  end

  match _ do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(404, Jason.encode!(%{error: "Not found"}))
  end

  # Helpers

  @max_backlog_chunks 120

  defp request_base_url(conn) do
    proto =
      case Plug.Conn.get_req_header(conn, "x-forwarded-proto") do
        [p | _] when p in ["http", "https"] -> p
        _ -> to_string(conn.scheme)
      end

    host =
      case Plug.Conn.get_req_header(conn, "host") do
        [h | _] -> h
        [] -> "#{conn.host}:#{conn.port}"
      end

    "#{proto}://#{host}"
  end

  defp stream_loop(conn, broadcaster_pid) do
    # Backpressure guard: prevent slow clients from exhausting server memory and corrupting MPEG-TS packets
    case :erlang.process_info(self(), :message_queue_len) do
      {:message_queue_len, len} when len > @max_backlog_chunks ->
        Logger.warning(
          "[Router] Slow client detected (#{inspect(self())}): mailbox backlog reached #{len} chunks. Closing connection cleanly."
        )

        Broadcaster.unsubscribe(broadcaster_pid, self())
        conn

      _ ->
        receive do
          {:stream_burst, chunks} ->
            case send_burst_chunks(conn, chunks) do
              {:ok, conn} ->
                stream_loop(conn, broadcaster_pid)

              {:error, :closed} ->
                Broadcaster.unsubscribe(broadcaster_pid, self())
                conn

              {:error, reason} ->
                Logger.warning("[Router] Downstream write error on burst: #{inspect(reason)}")
                Broadcaster.unsubscribe(broadcaster_pid, self())
                conn
            end

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

  defp send_burst_chunks(conn, []), do: {:ok, conn}

  defp send_burst_chunks(conn, [chunk | rest]) do
    case chunk(conn, chunk) do
      {:ok, conn} -> send_burst_chunks(conn, rest)
      {:error, reason} -> {:error, reason}
    end
  end
end
