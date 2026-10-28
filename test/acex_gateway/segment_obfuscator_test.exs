defmodule AcexGateway.Stream.SegmentObfuscatorTest do
  use ExUnit.Case, async: true
  alias AcexGateway.Stream.SegmentObfuscator

  describe "SegmentObfuscator" do
    test "round-trip obfuscation and deobfuscation" do
      original = "seg_1740000000_00042.ts"
      obfuscated = SegmentObfuscator.obfuscate(original)

      assert obfuscated != original
      assert not String.ends_with?(obfuscated, ".ts")
      assert not String.contains?(obfuscated, "00042")

      deobfuscated = SegmentObfuscator.deobfuscate(obfuscated)
      assert deobfuscated == original
    end

    test "is deterministic for the same segment" do
      seg = "seg_1712345678_00001.ts"
      assert SegmentObfuscator.obfuscate(seg) == SegmentObfuscator.obfuscate(seg)
    end

    test "handles sequence numbers up to 99999" do
      for seq <- [0, 1, 100, 1500, 99999] do
        seq_str = String.pad_leading(to_string(seq), 5, "0")
        original = "seg_1741234567_#{seq_str}.ts"
        obfuscated = SegmentObfuscator.obfuscate(original)
        assert SegmentObfuscator.deobfuscate(obfuscated) == original
      end
    end

    test "non-matching names pass through untouched" do
      assert SegmentObfuscator.obfuscate("other.mp4") == "other.mp4"
      assert SegmentObfuscator.deobfuscate("seg_1712345678_00001.ts") == "seg_1712345678_00001.ts"
    end

    test "obfuscate_manifest/1 transforms all .ts lines in m3u8" do
      raw_manifest = """
      #EXTM3U
      #EXT-X-VERSION:3
      #EXT-X-TARGETDURATION:3
      #EXTINF:3.000,
      /cast/premier-sports-1/seg_1741234567_00001.ts
      #EXTINF:3.000,
      /cast/premier-sports-1/seg_1741234567_00002.ts
      """

      obfuscated = SegmentObfuscator.obfuscate_manifest(raw_manifest)

      assert not String.contains?(obfuscated, ".ts")
      assert String.contains?(obfuscated, "#EXTM3U")
      assert String.contains?(obfuscated, "#EXTINF:3.000,")

      lines =
        obfuscated
        |> String.split("\n", trim: true)
        |> Enum.reject(&String.starts_with?(&1, "#"))

      assert length(lines) == 2

      Enum.each(lines, fn line ->
        base = Path.basename(line)
        assert SegmentObfuscator.deobfuscate(base) =~ ~r/^seg_1741234567_0000\d\.ts$/
      end)
    end

    test "obfuscate_manifest/2 with cdn_url produces absolute CDN URLs" do
      raw_manifest = """
      #EXTM3U
      #EXT-X-VERSION:3
      #EXT-X-TARGETDURATION:3
      #EXTINF:3.000,
      /cast/premier-sports-1/seg_1741234567_00001.ts
      #EXTINF:3.000,
      /cast/premier-sports-1/seg_1741234567_00002.ts
      """

      obfuscated =
        SegmentObfuscator.obfuscate_manifest(raw_manifest, "https://media.phu88.xyz/")

      lines =
        obfuscated
        |> String.split("\n", trim: true)
        |> Enum.reject(&String.starts_with?(&1, "#"))

      assert length(lines) == 2

      Enum.each(lines, fn line ->
        assert String.starts_with?(line, "https://media.phu88.xyz/cast/premier-sports-1/")
        assert not String.ends_with?(line, ".ts")
        base = Path.basename(line)
        assert SegmentObfuscator.deobfuscate(base) =~ ~r/^seg_1741234567_0000\d\.ts$/
      end)
    end

    test "content_type_for/1 maps image extensions to realistic image MIME types" do
      assert SegmentObfuscator.content_type_for("photo_123.jpg") == "image/jpeg"
      assert SegmentObfuscator.content_type_for("photo_123.jpeg") == "image/jpeg"
      assert SegmentObfuscator.content_type_for("avatar_123.webp") == "image/webp"
      assert SegmentObfuscator.content_type_for("thumb_123.png") == "image/png"
      assert SegmentObfuscator.content_type_for("asset_123.avif") == "image/avif"
      assert SegmentObfuscator.content_type_for("unknown.bin") == "application/octet-stream"
    end
  end
end
