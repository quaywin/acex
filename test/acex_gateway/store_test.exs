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
    assert m3u =~ "tvg-chno=\"1\""
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

    # 3. M3U playlist format with multiple streams under one #EXTINF
    m3u_text = """
    #EXTM3U
    #EXTINF:-1 tvg-id="espn-hd" tvg-name="ESPN HD" tvg-country="US" tvg-logo="https://logo.com/espn.png" group-title="Sports",ESPN HD
    acestream://1111222233334444555566667777888899990000
    acestream://2222333344445555666677778888999900001111
    """

    parsed_m3u = Store.parse_import_text(m3u_text)
    assert length(parsed_m3u) == 1
    ch_m3u = hd(parsed_m3u)
    assert ch_m3u["name"] == "ESPN HD"
    assert ch_m3u["country"] == "US"
    assert ch_m3u["logo"] == "https://logo.com/espn.png"
    assert length(ch_m3u["sources"]) == 2
    assert "1111222233334444555566667777888899990000" in ch_m3u["sources"]
    assert "2222333344445555666677778888999900001111" in ch_m3u["sources"]

    # 4. Multiple Content IDs on the SAME line separated by comma or space
    single_line_multi_hashes = """
    1111222233334444555566667777888899990000, 2222333344445555666677778888999900001111 | Multi Source Line | VN | Sports
    """

    parsed_single_line = Store.parse_import_text(single_line_multi_hashes)
    assert length(parsed_single_line) == 1
    ch_single = hd(parsed_single_line)
    assert ch_single["name"] == "Multi Source Line"
    assert length(ch_single["sources"]) == 2
    assert "1111222233334444555566667777888899990000" in ch_single["sources"]
    assert "2222333344445555666677778888999900001111" in ch_single["sources"]
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

  test "normalize_channel_param handles string with comma or newline separated hashes" do
    param = %{
      "name" => "K+ Sport 1",
      "sources" =>
        "1111222233334444555566667777888899990000, 2222333344445555666677778888999900001111"
    }

    normalized = Store.normalize_channel_param(param)
    assert length(normalized["sources"]) == 2
    assert "1111222233334444555566667777888899990000" in normalized["sources"]
    assert "2222333344445555666677778888999900001111" in normalized["sources"]
  end

  test "find_channel_by_source returns channel for indexed source hash via ETS" do
    channel = Store.find_channel_by_source("dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c")
    assert channel != nil
    assert channel["id"] == "big-buck-bunny"

    # Direct lookup with capital letters or extra spaces
    channel_caps = Store.find_channel_by_source("  DD8255ECDC7CA55FB0BBF81323D87062DB1F6D1C  ")
    assert channel_caps != nil
    assert channel_caps["id"] == "big-buck-bunny"

    assert Store.find_channel_by_source("non_existent_hash_000000000000000000000") == nil
  end

  test "export_txt returns pipe-delimited content id list" do
    txt = Store.export_txt()
    assert is_binary(txt)
    assert txt =~ "big-buck-bunny" or txt =~ "dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c"
    assert txt =~ " | "
  end

  test "promote_channel_source reorders sources putting working backup at index 0" do
    ch = %{
      "id" => "promo-test-ch",
      "name" => "Promo Test Channel",
      "sources" => ["backup_hash_1", "backup_hash_2", "backup_hash_3"]
    }

    assert {:ok, _} = Store.save_channel(ch)

    # Calling promote on index 0 is a no-op
    assert :noop = Store.promote_channel_source("promo-test-ch", "backup_hash_1")

    # Calling promote on backup_hash_3 moves it to index 0
    assert {:ok, updated} = Store.promote_channel_source("promo-test-ch", "backup_hash_3")
    assert hd(updated["sources"]) == "backup_hash_3"
    assert updated["sources"] == ["backup_hash_3", "backup_hash_1", "backup_hash_2"]

    # Verify ETS was updated
    stored = Store.get_channel("promo-test-ch")
    assert stored["sources"] == ["backup_hash_3", "backup_hash_1", "backup_hash_2"]

    # Cleanup
    Store.delete_channel("promo-test-ch")
  end

  test "remove_channel_source removes source but protects last remaining source" do
    ch = %{
      "id" => "prune-test-ch",
      "name" => "Prune Test Channel",
      "sources" => ["hash_a", "hash_b"]
    }

    assert {:ok, _} = Store.save_channel(ch)

    # Removing hash_a leaves hash_b
    assert {:ok, updated} = Store.remove_channel_source("prune-test-ch", "hash_a")
    assert updated["sources"] == ["hash_b"]

    # Trying to remove the last source (hash_b) is rejected
    assert {:error, :cannot_remove_last_source} =
             Store.remove_channel_source("prune-test-ch", "hash_b")

    # Verify channel still has hash_b in ETS
    stored = Store.get_channel("prune-test-ch")
    assert stored["sources"] == ["hash_b"]

    # Cleanup
    Store.delete_channel("prune-test-ch")
  end

  test "prune_dead_source removes dead source from multi-source channel" do
    ch = %{
      "id" => "auto-prune-ch",
      "name" => "Auto Prune Channel",
      "sources" => ["alive_hash_1", "dead_hash_2", "alive_hash_3"]
    }

    assert {:ok, _} = Store.save_channel(ch)

    # Pruning dead_hash_2 removes it
    assert {:ok, updated} = Store.prune_dead_source("auto-prune-ch", "dead_hash_2")
    assert updated["sources"] == ["alive_hash_1", "alive_hash_3"]

    # Pruning non-existent source returns :noop
    assert :noop = Store.prune_dead_source("auto-prune-ch", "non_existent_hash")

    # Pruning on a single-source channel returns :noop
    single_ch = %{
      "id" => "single-src-ch",
      "name" => "Single Source Channel",
      "sources" => ["only_one_hash"]
    }

    Store.save_channel(single_ch)
    assert :noop = Store.prune_dead_source("single-src-ch", "only_one_hash")

    # Cleanup
    Store.delete_channel("auto-prune-ch")
    Store.delete_channel("single-src-ch")
  end

  test "list_groups returns groups with channel_count" do
    groups = Store.list_groups()
    assert is_list(groups)
    assert length(groups) >= 1
    assert Enum.any?(groups, fn g -> g["name"] == "General" end)

    general = Enum.find(groups, fn g -> g["name"] == "General" end)
    assert Map.has_key?(general, "channel_count")
    assert is_integer(general["channel_count"])
  end

  test "get_group returns single group with channel_count and nil for unknown" do
    general = Store.get_group("general")
    assert general != nil
    assert general["name"] == "General"
    assert is_integer(general["channel_count"])

    assert Store.get_group("non_existent_group_xyz") == nil
    assert Store.get_group(nil) == nil
    assert Store.get_group(123) == nil
  end

  test "create_group creates group and prevents duplicates" do
    assert {:ok, group} = Store.create_group("Test New Category")
    assert group["name"] == "Test New Category"
    assert group["id"] == "test-new-category"

    # Duplicates rejected case-insensitively
    assert {:error, :already_exists} = Store.create_group("test new category")
    assert {:error, :already_exists} = Store.create_group("TEST NEW CATEGORY")

    # Empty name rejected
    assert {:error, :invalid_name} = Store.create_group("   ")

    # Cleanup
    Store.delete_group(group["id"])
  end

  test "rename_group cascades new name to all matching channels" do
    assert {:ok, group} = Store.create_group("Original Group")

    ch1 = %{
      "id" => "cascade-ch-1",
      "name" => "Cascade 1",
      "group" => "Original Group",
      "sources" => ["hash_casc_1"]
    }

    ch2 = %{
      "id" => "cascade-ch-2",
      "name" => "Cascade 2",
      "group" => "Original Group",
      "sources" => ["hash_casc_2"]
    }

    Store.save_channel(ch1)
    Store.save_channel(ch2)

    assert {:ok, updated_group} = Store.rename_group(group["id"], "Renamed Group")
    assert updated_group["name"] == "Renamed Group"

    assert Store.get_channel("cascade-ch-1")["group"] == "Renamed Group"
    assert Store.get_channel("cascade-ch-2")["group"] == "Renamed Group"

    # Cleanup
    Store.delete_channel("cascade-ch-1")
    Store.delete_channel("cascade-ch-2")
    Store.delete_group(group["id"])
  end

  test "delete_group reassigns orphan channels to fallback group" do
    assert {:ok, group} = Store.create_group("Doomed Group")

    ch = %{
      "id" => "orphan-ch",
      "name" => "Orphan Channel",
      "group" => "Doomed Group",
      "sources" => ["orphan_hash"]
    }

    Store.save_channel(ch)

    assert {:ok, res} = Store.delete_group(group["id"], "General")
    assert res.deleted == group["id"]
    assert res.reassigned_to == "General"

    assert Store.get_channel("orphan-ch")["group"] == "General"

    # Cleanup
    Store.delete_channel("orphan-ch")
  end

  test "move_channels_group moves multiple channels and auto-creates group if needed" do
    ch1 = %{
      "id" => "move-ch-1",
      "name" => "Move 1",
      "group" => "General",
      "sources" => ["hash_m1"]
    }

    ch2 = %{
      "id" => "move-ch-2",
      "name" => "Move 2",
      "group" => "General",
      "sources" => ["hash_m2"]
    }

    Store.save_channel(ch1)
    Store.save_channel(ch2)

    assert {:ok, res} =
             Store.move_channels_group(["move-ch-1", "move-ch-2"], "New Transferred Group")

    assert res.moved_count == 2
    assert res.target_group == "New Transferred Group"

    assert Store.get_channel("move-ch-1")["group"] == "New Transferred Group"
    assert Store.get_channel("move-ch-2")["group"] == "New Transferred Group"

    # Verify group was added to Store.list_groups()
    groups = Store.list_groups()
    assert Enum.any?(groups, fn g -> g["name"] == "New Transferred Group" end)

    # Test set_channel_group for a single channel
    assert {:ok, _} = Store.set_channel_group("move-ch-1", "Solo Group")
    assert Store.get_channel("move-ch-1")["group"] == "Solo Group"

    # Cleanup
    Store.delete_channel("move-ch-1")
    Store.delete_channel("move-ch-2")
  end
end
