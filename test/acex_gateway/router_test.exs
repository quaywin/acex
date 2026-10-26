defmodule AcexGateway.Web.RouterTest do
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn

  alias AcexGateway.Web.Router

  @opts Router.init([])

  test "GET /health returns 200 OK" do
    conn = conn(:get, "/health") |> Router.call(@opts)
    assert conn.status == 200
    assert conn.resp_body == "OK"
  end

  test "GET /favicon.ico returns 200 SVG favicon" do
    conn = conn(:get, "/favicon.ico") |> Router.call(@opts)
    assert conn.status == 200
    assert get_resp_header(conn, "content-type") == ["image/svg+xml"]
    assert conn.resp_body =~ "<svg"
    assert conn.resp_body =~ "viewBox=\"0 0 64 64\""
  end

  test "GET / returns landing HTML dashboard" do
    conn = conn(:get, "/") |> Router.call(@opts)
    assert conn.status == 200
    assert conn.resp_body =~ "AcexGateway"
    assert conn.resp_body =~ "playlist.m3u"
  end

  test "GET /playlist.m3u returns valid m3u format" do
    conn = conn(:get, "/playlist.m3u") |> Router.call(@opts)
    assert conn.status == 200
    assert get_resp_header(conn, "content-type") == ["application/x-mpegurl; charset=utf-8"]
    assert conn.resp_body =~ "#EXTM3U"
    assert conn.resp_body =~ "/live?channel="
  end

  test "GET /api/channels returns JSON channel list" do
    conn = conn(:get, "/api/channels") |> Router.call(@opts)
    assert conn.status == 200
    channels = Jason.decode!(conn.resp_body)
    assert is_list(channels)
    assert length(channels) >= 1
  end

  test "POST /api/channels adds a new channel" do
    payload = %{
      "id" => "news-channel-1",
      "name" => "News Channel HD",
      "country" => "US",
      "group" => "News",
      "sources" => ["news_hash_1", "news_hash_2"]
    }

    conn =
      conn(:post, "/api/channels", payload)
      |> put_req_header("content-type", "application/json")
      |> Router.call(@opts)

    assert conn.status == 201
    resp = Jason.decode!(conn.resp_body)
    assert resp["status"] == "created"
    assert resp["channel"]["id"] == "news-channel-1"
    assert resp["channel"]["country"] == "US"
  end

  test "PUT /api/channels/:id updates an existing channel" do
    payload = %{
      "name" => "News Channel HD Updated",
      "group" => "Breaking News",
      "sources" => ["news_hash_updated"]
    }

    conn =
      conn(:put, "/api/channels/news-channel-1", payload)
      |> put_req_header("content-type", "application/json")
      |> Router.call(@opts)

    assert conn.status == 200
    resp = Jason.decode!(conn.resp_body)
    assert resp["status"] == "updated"
    assert resp["channel"]["name"] == "News Channel HD Updated"
  end

  test "DELETE /api/channels/:id removes channel" do
    conn = conn(:delete, "/api/channels/news-channel-1") |> Router.call(@opts)
    assert conn.status == 200
    resp = Jason.decode!(conn.resp_body)
    assert resp["status"] == "deleted"
  end

  test "OPTIONS / returns 204 with CORS headers" do
    conn = conn(:options, "/live") |> Router.call(@opts)
    assert conn.status == 204
    assert get_resp_header(conn, "access-control-allow-origin") == ["*"]
  end

  test "GET /stat returns JSON telemetry with buffer info" do
    conn = conn(:get, "/stat") |> Router.call(@opts)
    assert conn.status == 200
    data = Jason.decode!(conn.resp_body)
    assert data["version"] == "0.1.0"
    assert data["engine"] =~ "AcexGateway"
    assert Map.has_key?(data, "buffered_bytes")
    assert Map.has_key?(data, "channels")
    assert Map.has_key?(data, "active_channels_count")
    assert Map.has_key?(data, "active_channel_name")
  end

  test "GET /restart triggers reset and returns ok" do
    conn = conn(:get, "/restart") |> Router.call(@opts)
    assert conn.status == 200
    data = Jason.decode!(conn.resp_body)
    assert data["status"] == "ok"
  end

  test "POST /api/channels/preview returns parsed channels without saving" do
    payload = %{
      "content" => "VTV1 HD | 1234567890123456789012345678901234567890 | VN | News",
      "default_group" => "TV",
      "default_country" => "VN"
    }

    conn =
      conn(:post, "/api/channels/preview", payload)
      |> put_req_header("content-type", "application/json")
      |> Router.call(@opts)

    assert conn.status == 200
    resp = Jason.decode!(conn.resp_body)
    assert resp["count"] == 1
    ch = hd(resp["channels"])
    assert ch["name"] == "VTV1 HD"
    assert ch["country"] == "VN"
  end

  test "POST /api/channels/import saves imported channels" do
    payload = %{
      "content" => "EuroSport 1 | 9999888877776666555544443333222211110000 | EU | Sports",
      "mode" => "merge"
    }

    conn =
      conn(:post, "/api/channels/import", payload)
      |> put_req_header("content-type", "application/json")
      |> Router.call(@opts)

    assert conn.status == 200
    resp = Jason.decode!(conn.resp_body)
    assert resp["status"] == "imported"
    assert resp["count"] == 1

    # Clean up
    AcexGateway.Channels.Store.delete_channel("eurosport-1")
  end

  test "GET /api/channels/export returns txt, m3u, and json downloads" do
    # 1. Text format
    conn_txt = conn(:get, "/api/channels/export?format=txt") |> Router.call(@opts)
    assert conn_txt.status == 200
    assert get_resp_header(conn_txt, "content-type") == ["text/plain; charset=utf-8"]
    assert conn_txt.resp_body =~ " | "

    # 2. M3U format
    conn_m3u = conn(:get, "/api/channels/export?format=m3u") |> Router.call(@opts)
    assert conn_m3u.status == 200
    assert get_resp_header(conn_m3u, "content-type") == ["application/x-mpegurl; charset=utf-8"]
    assert conn_m3u.resp_body =~ "#EXTM3U"

    # 3. JSON format
    conn_json = conn(:get, "/api/channels/export?format=json") |> Router.call(@opts)
    assert conn_json.status == 200
    assert get_resp_header(conn_json, "content-type") == ["application/json; charset=utf-8"]
    decoded = Jason.decode!(conn_json.resp_body)
    assert is_list(decoded)
  end
end
