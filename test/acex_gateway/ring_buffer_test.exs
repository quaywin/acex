defmodule AcexGateway.Stream.RingBufferTest do
  use ExUnit.Case, async: true
  alias AcexGateway.Stream.RingBuffer

  test "stores chunks up to max_bytes" do
    buf = RingBuffer.new(10)
    # 5 bytes
    buf = RingBuffer.push(buf, "hello")
    # 5 bytes (total 10)
    buf = RingBuffer.push(buf, "world")

    assert RingBuffer.to_chunks(buf) == ["hello", "world"]
    assert buf.total_bytes == 10

    # Exceeding capacity drops oldest
    # 3 bytes (total 13 -> drops "hello", total 8)
    buf = RingBuffer.push(buf, "123")
    assert RingBuffer.to_chunks(buf) == ["world", "123"]
    assert buf.total_bytes == 8
  end

  test "clear resets queue and byte count" do
    buf = RingBuffer.new(10)
    buf = RingBuffer.push(buf, "12345")
    buf = RingBuffer.clear(buf)

    assert RingBuffer.to_chunks(buf) == []
    assert buf.total_bytes == 0
  end
end
