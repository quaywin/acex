defmodule AcexGateway.Settings.Store do
  @moduledoc """
  GenServer and ETS-backed store for dynamic runtime settings (e.g. Xtream Codes credentials, EPG URL).
  Provides sub-microsecond, lock-free lookups via ETS table `:acex_settings_cache`
  while persisting updates to a JSON file (`data/settings.json`).
  """

  use GenServer
  require Logger

  @table :acex_settings_cache
  @default_file "data/settings.json"

  # Client API

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Gets a single setting value by atom or string key directly from ETS.
  Lock-free and sub-microsecond latency.
  """
  def get_setting(key, default \\ nil) when is_atom(key) or is_binary(key) do
    key_atom = to_atom(key)

    case :ets.lookup(@table, key_atom) do
      [{^key_atom, value}] -> value
      [] -> default
    end
  rescue
    _ -> default
  end

  @doc """
  Returns all settings as a map.
  """
  def get_all_settings do
    case :ets.lookup(@table, :all_settings) do
      [{:all_settings, settings}] -> settings
      [] -> GenServer.call(__MODULE__, :get_all_settings)
    end
  rescue
    _ ->
      GenServer.call(__MODULE__, :get_all_settings)
  end

  @doc """
  Updates settings in memory (ETS) and persists them to the JSON settings file.
  """
  def update_settings(params) when is_map(params) do
    GenServer.call(__MODULE__, {:update_settings, params})
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    file_path =
      Keyword.get(
        opts,
        :file_path,
        Application.get_env(:acex_gateway, :settings_file) ||
          System.get_env("SETTINGS_FILE", @default_file)
      )

    # Initialize ETS table if not already created
    if :ets.info(@table) == :undefined do
      :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    end

    settings = load_settings(file_path)
    sync_to_ets(settings)

    {:ok, %{file_path: file_path, settings: settings}}
  end

  @impl true
  def handle_call(:get_all_settings, _from, state) do
    {:reply, state.settings, state}
  end

  def handle_call({:update_settings, params}, _from, state) do
    current = state.settings

    updated = %{
      auth_enabled:
        case Map.get(params, "auth_enabled", Map.get(params, :auth_enabled)) do
          val when is_boolean(val) -> val
          "true" -> true
          "false" -> false
          _ -> current.auth_enabled
        end,
      auth_username:
        normalize_string(
          Map.get(params, "auth_username", Map.get(params, :auth_username)),
          current.auth_username
        ),
      auth_password:
        normalize_string(
          Map.get(params, "auth_password", Map.get(params, :auth_password)),
          current.auth_password
        ),
      epg_url:
        normalize_string(
          Map.get(params, "epg_url", Map.get(params, :epg_url)),
          current.epg_url
        ),
      max_active_channels:
        case Map.get(params, "max_active_channels", Map.get(params, :max_active_channels)) do
          val when is_integer(val) and val > 0 ->
            val

          val when is_binary(val) ->
            case Integer.parse(val) do
              {num, ""} when num > 0 -> num
              _ -> Map.get(current, :max_active_channels, 5)
            end

          _ ->
            Map.get(current, :max_active_channels, 5)
        end
    }

    sync_to_ets(updated)
    persist_settings(state.file_path, updated)

    Logger.info(
      "[Settings] Updated settings: auth_enabled=#{updated.auth_enabled}, auth_username=#{updated.auth_username}"
    )

    {:reply, {:ok, updated}, %{state | settings: updated}}
  end

  # Private Helpers

  defp load_settings(file_path) do
    if File.exists?(file_path) do
      case File.read(file_path) do
        {:ok, content} ->
          case Jason.decode(content) do
            {:ok, json} when is_map(json) ->
              parse_stored_settings(json)

            _ ->
              build_default_settings()
          end

        _ ->
          build_default_settings()
      end
    else
      defaults = build_default_settings()
      persist_settings(file_path, defaults)
      defaults
    end
  end

  defp build_default_settings do
    env_user = System.get_env("AUTH_USERNAME") || ""
    env_pass = System.get_env("AUTH_PASSWORD") || ""
    env_epg = System.get_env("EPG_URL") || ""

    has_env_creds =
      is_binary(env_user) and is_binary(env_pass) and String.trim(env_user) != "" and
        String.trim(env_pass) != ""

    default_max =
      case System.get_env("MAX_ACTIVE_CHANNELS") do
        nil ->
          5

        str ->
          case Integer.parse(str) do
            {n, ""} when n > 0 -> n
            _ -> 5
          end
      end

    %{
      auth_enabled: has_env_creds,
      auth_username: if(String.trim(env_user) != "", do: String.trim(env_user), else: "admin"),
      auth_password: if(String.trim(env_pass) != "", do: String.trim(env_pass), else: "acex123"),
      epg_url: String.trim(env_epg),
      max_active_channels: default_max
    }
  end

  defp parse_stored_settings(json) do
    defaults = build_default_settings()

    %{
      auth_enabled: Map.get(json, "auth_enabled", defaults.auth_enabled),
      auth_username: Map.get(json, "auth_username", defaults.auth_username),
      auth_password: Map.get(json, "auth_password", defaults.auth_password),
      epg_url: Map.get(json, "epg_url", defaults.epg_url),
      max_active_channels: Map.get(json, "max_active_channels", defaults.max_active_channels)
    }
  end

  defp sync_to_ets(settings) do
    :ets.insert(@table, {:all_settings, settings})
    :ets.insert(@table, {:auth_enabled, settings.auth_enabled})
    :ets.insert(@table, {:auth_username, settings.auth_username})
    :ets.insert(@table, {:auth_password, settings.auth_password})
    :ets.insert(@table, {:epg_url, settings.epg_url})
    :ets.insert(@table, {:max_active_channels, settings.max_active_channels})
  end

  defp persist_settings(file_path, settings) do
    dir = Path.dirname(file_path)
    File.mkdir_p(dir)

    json_str =
      Jason.encode!(
        %{
          "auth_enabled" => settings.auth_enabled,
          "auth_username" => settings.auth_username,
          "auth_password" => settings.auth_password,
          "epg_url" => settings.epg_url,
          "max_active_channels" => settings.max_active_channels
        },
        pretty: true
      )

    tmp_file = "#{file_path}.tmp.#{:erlang.unique_integer([:positive])}"

    with :ok <- File.write(tmp_file, json_str),
         :ok <- File.rename(tmp_file, file_path) do
      :ok
    else
      err ->
        Logger.error("[Settings] Failed to persist settings to #{file_path}: #{inspect(err)}")
        File.rm(tmp_file)
        :error
    end
  end

  defp normalize_string(nil, fallback), do: fallback

  defp normalize_string(val, _fallback) when is_binary(val) do
    String.trim(val)
  end

  defp normalize_string(val, fallback) do
    to_string(val) |> String.trim()
  rescue
    _ -> fallback
  end

  defp to_atom(k) when is_atom(k), do: k

  defp to_atom(k) when is_binary(k) do
    case k do
      "auth_enabled" -> :auth_enabled
      "auth_username" -> :auth_username
      "auth_password" -> :auth_password
      "epg_url" -> :epg_url
      _ -> String.to_atom(k)
    end
  end
end
