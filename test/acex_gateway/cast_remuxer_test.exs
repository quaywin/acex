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

    test "get_playlist/2 accepts optional base_url without error" do
      # On a non-existent or inactive target, returns error tuple without crashing
      res = CastRemuxer.get_playlist("non-existent-channel-prewarm", "https://example.com")
      assert match?({:error, _}, res)
    end

    test "cast_base_dir/0 respects custom environment variable" do
      default_dir = CastRemuxer.cast_base_dir()
      assert is_binary(default_dir)
      assert String.ends_with?(default_dir, "acex_cast")

      System.put_env("CAST_CACHE_DIR", "/tmp/custom_cast_test")

      try do
        assert CastRemuxer.cast_base_dir() == "/tmp/custom_cast_test"
      after
        System.delete_env("CAST_CACHE_DIR")
      end
    end
  end
end
