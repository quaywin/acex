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
  end
end
