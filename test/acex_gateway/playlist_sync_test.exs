defmodule AcexGateway.PlaylistSyncTest do
  use ExUnit.Case, async: false

  alias AcexGateway.Sync.PlaylistSync

  describe "URL normalization" do
    test "converts GitHub blob URLs to raw URLs" do
      github_blob = "https://github.com/Icastresana/lista1/blob/main/eventos.m3u"
      expected = "https://raw.githubusercontent.com/Icastresana/lista1/main/eventos.m3u"
      assert PlaylistSync.normalize_github_url(github_blob) == expected

      channels_blob = "https://github.com/Icastresana/lista1/blob/main/Probando"
      expected_ch = "https://raw.githubusercontent.com/Icastresana/lista1/main/Probando"
      assert PlaylistSync.normalize_github_url(channels_blob) == expected_ch
    end

    test "leaves raw URLs and regular URLs unchanged" do
      raw_url = "https://raw.githubusercontent.com/user/repo/main/playlist.m3u"
      assert PlaylistSync.normalize_github_url(raw_url) == raw_url

      other_url = "https://example.com/stream.m3u8"
      assert PlaylistSync.normalize_github_url(other_url) == other_url
    end
  end

  describe "Events parser" do
    test "parses eventos.m3u structure and consolidates multi-sources" do
      sample_m3u = """
      #EXTM3U
      #EXTINF:-1 tvg-logo="https://i.ibb.co/2vhFM7h/soccer-ball-variant.png", 19:00 Real Madrid vs Barcelona
      acestream://1111111111111111111111111111111111111111
      #EXTINF:-1 tvg-logo="https://i.ibb.co/2vhFM7h/soccer-ball-variant.png", 19:00 Real Madrid vs Barcelona
      acestream://2222222222222222222222222222222222222222
      #EXTINF:-1 tvg-logo="https://i.ibb.co/Yjyrpmh/ball.png", 14:00 Djokovic vs Nadal
      acestream://3333333333333333333333333333333333333333
      """

      parsed = PlaylistSync.parse_events_m3u(sample_m3u)
      assert length(parsed) == 2

      match1 = Enum.find(parsed, &(&1["name"] == "19:00 Real Madrid vs Barcelona"))
      assert match1 != nil
      assert match1["group"] == "Live Football"
      assert match1["sources"] == [
        "1111111111111111111111111111111111111111",
        "2222222222222222222222222222222222222222"
      ]

      match2 = Enum.find(parsed, &(&1["name"] == "14:00 Djokovic vs Nadal"))
      assert match2 != nil
      assert match2["group"] == "Live Tennis"
      assert match2["sources"] == ["3333333333333333333333333333333333333333"]
    end
  end

  describe "Sync status" do
    test "returns sync status structure" do
      status = PlaylistSync.get_status()
      assert is_map(status)
      assert Map.has_key?(status, :events)
      assert Map.has_key?(status, :channels)
      assert is_integer(status.events.count)
      assert is_integer(status.channels.count)
    end
  end
end
