defmodule AcexGateway.Web.XtreamCodes do
  @moduledoc """
  Implements the industry-standard Xtream Codes API (`/player_api.php`) for seamless
  integration with IPTV players like TiviMate, IPTV Smarters Pro, and XCIPTV.
  """

  alias AcexGateway.Channels.Store
  alias AcexGateway.Config

  @doc """
  Dispatches an incoming `/player_api.php` request based on query parameters.
  """
  def handle_request(params, base_url) do
    username = params["username"] || ""
    password = params["password"] || ""
    action = params["action"]

    if Config.authenticate?(username, password) do
      case action do
        nil ->
          {:ok, build_handshake(username, password, base_url)}

        "" ->
          {:ok, build_handshake(username, password, base_url)}

        "get_live_categories" ->
          {:ok, get_categories()}

        "get_live_streams" ->
          category_id = params["category_id"]
          {:ok, get_live_streams(category_id)}

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
    port_str = to_string(Config.proxy_port())

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
        "allowed_output_formats" => ["ts", "m3u8"]
      },
      "server_info" => %{
        "url" => base_url,
        "port" => port_str,
        "https_port" => port_str,
        "server_protocol" => "http",
        "rtmp_port" => port_str,
        "timezone" => "UTC",
        "timestamp_now" => now,
        "time_now" => DateTime.utc_now() |> DateTime.to_iso8601()
      }
    }
  end

  defp get_categories do
    groups = Store.list_groups()

    Enum.map(groups, fn g ->
      %{
        "category_id" => to_string(g["order"] || 1),
        "category_name" => g["name"],
        "parent_id" => 0
      }
    end)
  end

  defp get_live_streams(category_id) do
    channels = Store.list_channels()
    groups = Store.list_groups()

    group_to_cat_id =
      Map.new(groups, fn g ->
        {g["name"], to_string(g["order"] || 1)}
      end)

    streams =
      channels
      |> Enum.with_index(1)
      |> Enum.map(fn {c, num} ->
        group = c["group"] || "General"
        cat_id = Map.get(group_to_cat_id, group, "1")
        name = Store.format_playlist_title(c["name"], c["country"])

        %{
          "num" => num,
          "name" => name,
          "stream_type" => "live",
          "stream_id" => c["id"],
          "stream_icon" => c["logo"] || "",
          "epg_channel_id" => c["id"],
          "added" => "1700000000",
          "category_id" => cat_id,
          "custom_sid" => "",
          "tv_archive" => 0,
          "direct_source" => "",
          "tv_archive_duration" => 0
        }
      end)

    case category_id do
      nil ->
        streams

      "" ->
        streams

      cid ->
        Enum.filter(streams, &(&1["category_id"] == to_string(cid)))
    end
  end
end
