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

  test "GET / returns landing HTML dashboard with player, fleet banner, and filters" do
    conn = conn(:get, "/") |> Router.call(@opts)
    assert conn.status == 200
    assert conn.resp_body =~ "AcexGateway"
    assert conn.resp_body =~ "playlist.m3u"
    assert conn.resp_body =~ "fleet-health-banner"
    assert conn.resp_body =~ "filter-tab-pill"
    assert conn.resp_body =~ "webPlayerModal"
    assert conn.resp_body =~ "hls.min.js"
    assert conn.resp_body =~ "updateBadgeBtn"
    assert conn.resp_body =~ "updateModal"
    assert conn.resp_body =~ "manualUpdateCmdInput"
  end

  test "GET /playlist.m3u and /playlist.m3u8 return valid m3u format" do
    for path <- ["/playlist.m3u", "/playlist.m3u8"] do
      conn = conn(:get, path) |> Router.call(@opts)
      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["application/x-mpegurl; charset=utf-8"]
      assert conn.resp_body =~ "#EXTM3U"
      assert conn.resp_body =~ "/live?channel="
      assert conn.resp_body =~ "tvg-chno="
    end
  end

  test "HEAD /live and /live/:target.ts return MPEG-TS headers" do
    for path <- ["/live", "/live/test-channel.ts"] do
      conn = conn(:head, path) |> Router.call(@opts)
      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["video/mp2t"]
    end
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
    assert data["version"] == AcexGateway.version()
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

  test "GET /api/channels/export returns txt, m3u, m3u8, and json downloads" do
    # 1. Text format
    conn_txt = conn(:get, "/api/channels/export?format=txt") |> Router.call(@opts)
    assert conn_txt.status == 200
    assert get_resp_header(conn_txt, "content-type") == ["text/plain; charset=utf-8"]
    assert conn_txt.resp_body =~ " | "

    # 2. M3U and M3U8 formats
    conn_m3u = conn(:get, "/api/channels/export?format=m3u") |> Router.call(@opts)
    assert conn_m3u.status == 200
    assert get_resp_header(conn_m3u, "content-type") == ["application/x-mpegurl; charset=utf-8"]

    assert get_resp_header(conn_m3u, "content-disposition") == [
             "attachment; filename=\"acex_channels.m3u\""
           ]

    assert conn_m3u.resp_body =~ "#EXTM3U"

    conn_m3u8 = conn(:get, "/api/channels/export?format=m3u8") |> Router.call(@opts)
    assert conn_m3u8.status == 200
    assert get_resp_header(conn_m3u8, "content-type") == ["application/x-mpegurl; charset=utf-8"]

    assert get_resp_header(conn_m3u8, "content-disposition") == [
             "attachment; filename=\"acex_channels.m3u8\""
           ]

    assert conn_m3u8.resp_body =~ "#EXTM3U"

    # 3. JSON format
    conn_json = conn(:get, "/api/channels/export?format=json") |> Router.call(@opts)
    assert conn_json.status == 200
    assert get_resp_header(conn_json, "content-type") == ["application/json; charset=utf-8"]
    decoded = Jason.decode!(conn_json.resp_body)
    assert is_list(decoded)
  end

  test "GET and POST /api/settings manages runtime credentials" do
    # 1. GET settings
    conn_get = conn(:get, "/api/settings") |> Router.call(@opts)
    assert conn_get.status == 200
    initial = Jason.decode!(conn_get.resp_body)
    assert Map.has_key?(initial, "auth_enabled")
    assert Map.has_key?(initial, "auth_username")
    assert Map.has_key?(initial, "auth_password")

    # 2. POST update settings
    payload = %{
      "auth_enabled" => true,
      "auth_username" => "testadmin",
      "auth_password" => "testpass123",
      "epg_url" => "https://my-epg.com/epg.xml"
    }

    conn_post =
      conn(:post, "/api/settings", payload)
      |> put_req_header("content-type", "application/json")
      |> Router.call(@opts)

    assert conn_post.status == 200
    resp = Jason.decode!(conn_post.resp_body)
    assert resp["status"] == "updated"
    assert resp["settings"]["auth_enabled"] == true
    assert resp["settings"]["auth_username"] == "testadmin"
    assert resp["settings"]["auth_password"] == "testpass123"

    # 3. Playlist exports with auth credentials attached
    conn_m3u =
      conn(:get, "/playlist.m3u8?username=testadmin&password=testpass123")
      |> Router.call(@opts)

    assert conn_m3u.status == 200
    assert conn_m3u.resp_body =~ "/live/testadmin/testpass123/"

    # Reset settings back to disabled for other tests
    conn_reset =
      conn(:post, "/api/settings", %{"auth_enabled" => false})
      |> put_req_header("content-type", "application/json")
      |> Router.call(@opts)

    assert conn_reset.status == 200
  end

  test "POST /api/channels/validate-source validates hash format" do
    # Invalid hash format
    conn_invalid =
      conn(:post, "/api/channels/validate-source", %{"source" => "invalid_short_hash"})
      |> put_req_header("content-type", "application/json")
      |> Router.call(@opts)

    assert conn_invalid.status == 200
    resp_invalid = Jason.decode!(conn_invalid.resp_body)
    assert resp_invalid["status"] == "ok"
    assert resp_invalid["result"]["valid"] == false
    assert resp_invalid["result"]["error"] == "invalid_hash_format"
  end

  test "POST /api/channels/:id/validate returns report or 404" do
    # 404 for non-existent channel
    conn_404 =
      conn(:post, "/api/channels/non-existent-channel/validate", %{})
      |> put_req_header("content-type", "application/json")
      |> Router.call(@opts)

    assert conn_404.status == 404

    # 200 for existing channel (e.g. big-buck-bunny)
    conn_ok =
      conn(:post, "/api/channels/big-buck-bunny/validate", %{"force" => false})
      |> put_req_header("content-type", "application/json")
      |> Router.call(@opts)

    assert conn_ok.status == 200
    resp = Jason.decode!(conn_ok.resp_body)
    assert resp["status"] == "ok"
    assert Map.has_key?(resp["report"], "alive_count")
    assert Map.has_key?(resp["report"], "dead_count")
    assert Map.has_key?(resp["report"], "results")
  end

  test "POST /api/channels/:id/prune-dead cleans up dead sources" do
    # 1. Channel not found returns 404
    conn_404 =
      conn(:post, "/api/channels/non-existent/prune-dead", %{})
      |> put_req_header("content-type", "application/json")
      |> Router.call(@opts)

    assert conn_404.status == 404

    # 2. Channel with 1 source protects it and returns error/400
    ch_single = %{
      "id" => "prune-router-single",
      "name" => "Single Channel",
      "sources" => ["single_dead_src"]
    }

    AcexGateway.Channels.Store.save_channel(ch_single)

    conn_single =
      conn(:post, "/api/channels/prune-router-single/prune-dead", %{
        "dead_sources" => ["single_dead_src"]
      })
      |> put_req_header("content-type", "application/json")
      |> Router.call(@opts)

    assert conn_single.status == 400
    assert Jason.decode!(conn_single.resp_body)["error"] =~ "Cannot prune single-source channel"

    # 3. Channel with multiple sources successfully prunes specified dead sources
    ch_multi = %{
      "id" => "prune-router-multi",
      "name" => "Multi Channel",
      "sources" => ["alive_src_1", "dead_src_2", "dead_src_3"]
    }

    AcexGateway.Channels.Store.save_channel(ch_multi)

    conn_multi =
      conn(:post, "/api/channels/prune-router-multi/prune-dead", %{
        "dead_sources" => ["dead_src_2", "dead_src_3"]
      })
      |> put_req_header("content-type", "application/json")
      |> Router.call(@opts)

    assert conn_multi.status == 200
    resp_multi = Jason.decode!(conn_multi.resp_body)
    assert resp_multi["status"] == "ok"
    assert resp_multi["pruned_count"] == 2
    assert resp_multi["channel"]["sources"] == ["alive_src_1"]

    # Cleanup
    AcexGateway.Channels.Store.delete_channel("prune-router-single")
    AcexGateway.Channels.Store.delete_channel("prune-router-multi")
  end

  test "POST /api/channels/prune-all-dead cleans dead sources across all multi-source channels" do
    # Pre-cache valid_hash as alive
    valid_hash = "1111222233334444555566667777888899990000"
    AcexGateway.Engine.Validator.ensure_cache()
    now = System.monotonic_time(:second) + 60

    :ets.insert(
      :acex_validator_cache,
      {valid_hash,
       %{
         source: valid_hash,
         clean_source: valid_hash,
         valid: true,
         infohash: "ok",
         response_time_ms: 5,
         error: nil
       }, now}
    )

    # Multi-source channel with 1 alive and 2 invalid dead sources
    ch_multi = %{
      "id" => "bulk-prune-test-1",
      "name" => "Bulk Prune Test",
      "sources" => [valid_hash, "dead_short_1", "dead_short_2"]
    }

    AcexGateway.Channels.Store.save_channel(ch_multi)

    # Single-source channel (must be protected)
    ch_single = %{
      "id" => "bulk-prune-test-single",
      "name" => "Bulk Prune Single",
      "sources" => ["dead_short_single"]
    }

    AcexGateway.Channels.Store.save_channel(ch_single)

    conn =
      conn(:post, "/api/channels/prune-all-dead", %{})
      |> put_req_header("content-type", "application/json")
      |> Router.call(@opts)

    assert conn.status == 200
    resp = Jason.decode!(conn.resp_body)
    assert resp["status"] == "ok"
    assert resp["pruned_sources_count"] >= 2

    # Verify single source is untouched
    stored_single = AcexGateway.Channels.Store.get_channel("bulk-prune-test-single")
    assert stored_single["sources"] == ["dead_short_single"]

    # Verify multi channel had invalid sources pruned
    stored_multi = AcexGateway.Channels.Store.get_channel("bulk-prune-test-1")
    assert stored_multi["sources"] == [valid_hash]

    # Cleanup
    AcexGateway.Channels.Store.delete_channel("bulk-prune-test-1")
    AcexGateway.Channels.Store.delete_channel("bulk-prune-test-single")
  end

  test "GET /api/system/version returns system version and update information" do
    # 1. Standard check (uses ETS cache or fallback gracefully)
    conn = conn(:get, "/api/system/version") |> Router.call(@opts)
    assert conn.status == 200
    assert get_resp_header(conn, "content-type") == ["application/json; charset=utf-8"]
    data = Jason.decode!(conn.resp_body)
    assert data["current_version"] == AcexGateway.version()
    assert Map.has_key?(data, "latest_version")
    assert Map.has_key?(data, "has_update")
    assert Map.has_key?(data, "update_method")
    assert Map.has_key?(data, "release_notes")

    # 2. Check with force=true
    conn_force = conn(:get, "/api/system/version?force=true") |> Router.call(@opts)
    assert conn_force.status == 200
    data_force = Jason.decode!(conn_force.resp_body)
    assert data_force["current_version"] == AcexGateway.version()
  end

  test "POST /api/system/update triggers system update workflow" do
    conn = conn(:post, "/api/system/update", %{}) |> Router.call(@opts)
    assert conn.status in [200, 500]
    data = Jason.decode!(conn.resp_body)
    assert Map.has_key?(data, "status")
    assert Map.has_key?(data, "message")
  end

  test "GET /cast/:target/live.m3u8 routes to CastRemuxer" do
    conn = conn(:get, "/cast/test-cast-target/live.m3u8") |> Router.call(@opts)
    # Without an active stream or if FFmpeg is starting/timing out, returns 503 or 200
    assert conn.status in [200, 503]
    assert get_resp_header(conn, "access-control-allow-origin") == ["*"]
  end

  test "GET /cast/:target/:segment returns 404 for non-existent segment" do
    conn = conn(:get, "/cast/test-cast-target/seg_999.ts") |> Router.call(@opts)
    assert conn.status == 404
    assert get_resp_header(conn, "access-control-allow-origin") == ["*"]
  end

  test "GET /api/groups returns list of groups with channel count" do
    conn = conn(:get, "/api/groups") |> Router.call(@opts)
    assert conn.status == 200
    groups = Jason.decode!(conn.resp_body)
    assert is_list(groups)
    assert length(groups) >= 1
    assert Enum.any?(groups, fn g -> g["name"] == "General" end)
    general = Enum.find(groups, fn g -> g["name"] == "General" end)
    assert Map.has_key?(general, "channel_count")
  end

  test "POST, PUT, DELETE /api/groups manages groups and cascades changes" do
    unique_tag = System.unique_integer([:positive])
    init_name = "Anime #{unique_tag}"
    renamed_name = "Animation #{unique_tag}"
    ch_id = "anime-ch-#{unique_tag}"

    # 1. POST /api/groups creates a new group
    conn_create =
      conn(:post, "/api/groups", %{"name" => init_name})
      |> put_req_header("content-type", "application/json")
      |> Router.call(@opts)

    assert conn_create.status == 201
    resp_create = Jason.decode!(conn_create.resp_body)
    assert resp_create["status"] == "created"
    assert resp_create["group"]["name"] == init_name
    group_id = resp_create["group"]["id"]

    # 2. Add channel to that group
    ch = %{
      "id" => ch_id,
      "name" => "Anime Channel",
      "group" => init_name,
      "sources" => ["anime_hash_1"]
    }

    AcexGateway.Channels.Store.save_channel(ch)

    # 3. PUT /api/groups/:id renames group and cascades to channel
    conn_rename =
      conn(:put, "/api/groups/#{group_id}", %{"name" => renamed_name})
      |> put_req_header("content-type", "application/json")
      |> Router.call(@opts)

    assert conn_rename.status == 200
    resp_rename = Jason.decode!(conn_rename.resp_body)
    assert resp_rename["status"] == "updated"
    assert resp_rename["group"]["name"] == renamed_name
    assert AcexGateway.Channels.Store.get_channel(ch_id)["group"] == renamed_name

    # 4. DELETE /api/groups/:id deletes group and reassigns channel to fallback
    conn_del =
      conn(:delete, "/api/groups/#{group_id}?fallback_group=General")
      |> Router.call(@opts)

    assert conn_del.status == 200
    resp_del = Jason.decode!(conn_del.resp_body)
    assert resp_del["status"] == "deleted"
    assert AcexGateway.Channels.Store.get_channel(ch_id)["group"] == "General"

    # Cleanup
    AcexGateway.Channels.Store.delete_channel(ch_id)
  end

  test "PATCH /api/channels/:id/group reassigns single channel group" do
    ch = %{
      "id" => "patch-group-ch",
      "name" => "Patch Channel",
      "group" => "General",
      "sources" => ["patch_group_hash"]
    }

    AcexGateway.Channels.Store.save_channel(ch)

    conn =
      conn(:patch, "/api/channels/patch-group-ch/group", %{"group" => "Documentaries"})
      |> put_req_header("content-type", "application/json")
      |> Router.call(@opts)

    assert conn.status == 200
    resp = Jason.decode!(conn.resp_body)
    assert resp["status"] == "ok"
    assert resp["channel"]["group"] == "Documentaries"
    assert AcexGateway.Channels.Store.get_channel("patch-group-ch")["group"] == "Documentaries"

    # Cleanup
    AcexGateway.Channels.Store.delete_channel("patch-group-ch")
  end

  test "POST /api/channels/bulk-move and bulk-delete batch operation" do
    ch1 = %{
      "id" => "bulk-test-ch-1",
      "name" => "Bulk 1",
      "group" => "General",
      "sources" => ["bulk_h1"]
    }

    ch2 = %{
      "id" => "bulk-test-ch-2",
      "name" => "Bulk 2",
      "group" => "General",
      "sources" => ["bulk_h2"]
    }

    AcexGateway.Channels.Store.save_channel(ch1)
    AcexGateway.Channels.Store.save_channel(ch2)

    # 1. Bulk move
    conn_move =
      conn(:post, "/api/channels/bulk-move", %{
        "channel_ids" => ["bulk-test-ch-1", "bulk-test-ch-2"],
        "group" => "Gaming & Esports"
      })
      |> put_req_header("content-type", "application/json")
      |> Router.call(@opts)

    assert conn_move.status == 200
    resp_move = Jason.decode!(conn_move.resp_body)
    assert resp_move["status"] == "ok"
    assert resp_move["moved_count"] == 2
    assert AcexGateway.Channels.Store.get_channel("bulk-test-ch-1")["group"] == "Gaming & Esports"
    assert AcexGateway.Channels.Store.get_channel("bulk-test-ch-2")["group"] == "Gaming & Esports"

    # 2. Bulk delete
    conn_del =
      conn(:post, "/api/channels/bulk-delete", %{
        "channel_ids" => ["bulk-test-ch-1", "bulk-test-ch-2"]
      })
      |> put_req_header("content-type", "application/json")
      |> Router.call(@opts)

    assert conn_del.status == 200
    resp_del = Jason.decode!(conn_del.resp_body)
    assert resp_del["status"] == "ok"
    assert resp_del["deleted_count"] == 2
    assert AcexGateway.Channels.Store.get_channel("bulk-test-ch-1") == nil
    assert AcexGateway.Channels.Store.get_channel("bulk-test-ch-2") == nil
  end
end
