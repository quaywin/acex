defmodule AcexGateway.Web.XtreamCodesTest do
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn

  alias AcexGateway.Web.Router

  @opts Router.init([])

  setup do
    # Clear auth env vars for baseline tests
    System.delete_env("AUTH_USERNAME")
    System.delete_env("AUTH_PASSWORD")

    AcexGateway.Settings.Store.update_settings(%{
      "auth_enabled" => false,
      "auth_username" => "",
      "auth_password" => ""
    })

    :ok
  end

  test "GET /player_api.php returns handshake when no auth configured" do
    conn = conn(:get, "/player_api.php") |> Router.call(@opts)
    assert conn.status == 200

    resp = Jason.decode!(conn.resp_body)
    assert resp["user_info"]["auth"] == 1
    assert resp["user_info"]["status"] == "Active"
    assert is_binary(resp["server_info"]["port"])
  end

  test "GET /player_api.php?action=get_live_categories returns category list" do
    conn = conn(:get, "/player_api.php?action=get_live_categories") |> Router.call(@opts)
    assert conn.status == 200

    categories = Jason.decode!(conn.resp_body)
    assert is_list(categories)
    assert length(categories) >= 1
    assert hd(categories)["category_name"] != nil
  end

  test "GET /player_api.php?action=get_live_streams returns stream list" do
    conn = conn(:get, "/player_api.php?action=get_live_streams") |> Router.call(@opts)
    assert conn.status == 200

    streams = Jason.decode!(conn.resp_body)
    assert is_list(streams)
    assert length(streams) >= 1
    sample = hd(streams)
    assert sample["stream_type"] == "live"
    assert sample["stream_id"] != nil
  end

  test "GET /player_api.php blocks unauthorized user when auth configured" do
    AcexGateway.Settings.Store.update_settings(%{
      "auth_enabled" => true,
      "auth_username" => "admin",
      "auth_password" => "secret123"
    })

    on_exit(fn ->
      AcexGateway.Settings.Store.update_settings(%{"auth_enabled" => false})
    end)

    # 1. Without credentials -> disabled
    conn = conn(:get, "/player_api.php") |> Router.call(@opts)
    assert conn.status == 200
    resp = Jason.decode!(conn.resp_body)
    assert resp["user_info"]["auth"] == 0

    # 2. With wrong credentials -> disabled
    conn = conn(:get, "/player_api.php?username=admin&password=wrong") |> Router.call(@opts)
    assert conn.status == 200
    resp = Jason.decode!(conn.resp_body)
    assert resp["user_info"]["auth"] == 0

    # 3. With correct credentials -> active
    conn = conn(:get, "/player_api.php?username=admin&password=secret123") |> Router.call(@opts)
    assert conn.status == 200
    resp = Jason.decode!(conn.resp_body)
    assert resp["user_info"]["auth"] == 1
    assert resp["user_info"]["username"] == "admin"
  end

  test "HEAD /live/:username/:password/:channel.ts validates Xtream stream credentials" do
    AcexGateway.Settings.Store.update_settings(%{
      "auth_enabled" => true,
      "auth_username" => "admin",
      "auth_password" => "secret123"
    })

    on_exit(fn ->
      AcexGateway.Settings.Store.update_settings(%{"auth_enabled" => false})
    end)

    # Wrong credentials -> 401
    conn = conn(:head, "/live/admin/wrong/big-buck-bunny.ts") |> Router.call(@opts)
    assert conn.status == 401

    # Correct credentials -> 200
    conn = conn(:head, "/live/admin/secret123/big-buck-bunny.ts") |> Router.call(@opts)
    assert conn.status == 200
    assert get_resp_header(conn, "content-type") == ["video/mp2t"]
  end

  test "GET /player_api.php handshake reflects configured xtream_format" do
    AcexGateway.Settings.Store.update_settings(%{"xtream_format" => "hls"})
    conn = conn(:get, "/player_api.php") |> Router.call(@opts)
    resp = Jason.decode!(conn.resp_body)
    assert resp["user_info"]["allowed_output_formats"] == ["m3u8", "ts"]

    AcexGateway.Settings.Store.update_settings(%{"xtream_format" => "ts"})
    conn = conn(:get, "/player_api.php") |> Router.call(@opts)
    resp = Jason.decode!(conn.resp_body)
    assert resp["user_info"]["allowed_output_formats"] == ["ts", "m3u8"]

    # Reset back to hls
    AcexGateway.Settings.Store.update_settings(%{"xtream_format" => "hls"})
  end

  test "POST /player_api.php accepts action in body parameters" do
    body = Plug.Conn.Query.encode(%{"action" => "get_live_categories"})

    conn =
      conn(:post, "/player_api.php", body)
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> Router.call(@opts)

    assert conn.status == 200
    categories = Jason.decode!(conn.resp_body)
    assert is_list(categories)
  end

  test "GET /player_api.php?action=get_live_streams outputs integer stream_id" do
    conn = conn(:get, "/player_api.php?action=get_live_streams") |> Router.call(@opts)
    assert conn.status == 200

    streams = Jason.decode!(conn.resp_body)
    assert is_list(streams)
    assert length(streams) >= 1

    # All streams must have integer stream_id and category_ids array of integers
    Enum.each(streams, fn stream ->
      assert is_integer(stream["stream_id"])
      assert is_integer(stream["num"])
      assert is_list(stream["category_ids"])
      assert Enum.all?(stream["category_ids"], &is_integer/1)
      assert is_binary(stream["category_id"])
    end)

    # Test stream resolution by numeric stream_id
    sample = hd(streams)
    sid = sample["stream_id"]
    conn_stream = conn(:head, "/live/#{sid}.ts") |> Router.call(@opts)
    assert conn_stream.status == 200
  end
end
