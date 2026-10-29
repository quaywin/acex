defmodule AcexGateway.SettingsTest do
  use ExUnit.Case, async: false

  alias AcexGateway.Settings.Store, as: SettingsStore
  alias AcexGateway.Config

  @test_settings_file "tmp/test_settings.json"

  setup do
    # Reset settings to clean state before each test
    SettingsStore.update_settings(%{
      "auth_enabled" => false,
      "auth_username" => "admin",
      "auth_password" => "acex123",
      "epg_url" => ""
    })

    on_exit(fn ->
      SettingsStore.update_settings(%{
        "auth_enabled" => false,
        "auth_username" => "admin",
        "auth_password" => "acex123",
        "epg_url" => ""
      })
    end)

    :ok
  end

  test "initializes with defaults and writes to disk" do
    assert File.exists?(@test_settings_file)
    settings = SettingsStore.get_all_settings()

    assert is_boolean(settings.auth_enabled)
    assert is_binary(settings.auth_username)
    assert is_binary(settings.auth_password)
    assert is_binary(settings.epg_url)
  end

  test "updates settings via GenServer and reflects in ETS immediately" do
    payload = %{
      "auth_enabled" => true,
      "auth_username" => "admin_tester",
      "auth_password" => "super_secret_999",
      "epg_url" => "https://epg.example.com/guide.xml"
    }

    assert {:ok, updated} = SettingsStore.update_settings(payload)
    assert updated.auth_enabled == true
    assert updated.auth_username == "admin_tester"
    assert updated.auth_password == "super_secret_999"
    assert updated.epg_url == "https://epg.example.com/guide.xml"

    # Fast ETS check
    assert SettingsStore.get_setting(:auth_enabled) == true
    assert SettingsStore.get_setting("auth_username") == "admin_tester"
    assert SettingsStore.get_setting(:auth_password) == "super_secret_999"
    assert SettingsStore.get_setting(:epg_url) == "https://epg.example.com/guide.xml"

    # Config helper check
    assert Config.auth_enabled?() == true
    assert Config.auth_username() == "admin_tester"
    assert Config.auth_password() == "super_secret_999"
    assert Config.epg_url() == "https://epg.example.com/guide.xml"
    assert Config.authenticate?("admin_tester", "super_secret_999") == true
    assert Config.authenticate?("wrong_user", "super_secret_999") == false

    # File persistence check
    assert {:ok, content} = File.read(@test_settings_file)
    decoded = Jason.decode!(content)
    assert decoded["auth_enabled"] == true
    assert decoded["auth_username"] == "admin_tester"
  end

  test "disabling auth allows any credentials" do
    payload = %{
      "auth_enabled" => false,
      "auth_username" => "admin",
      "auth_password" => "acex123"
    }

    assert {:ok, _} = SettingsStore.update_settings(payload)
    assert Config.auth_enabled?() == false
    assert Config.authenticate?("any_user", "any_pass") == true
  end

  test "max_active_channels can be dynamically configured and read via Config" do
    assert Config.max_active_channels() == 5

    assert {:ok, updated} = SettingsStore.update_settings(%{"max_active_channels" => 3})
    assert updated.max_active_channels == 3
    assert Config.max_active_channels() == 3

    assert {:ok, _} = SettingsStore.update_settings(%{"max_active_channels" => 5})
    assert Config.max_active_channels() == 5
  end

  test "xtream_format can be dynamically configured and read via Config" do
    assert Config.xtream_format() == "hls"

    assert {:ok, updated} = SettingsStore.update_settings(%{"xtream_format" => "ts"})
    assert updated.xtream_format == "ts"
    assert Config.xtream_format() == "ts"

    assert {:ok, updated2} = SettingsStore.update_settings(%{"xtream_format" => "hls"})
    assert updated2.xtream_format == "hls"
    assert Config.xtream_format() == "hls"
  end
end
