defmodule AcexGateway.System.Updater do
  @moduledoc """
  Manages system version inspection, GitHub release checking with ETS caching,
  and 1-click update triggers via Native systemd symlink swaps, Watchtower internal
  HTTP API, or local scripts.
  """

  require Logger

  @cache_table :acex_updater_cache
  @cache_ttl_seconds 1800
  @default_repo "quaywin/acex"
  @install_root "/opt/acex"
  @service_name "acex.service"

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
  Checks if the host is running a Native systemd installation under `/opt/acex`
  capable of 1-click self-upgrading.
  """
  def native_installed? do
    :os.type() == {:unix, :linux} and
      File.dir?(Path.join(@install_root, "releases")) and
      not is_nil(System.find_executable("systemctl")) and
      not is_nil(System.find_executable("tar"))
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
      :native ->
        trigger_native()

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
      native_installed?() ->
        :native

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

  defp trigger_native do
    Logger.info("[Updater] Starting Native systemd upgrade in background...")

    Task.start(fn ->
      Process.sleep(300)

      case perform_native_upgrade() do
        {:ok, _} ->
          Logger.info("[Updater] Native upgrade completed successfully.")

        {:error, reason} ->
          Logger.error("[Updater] Native upgrade failed: #{inspect(reason)}")
      end
    end)

    {:ok,
     %{
       status: "updating",
       method: "native",
       message: "Downloading latest release and upgrading systemd service in background..."
     }}
  end

  @doc """
  Downloads the latest Native release tarball matching the host CPU architecture,
  verifies SHA256, extracts to `/opt/acex/releases/<timestamp>`, switches the
  `/opt/acex/current` symlink, prunes old releases, and restarts `acex.service`.
  """
  def perform_native_upgrade do
    with {:ok, arch} <- detect_arch(),
         {:ok, tmp_tar} <- download_release_tarball(arch),
         :ok <- verify_tarball_checksum(tmp_tar, arch),
         {:ok, release_dir} <- extract_release(tmp_tar),
         :ok <- switch_current_symlink(release_dir),
         :ok <- prune_old_releases(),
         :ok <- restart_systemd_service() do
      {:ok, :upgrading}
    end
  end

  defp detect_arch do
    case System.cmd("uname", ["-m"], stderr_to_stdout: true) do
      {out, 0} ->
        case String.trim(out) do
          arch when arch in ["x86_64", "amd64"] -> {:ok, "amd64"}
          arch when arch in ["aarch64", "arm64"] -> {:ok, "arm64"}
          other -> {:error, "Unsupported architecture: #{other}"}
        end

      {err, _} ->
        {:error, "Failed to detect architecture: #{err}"}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp download_release_tarball(arch) do
    repo = System.get_env("GITHUB_REPO") || @default_repo
    url = "https://github.com/#{repo}/releases/latest/download/acex-linux-#{arch}.tar.gz"

    tmp_tar =
      Path.join(System.tmp_dir!(), "acex-upgrade-#{System.unique_integer([:positive])}.tar.gz")

    Logger.info("[Updater] Downloading #{url}...")

    case Req.get(url,
           headers: [{"user-agent", "AcexGateway-Updater"}],
           into: File.stream!(tmp_tar),
           receive_timeout: 120_000
         ) do
      {:ok, %{status: 200}} ->
        {:ok, tmp_tar}

      {:ok, %{status: status}} ->
        File.rm(tmp_tar)
        {:error, "Failed to download release archive (HTTP #{status})"}

      {:error, reason} ->
        File.rm(tmp_tar)
        {:error, "Download failed: #{inspect(reason)}"}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp verify_tarball_checksum(tmp_tar, arch) do
    repo = System.get_env("GITHUB_REPO") || @default_repo
    sums_url = "https://github.com/#{repo}/releases/latest/download/SHA256SUMS"
    tarball_name = "acex-linux-#{arch}.tar.gz"

    case Req.get(sums_url,
           headers: [{"user-agent", "AcexGateway-Updater"}],
           receive_timeout: 30_000
         ) do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        case verify_sha256_against_sums(tmp_tar, tarball_name, body) do
          :ok ->
            :ok

          {:error, _} = err ->
            File.rm(tmp_tar)
            err
        end

      {:ok, %{status: status}} ->
        File.rm(tmp_tar)
        {:error, "Failed to download SHA256SUMS (HTTP #{status})"}

      {:error, reason} ->
        File.rm(tmp_tar)
        {:error, "SHA256SUMS download failed: #{inspect(reason)}"}
    end
  rescue
    e ->
      File.rm(tmp_tar)
      {:error, Exception.message(e)}
  end

  @doc false
  def verify_sha256_against_sums(file_path, tarball_name, sums_body) do
    expected =
      sums_body
      |> String.split("\n", trim: true)
      |> Enum.find_value(fn line ->
        case String.split(line, ~r/\s+/, trim: true) do
          [hash, name] when name == tarball_name -> String.downcase(hash)
          [hash, "*" <> name] when name == tarball_name -> String.downcase(hash)
          _ -> nil
        end
      end)

    if is_nil(expected) do
      {:error, "Checksum entry not found for #{tarball_name}"}
    else
      actual =
        file_path
        |> File.stream!(65_536)
        |> Enum.reduce(:crypto.hash_init(:sha256), fn chunk, acc ->
          :crypto.hash_update(acc, chunk)
        end)
        |> :crypto.hash_final()
        |> Base.encode16(case: :lower)

      if actual == expected do
        :ok
      else
        {:error, "Checksum mismatch for #{tarball_name}"}
      end
    end
  end

  defp extract_release(tmp_tar) do
    release_id =
      DateTime.utc_now()
      |> Calendar.strftime("%Y%m%d%H%M%S")

    release_dir = Path.join([@install_root, "releases", release_id])
    File.mkdir_p!(release_dir)

    try do
      case System.cmd("tar", ["-xzf", tmp_tar, "-C", release_dir], stderr_to_stdout: true) do
        {_, 0} ->
          _ = File.chmod(Path.join([release_dir, "bin", "server"]), 0o755)
          _ = File.chmod(Path.join([release_dir, "bin", "acex_gateway"]), 0o755)
          {:ok, release_dir}

        {err, code} ->
          File.rm_rf(release_dir)
          {:error, "Failed to extract release tarball (code #{code}): #{err}"}
      end
    after
      File.rm(tmp_tar)
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp switch_current_symlink(release_dir) do
    current_link = Path.join(@install_root, "current")

    case System.cmd("ln", ["-sfn", release_dir, current_link], stderr_to_stdout: true) do
      {_, 0} -> :ok
      {err, code} -> {:error, "Failed to update symlink (code #{code}): #{err}"}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp prune_old_releases do
    releases_dir = Path.join(@install_root, "releases")

    case File.ls(releases_dir) do
      {:ok, entries} ->
        entries
        |> Enum.sort(:desc)
        |> Enum.drop(2)
        |> Enum.each(fn old ->
          File.rm_rf(Path.join(releases_dir, old))
        end)

        :ok

      _ ->
        :ok
    end
  end

  defp restart_systemd_service do
    case System.cmd("systemctl", ["restart", "--no-block", @service_name], stderr_to_stdout: true) do
      {_, 0} -> :ok
      {err, code} -> {:error, "Failed to restart #{@service_name} (code #{code}): #{err}"}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp trigger_watchtower do
    endpoint =
      System.get_env("WATCHTOWER_ENDPOINT") || "http://acex-watchtower:8080/v1/update"

    token =
      System.get_env("WATCHTOWER_HTTP_API_TOKEN") ||
        System.get_env("WATCHTOWER_TOKEN") ||
        "acex_update_token"

    Logger.info("[Updater] Dispatching Watchtower update to #{endpoint} in background...")

    # Spawn background task with a small delay to ensure the HTTP 200 response
    # flushes completely to the browser before Watchtower pulls and restarts containers.
    Task.start(fn ->
      Process.sleep(250)

      headers = [
        {"authorization", "Bearer #{token}"},
        {"content-type", "application/json"}
      ]

      case Req.post(endpoint, headers: headers, receive_timeout: 120_000, retry: false) do
        {:ok, %{status: status, body: body}} when status in 200..299 ->
          Logger.info("[Updater] Watchtower update completed: #{inspect(body)}")

        {:ok, %{status: status, body: body}} ->
          Logger.warning("[Updater] Watchtower returned HTTP #{status}: #{inspect(body)}")

        {:error, reason} ->
          Logger.info(
            "[Updater] Watchtower request ended: #{inspect(reason)} (container may be recreating)."
          )
      end
    end)

    {:ok,
     %{
       status: "updating",
       method: "watchtower",
       message: "Watchtower update dispatched! Pulling new image and recreating containers..."
     }}
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
