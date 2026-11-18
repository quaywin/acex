defmodule AcexGateway.Web.XtreamCodes do
  @moduledoc """
  Implements the industry-standard Xtream Codes API (`/player_api.php`) for seamless
  integration with IPTV players like TiviMate, IPTV Smarters Pro, and XCIPTV.
  """

  alias AcexGateway.Channels.Store
  alias AcexGateway.Config

  @doc """
  Dispatches an incoming `/player_api.php` request based on query or form parameters.
  """
  def handle_request(params, base_url) do
    username = params["username"] || params[:username] || ""
    password = params["password"] || params[:password] || ""
    action = params["action"] || params[:action]

    if Config.authenticate?(username, password) do
      case action do
        nil ->
          {:ok, build_handshake(username, password, base_url)}

        "" ->
          {:ok, build_handshake(username, password, base_url)}

        "get_live_categories" ->
          {:ok, get_categories()}

        "get_live_streams" ->
          category_id = params["category_id"] || params[:category_id]
          stream_id = params["stream_id"] || params[:stream_id]
          {:ok, get_live_streams(category_id, stream_id)}

        "get_vod_categories" ->
          {:ok, []}

        "get_vod_streams" ->
          {:ok, []}

        "get_series_categories" ->
          {:ok, []}

        "get_series" ->
          {:ok, []}

        "get_short_epg" ->
          {:ok, %{"epg_listings" => []}}

        "get_simple_data_table" ->
          {:ok, %{"epg_listings" => []}}

        _unknown ->
          {:ok, %{}}
      end
    else
      {:unauthorized, %{"user_info" => %{"auth" => 0, "status" => "Disabled"}}}
    end
  end

  defp build_handshake(username, password, base_url) do
    now = System.system_time(:second)

    uri = URI.parse(base_url)
    host = uri.host || "localhost"
    port = uri.port || Config.proxy_port()
    port_str = to_string(port)
    server_protocol = uri.scheme || "http"

    formats =
      case Config.xtream_format() do
        "ts" -> ["ts", "m3u8"]
        _ -> ["m3u8", "ts"]
      end

    time_now_str = Calendar.strftime(DateTime.utc_now(), "%Y-%m-%d %H:%M:%S")

    %{
      "user_info" => %{
        "username" => if(username == "", do: "guest", else: username),
        "password" => password,
        "message" => "Welcome to AcexGateway IPTV",
        "auth" => 1,
        "status" => "Active",
        "exp_date" => "1999999999",
        "is_trial" => "0",
        "active_cons" => "1",
        "created_at" => "1700000000",
        "max_connections" => "100",
        "allowed_output_formats" => formats
      },
      "server_info" => %{
        "url" => host,
        "port" => port_str,
        "https_port" => port_str,
        "server_protocol" => server_protocol,
        "rtmp_port" => port_str,
        "timezone" => "UTC",
        "timestamp_now" => now,
        "time_now" => time_now_str
      }
    }
  end

  defp build_category_mapping(channels) do
    # Channel groups that actually have channels (> 0)
    channel_counts = Enum.frequencies_by(channels, fn c -> c["group"] || "General" end)
    groups = Store.list_groups()

    sorted_channel_groups =
      groups
      |> Enum.filter(fn g -> Map.get(channel_counts, g["name"], 0) > 0 end)
      |> Enum.sort_by(&(&1["order"] || 999))
      |> Enum.map(& &1["name"])

    extra_channel_groups =
      channels
      |> Enum.map(&(&1["group"] || "General"))
      |> Enum.uniq()
      |> Enum.reject(&(&1 in sorted_channel_groups))

    channel_group_names = sorted_channel_groups ++ extra_channel_groups

    Map.new(Enum.with_index(channel_group_names, 1), fn {name, idx} ->
      {name, to_string(idx)}
    end)
  end

  defp get_categories do
    channels = Store.list_channels()
    cat_map = build_category_mapping(channels)

    cat_map
    |> Enum.sort_by(fn {_name, id_str} -> String.to_integer(id_str) end)
    |> Enum.map(fn {group_name, cat_id} ->
      %{
        "category_id" => cat_id,
        "category_name" => group_name,
        "parent_id" => 0
      }
    end)
  end

  defp get_live_streams(category_id, stream_id) do
    channels = Store.list_channels()
    cat_map = build_category_mapping(channels)

    channel_streams =
      Enum.with_index(channels, 1)
      |> Enum.map(fn {c, idx} ->
        group = c["group"] || "General"
        cat_id = Map.get(cat_map, group, "1")

        cat_id_int =
          case Integer.parse(cat_id) do
            {n, ""} -> n
            _ -> 1
          end

        name = Store.format_playlist_title(c["name"], c["country"])
        sid = c["stream_id"] || idx

        %{
          "num" => sid,
          "name" => name,
          "stream_type" => "live",
          "stream_id" => sid,
          "stream_icon" => c["logo"] || "",
          "epg_channel_id" => to_string(sid),
          "added" => "1700000000",
          "category_id" => cat_id,
          "category_ids" => [cat_id_int],
          "custom_sid" => "",
          "tv_archive" => 0,
          "direct_source" => "",
          "tv_archive_duration" => 0
        }
      end)

    filtered_by_cat =
      case category_id do
        nil ->
          channel_streams

        "" ->
          channel_streams

        cid ->
          cid_str = to_string(cid)
          Enum.filter(channel_streams, &(&1["category_id"] == cid_str))
      end

    case stream_id do
      nil ->
        filtered_by_cat

      "" ->
        filtered_by_cat

      sid ->
        sid_str = to_string(sid)
        Enum.filter(filtered_by_cat, &(to_string(&1["stream_id"]) == sid_str))
    end
  end
end
