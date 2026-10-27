defmodule AcexGateway.System.Updater do
  @moduledoc """
  Manages system version inspection, GitHub release checking with ETS caching,
  and 1-click update triggers via Watchtower internal HTTP API or local scripts.
  """

  require Logger

  @cache_table :acex_updater_cache
  @cache_ttl_seconds 1800
  @default_repo "quaywin/acex"

  @doc """
  Ensures the ETS cache table exists.
  """
  def ensure_cache do
    if :ets.whereis(@cache_table) == :undefined do
      try do
        :ets.new(@cache_table, [:named_table, :public, :set, read_concurrency: true])
      rescue
        _ -> :ok
      end
    end

    :ok
  end

  @doc """
  Checks for newer releases on GitHub.
  Uses ETS cache with a 30-minute TTL unless `force: true` is passed.
  """
  def check_update(opts \\ []) do
    ensure_cache()
    force = Keyword.get(opts, :force, false)
    now = System.monotonic_time(:second)

    if not force do
      case :ets.lookup(@cache_table, :latest_release) do
        [{:latest_release, cached_info, expires_at}] when expires_at > now ->
          cached_info

        _ ->
          fetch_and_cache_release()
      end
    else
      fetch_and_cache_release()
    end
  end

  @doc """
  Triggers the system update process based on the detected environment.
  """
  def trigger_update do
    method = detect_update_method()

    case method do
      :watchtower ->
        trigger_watchtower()

      :script ->
        trigger_script()

      _ ->
        {:ok,
         %{
           status: "manual_required",
           method: "manual",
           message: "Please run the following command on your server terminal:",
           command: "docker compose pull && docker compose up -d"
         }}
    end
  end

  @doc """
  Detects the primary update mechanism available in the current environment.
  """
  def detect_update_method do
    cond do
      System.get_env("WATCHTOWER_ENDPOINT") != nil or
        System.get_env("WATCHTOWER_HTTP_API_TOKEN") != nil or
          System.get_env("WATCHTOWER_TOKEN") != nil ->
        :watchtower

      # In standard docker-compose, watchtower is accessible via DNS
      in_docker?() ->
        :watchtower

      has_executable_script?() ->
        :script

      true ->
        :manual
    end
  end

  # --- Internal Helpers ---

  defp in_docker? do
    File.exists?("/.dockerenv") or System.get_env("DOCKER_CONTAINER") == "true"
  end

  defp has_executable_script? do
    File.exists?("update.sh") or File.exists?("/app/data/update.sh")
  end

  defp fetch_and_cache_release do
    current_ver = AcexGateway.version() |> normalize_version()
    repo = System.get_env("GITHUB_REPO") || @default_repo
    url = "https://api.github.com/repos/#{repo}/releases/latest"

    headers = [
      {"user-agent", "AcexGateway-Updater/#{AcexGateway.version()}"},
      {"accept", "application/vnd.github.v3+json"}
    ]

    method = detect_update_method()

    case Req.get(url, headers: headers, receive_timeout: 5000, retry: false) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        tag_name = body["tag_name"] || ""
        latest_ver = normalize_version(tag_name)
        has_update = compare_versions(latest_ver, current_ver)

        info = %{
          current_version: current_ver,
          latest_version: latest_ver,
          has_update: has_update,
          release_name: body["name"] || tag_name,
          release_url: body["html_url"] || "https://github.com/#{repo}/releases",
          release_notes: body["body"] || "",
          published_at: body["published_at"],
          update_method: to_string(method),
          checked_at: System.system_time(:second)
        }

        expires_at = System.monotonic_time(:second) + @cache_ttl_seconds
        :ets.insert(@cache_table, {:latest_release, info, expires_at})
        info

      {:ok, %{status: status}} ->
        Logger.warning("[Updater] GitHub API returned HTTP #{status}")
        fallback_info(current_ver, method, "GitHub API returned HTTP #{status}")

      {:error, reason} ->
        Logger.warning("[Updater] Failed to check GitHub updates: #{inspect(reason)}")
        fallback_info(current_ver, method, "Network or timeout error checking updates")
    end
  end

  defp fallback_info(current_ver, method, error_msg) do
    repo = System.get_env("GITHUB_REPO") || @default_repo

    %{
      current_version: current_ver,
      latest_version: current_ver,
      has_update: false,
      release_name: "v" <> current_ver,
      release_url: "https://github.com/#{repo}/releases",
      release_notes: "Unable to load release notes from GitHub (#{error_msg}).",
      published_at: nil,
      update_method: to_string(method),
      checked_at: System.system_time(:second),
      error: error_msg
    }
  end

  defp normalize_version(nil), do: "0.1.0"

  defp normalize_version(v) when is_binary(v) do
    v
    |> String.trim()
    |> String.trim_leading("v")
  end

  defp compare_versions(latest, current) do
    case {Version.parse(latest), Version.parse(current)} do
      {{:ok, latest_v}, {:ok, current_v}} ->
        Version.compare(latest_v, current_v) == :gt

      _ ->
        latest != "" and latest != current
    end
  end

  defp trigger_watchtower do
    endpoint =
      System.get_env("WATCHTOWER_ENDPOINT") || "http://acex-watchtower:8080/v1/update"

    token =
      System.get_env("WATCHTOWER_HTTP_API_TOKEN") ||
        System.get_env("WATCHTOWER_TOKEN") ||
        "acex_update_token"

    Logger.info("[Updater] Triggering Watchtower update via #{endpoint}...")

    headers = [
      {"authorization", "Bearer #{token}"},
      {"content-type", "application/json"}
    ]

    case Req.post(endpoint, headers: headers, receive_timeout: 45_000, retry: false) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        Logger.info("[Updater] Watchtower update accepted: #{inspect(body)}")

        {:ok,
         %{
           status: "updating",
           method: "watchtower",
           message: "Watchtower update triggered. Containers will be recreated shortly."
         }}

      {:ok, %{status: status, body: body}} ->
        Logger.error("[Updater] Watchtower returned HTTP #{status}: #{inspect(body)}")

        {:error,
         %{
           status: "error",
           message: "Watchtower error (HTTP #{status}). Please update manually.",
           command: "docker compose pull && docker compose up -d"
         }}

      {:error, reason} ->
        # When Watchtower stops and recreates acex-gateway, or takes time pulling images,
        # the HTTP connection may close or timeout while the update is actively proceeding.
        is_in_progress =
          case reason do
            %{reason: r} when r in [:timeout, :econnreset, :closed] -> true
            :timeout -> true
            :closed -> true
            _ -> false
          end

        if is_in_progress do
          Logger.info(
            "[Updater] Watchtower request ended with #{inspect(reason)} (update in progress)."
          )

          {:ok,
           %{
             status: "updating",
             method: "watchtower",
             message: "Watchtower update dispatched. Containers will be recreated shortly."
           }}
        else
          Logger.warning("[Updater] Cannot reach Watchtower at #{endpoint}: #{inspect(reason)}")

          {:error,
           %{
             status: "error",
             message: "Cannot connect to Watchtower service. Please run update command manually.",
             command: "docker compose pull && docker compose up -d"
           }}
        end
    end
  end

  defp trigger_script do
    script_path =
      cond do
        File.exists?("update.sh") -> "./update.sh"
        File.exists?("/app/data/update.sh") -> "/app/data/update.sh"
        true -> "update.sh"
      end

    Logger.info("[Updater] Spawning update script: #{script_path}...")

    Task.start(fn ->
      System.cmd("bash", [script_path], stderr_to_stdout: true)
    end)

    {:ok,
     %{
       status: "updating",
       method: "script",
       message: "Running update script on server. Please wait..."
     }}
  end
end
