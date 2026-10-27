defmodule AcexGateway.Engine.ProtocolTest do
  use ExUnit.Case, async: true
  alias AcexGateway.Engine.Protocol

  test "compute_ready_key matches python hashlib sha1" do
    req_key = "test123"
    ready_key = Protocol.compute_ready_key(req_key)
    assert ready_key == "n51LvQoTlJzNGaFxseRK-30306f6b44dfe91302cd8b1ffbb612c6d450c8d1"
  end

  test "parse_hellots extracts key and http_port" do
    line = "HELLOTS version=3.1.74 key=987654 http_port=6878"
    assert Protocol.parse_hellots(line) == %{key: "987654", http_port: 6878}
  end

  test "parse_start_url decodes URI correctly" do
    line = "START url=http%3A%2F%2F127.0.0.1%3A6878%2Face%2Fgetstream%3Fid%3Dabc123"

    assert Protocol.parse_start_url(line) ==
             {:ok, "http://127.0.0.1:6878/ace/getstream?id=abc123"}
  end

  test "parse_status extracts peers and speed" do
    line = "STATUS main:dl|peers:24|speed_down:3500|progress:100.0"
    stats = Protocol.parse_status(line)
    assert stats.peers == 24
    assert stats.speed_kbps == 3500
    assert stats.progress == 100.0
    assert stats.engine_state == :downloading
  end

  test "parse_status parses positional prebuf and buf lines" do
    prebuf_line = "STATUS main:prebuf|58|4|10"
    prebuf_stats = Protocol.parse_status(prebuf_line)
    assert prebuf_stats.engine_state == :prebuf
    assert prebuf_stats.progress == 58
    assert prebuf_stats.peers == 4

    buf_line = "STATUS main:buf|85"
    buf_stats = Protocol.parse_status(buf_line)
    assert buf_stats.engine_state == :buffering
    assert buf_stats.progress == 85

    idle_line = "STATUS main:idle"
    idle_stats = Protocol.parse_status(idle_line)
    assert idle_stats.engine_state == :idle
  end

  test "parse_state correctly maps engine states and detects errors" do
    assert Protocol.parse_state("STATE 0") == {:ok, :idle, 0}
    assert Protocol.parse_state("STATE 1") == {:ok, :prebuf, 1}
    assert Protocol.parse_state("STATE 2") == {:ok, :downloading, 2}
    assert Protocol.parse_state("STATE 3") == {:ok, :buffering, 3}
    assert Protocol.parse_state("STATE 4") == {:ok, :completed, 4}
    assert Protocol.parse_state("STATE 5") == {:ok, :checking, 5}
    assert Protocol.parse_state("STATE 6") == {:error, :engine_error, 6}
    assert Protocol.parse_state("STATE 6 extra_info") == {:error, :engine_error, 6}
    assert Protocol.parse_state("INVALID") == :error
  end

  test "parse_loadresp extracts infohash or detects errors" do
    valid_line =
      ~s(LOADRESP 0 {"infohash": "dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c", "checksum": "abc"})

    assert Protocol.parse_loadresp(valid_line) ==
             {:ok, "dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c"}

    assert Protocol.parse_infohash_from_loadresp(valid_line) ==
             {:ok, "dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c"}

    err_line = ~s(LOADRESP 0 {"error": "Cannot load torrent", "status": 0})
    assert Protocol.parse_loadresp(err_line) == {:error, "Cannot load torrent"}
    assert Protocol.parse_infohash_from_loadresp(err_line) == :none

    status_zero_line = ~s(LOADRESP 0 {"status": 0})
    assert Protocol.parse_loadresp(status_zero_line) == {:error, "cannot_load_torrent"}

    unknown_line = ~s(LOADRESP 0 {"status": 1})
    assert Protocol.parse_loadresp(unknown_line) == :none
  end
end
