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

      assert CastRemuxer.get_segment("inactive-ch", "avatar_mock123.webp") ==
               {:error, :not_running}
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

    test "build_manifest_string/4 correctly formats standard HLS manifest" do
      segments = [
        {"seg_1700000000_00001.ts", 3.003333},
        {"seg_1700000000_00002.ts", 2.996667}
      ]

      manifest = CastRemuxer.build_manifest_string("my_stream", 4, 1, segments)

      assert String.starts_with?(manifest, "#EXTM3U\n")
      assert String.contains?(manifest, "#EXT-X-TARGETDURATION:4")
      assert String.contains?(manifest, "#EXT-X-MEDIA-SEQUENCE:1")
      assert String.contains?(manifest, "#EXTINF:3.003333,")
      assert String.contains?(manifest, "/cast/my_stream/seg_1700000000_00001.ts")
      assert String.contains?(manifest, "#EXTINF:2.996667,")
      assert String.contains?(manifest, "/cast/my_stream/seg_1700000000_00002.ts")
    end

    test "parse_manifest_data/3 extracts segments and metadata accurately" do
      content = """
      #EXTM3U
      #EXT-X-VERSION:3
      #EXT-X-TARGETDURATION:5
      #EXT-X-MEDIA-SEQUENCE:42
      #EXT-X-INDEPENDENT-SEGMENTS
      #EXTINF:3.012000,
      /cast/test_target/seg_1700000000_00042.ts
      #EXTINF:2.988000,
      /cast/test_target/seg_1700000000_00043.ts
      """

      parsed = CastRemuxer.parse_manifest_data("test_target", content, "/tmp/dummy")

      assert parsed.target == "test_target"
      assert parsed.target_duration == 5
      assert parsed.media_sequence == 42
      assert length(parsed.segments) == 2

      assert parsed.segments == [
               {"seg_1700000000_00042.ts", 3.012},
               {"seg_1700000000_00043.ts", 2.988}
             ]
    end

    test "build_dynamic_manifest_from_disk/2 aggregates finished segments into manifest" do
      test_dir = Path.join(System.tmp_dir!(), "cast_test_segments_#{System.unique_integer([:positive])}")
      File.mkdir_p!(test_dir)

      try do
        # Create mock segment files with increasing sequences
        File.write!(Path.join(test_dir, "seg_1700000000_00001.ts"), "segment_1_data")
        File.write!(Path.join(test_dir, "seg_1700000000_00002.ts"), "segment_2_data")
        File.write!(Path.join(test_dir, "seg_1700000000_00003.ts"), "active_unflushed_data")

        # Excludes actively recording last segment, keeps 1 and 2
        assert {:ok, dynamic_data} = CastRemuxer.build_dynamic_manifest_from_disk("disk_stream", test_dir)
        assert dynamic_data.media_sequence == 1
        assert length(dynamic_data.segments) == 2
        assert String.contains?(dynamic_data.manifest, "seg_1700000000_00001.ts")
        assert String.contains?(dynamic_data.manifest, "seg_1700000000_00002.ts")
        refute String.contains?(dynamic_data.manifest, "seg_1700000000_00003.ts")
      after
        File.rm_rf(test_dir)
      end
    end

    test "sync_manifest/2 caches in ETS and serves valid manifest on mid-flush empty reads" do
      test_dir = Path.join(System.tmp_dir!(), "cast_test_sync_#{System.unique_integer([:positive])}")
      File.mkdir_p!(test_dir)
      m3u8_file = Path.join(test_dir, "live.m3u8")

      target = "sync_race_test_stream"

      try do
        # 1. First sync with valid disk manifest
        initial_m3u8 = """
        #EXTM3U
        #EXT-X-VERSION:3
        #EXT-X-TARGETDURATION:4
        #EXT-X-MEDIA-SEQUENCE:10
        #EXTINF:3.000000,
        /cast/#{target}/seg_1700000000_00010.ts
        """
        File.write!(m3u8_file, initial_m3u8)

        assert {:ok, manifest1} = CastRemuxer.sync_manifest(target, test_dir)
        assert String.contains?(manifest1, "seg_1700000000_00010.ts")

        # Check ETS cache
        assert {:ok, %{media_sequence: 10}} = CastRemuxer.lookup_manifest(target)
        assert CastRemuxer.get_active_segments(target) == ["seg_1700000000_00010.ts"]

        # 2. Simulate FFmpeg mid-write file truncation (empty 0-byte file)
        File.write!(m3u8_file, "")

        # sync_manifest must NOT fail or return empty; it serves cached ETS manifest
        assert {:ok, fallback_manifest} = CastRemuxer.sync_manifest(target, test_dir)
        assert String.contains?(fallback_manifest, "seg_1700000000_00010.ts")
      after
        File.rm_rf(test_dir)
      end
    end
  end
end
