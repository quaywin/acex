defmodule AcexGateway.Stream.CastRemuxerTest do
  use ExUnit.Case, async: false
  alias AcexGateway.Stream.CastRemuxer

  describe "CastRemuxer unit tests" do
    test "ffmpeg_available?/0 returns boolean" do
      assert is_boolean(CastRemuxer.ffmpeg_available?())
    end

    test "running?/1 returns false for non-existent target" do
      assert CastRemuxer.running?("non-existent-channel-123") == false
    end

    test "get_segment/2 returns error :not_running for inactive target" do
      assert CastRemuxer.get_segment("inactive-ch", "seg_000.ts") == {:error, :not_running}
    end

    test "stop_remuxer/1 does not crash on non-existent target" do
      assert CastRemuxer.stop_remuxer("non-existent-channel-xyz") == :ok
    end
  end
end
