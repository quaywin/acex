defmodule AcexGateway.Channels.StoreTest do
  use ExUnit.Case, async: false
  alias AcexGateway.Channels.Store

  test "list_channels returns default benchmark channel" do
    channels = Store.list_channels()
    assert length(channels) >= 1
    assert Enum.any?(channels, fn c -> c["id"] == "big-buck-bunny" end)
  end

  test "save_channel adds new channel and persists" do
    new_ch = %{
      "id" => "stream-hd-test",
      "name" => "Stream HD Test",
      "group" => "Live TV",
      "sources" => ["test_hash_1", "test_hash_2"]
    }

    assert {:ok, saved} = Store.save_channel(new_ch)
    assert saved["id"] == "stream-hd-test"
    assert length(saved["sources"]) == 2

    assert Store.get_channel("stream-hd-test") != nil

    # Cleanup
    Store.delete_channel("stream-hd-test")
  end

  test "format_playlist_title amends country in square brackets before title" do
    assert Store.format_playlist_title("VTV3 HD", "VN") == "[VN] VTV3 HD"

    assert Store.format_playlist_title("Sky Sports Main Event", "UK") ==
             "[UK] Sky Sports Main Event"

    assert Store.format_playlist_title("Movistar LaLiga", "[ES]") == "[ES] Movistar LaLiga"
    assert Store.format_playlist_title("[VN] VTV3 HD", "VN") == "[VN] VTV3 HD"
    assert Store.format_playlist_title("General Stream", "") == "General Stream"
    assert Store.format_playlist_title("General Stream", nil) == "General Stream"
  end

  test "save_channel stores country and export_m3u amends country to title" do
    new_ch = %{
      "id" => "vtv3-hd-test",
      "name" => "VTV3 HD",
      "country" => "VN",
      "group" => "National",
      "sources" => ["vtv3_hash_1"]
    }

    assert {:ok, saved} = Store.save_channel(new_ch)
    assert saved["id"] == "vtv3-hd-test"
    assert saved["country"] == "VN"

    m3u = Store.export_m3u("http://localhost:8686")
    assert m3u =~ "tvg-id=\"vtv3-hd-test\""
    assert m3u =~ "tvg-name=\"[VN] VTV3 HD\""
    assert m3u =~ "tvg-country=\"VN\""
    assert m3u =~ ",[VN] VTV3 HD"

    # Cleanup
    Store.delete_channel("vtv3-hd-test")
  end

  test "export_m3u formats valid playlist" do
    m3u = Store.export_m3u("http://192.168.1.100:8686")
    assert String.starts_with?(m3u, "#EXTM3U")
    assert m3u =~ "http://192.168.1.100:8686/live?channel=big-buck-bunny"
  end

  test "parse_import_text correctly parses multiple formats" do
    # 1. Pipe format with country and group
    pipe_text = """
    dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c | K+ Sport 1 HD | VN | Sports
    4a32e8b7c61f55a1234567890123456789012345 | Sky Sports Main Event | UK | Football
    """

    parsed_pipe = Store.parse_import_text(pipe_text)
    assert length(parsed_pipe) == 2
    ch1 = hd(parsed_pipe)
    assert ch1["name"] == "K+ Sport 1 HD"
    assert ch1["country"] == "VN"
    assert ch1["group"] == "Sports"
    assert ch1["sources"] == ["dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c"]

    # 2. Consolidation of same channel with multiple backup sources
    multi_sources_text = """
    K+ Cine | dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c | VN | Movies
    K+ Cine | 4a32e8b7c61f55a1234567890123456789012345 | VN | Movies
    """

    parsed_multi = Store.parse_import_text(multi_sources_text)
    assert length(parsed_multi) == 1
    assert length(hd(parsed_multi)["sources"]) == 2

    # 3. M3U playlist format with #EXTINF
    m3u_text = """
    #EXTM3U
    #EXTINF:-1 tvg-id="espn-hd" tvg-name="ESPN HD" tvg-country="US" tvg-logo="https://logo.com/espn.png" group-title="Sports",ESPN HD
    acestream://1111222233334444555566667777888899990000
    """

    parsed_m3u = Store.parse_import_text(m3u_text)
    assert length(parsed_m3u) == 1
    ch_m3u = hd(parsed_m3u)
    assert ch_m3u["name"] == "ESPN HD"
    assert ch_m3u["country"] == "US"
    assert ch_m3u["logo"] == "https://logo.com/espn.png"
    assert ch_m3u["sources"] == ["1111222233334444555566667777888899990000"]
  end

  test "import_channels adds new channels and merges with existing lineup" do
    import_text = """
    Imported Test Channel | aaaaaabbbbbbccccccddddddeeeeeeffffff0000 | UK | International
    """

    assert {:ok, imported} = Store.import_channels(import_text)
    assert length(imported) == 1

    stored = Store.get_channel("imported-test-channel")
    assert stored != nil
    assert stored["country"] == "UK"

    # Clean up
    Store.delete_channel("imported-test-channel")
  end

  test "export_txt returns pipe-delimited content id list" do
    txt = Store.export_txt()
    assert is_binary(txt)
    assert txt =~ "big-buck-bunny" or txt =~ "dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c"
    assert txt =~ " | "
  end
end
