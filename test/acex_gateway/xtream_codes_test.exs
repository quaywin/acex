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
end
