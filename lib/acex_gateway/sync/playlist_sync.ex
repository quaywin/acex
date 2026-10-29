defmodule AcexGateway.Sync.PlaylistSync do
  @moduledoc """
  Background GenServer that synchronizes:
  1. Live sports events from remote GitHub M3U (e.g. eventos.m3u) into `AcexGateway.Events.Store`.
  2. Live 24/7 channels from remote GitHub M3U (e.g. Probando) into `AcexGateway.Channels.Store`.

  Supports automatic recurring timers, conditional HTTP requests (ETag / If-None-Match),
  manual 1-click sync triggers, and GitHub URL normalization.
  """

  use GenServer
  require Logger

  alias AcexGateway.Events.Store, as: EventsStore
  alias AcexGateway.Channels.Store, as: ChannelsStore
  alias AcexGateway.Settings.Store, as: SettingsStore

  @default_events_url "https://raw.githubusercontent.com/Icastresana/lista1/main/eventos.m3u"
  @default_channels_url "https://raw.githubusercontent.com/Icastresana/lista1/main/Probando"

  # Client API

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Triggers an immediate sync of live sports events.
  """
  def sync_events(opts \\ []) do
    GenServer.call(__MODULE__, {:sync_events, opts}, 60_000)
  end

  @doc """
  Triggers an immediate sync of 24/7 channels.
  """
  def sync_channels(opts \\ []) do
    GenServer.call(__MODULE__, {:sync_channels, opts}, 60_000)
  end

  @doc """
  Returns current sync status and statistics for events and channels.
  """
  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Initial status
    initial_status = %{
      events: %{
        url: get_events_url(),
        last_sync: nil,
        status: "idle",
        count: length(EventsStore.list_events()),
        error: nil,
        etag: nil
      },
      channels: %{
        url: get_channels_url(),
        last_sync: nil,
        status: "idle",
        count: length(ChannelsStore.list_channels()),
        error: nil,
        etag: nil
      }
    }

    # Schedule initial sync after a short boot delay (3 seconds)
    Process.send_after(self(), :initial_sync, 3_000)

    {:ok, %{status: initial_status}}
  end

  @impl true
  def handle_call({:sync_events, opts}, _from, state) do
    {result, new_state} = perform_sync_events(state, opts)
    schedule_next_events_sync()
    {:reply, result, new_state}
  end

  @impl true
  def handle_call({:sync_channels, opts}, _from, state) do
    {result, new_state} = perform_sync_channels(state, opts)
    schedule_next_channels_sync()
    {:reply, result, new_state}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    # Enrich counts dynamically
    enriched_status = %{
      state.status
      | events: Map.put(state.status.events, :count, length(EventsStore.list_events())),
        channels: Map.put(state.status.channels, :count, length(ChannelsStore.list_channels()))
    }

    {:reply, enriched_status, state}
  end

  @impl true
  def handle_info(:initial_sync, state) do
    state =
      if events_sync_enabled?() do
        {_res, st} = perform_sync_events(state, force: false)
        st
      else
        state
      end

    state =
      if channels_sync_enabled?() and length(ChannelsStore.list_channels()) <= 1 do
        # Only auto-sync channels on cold start if channel list is empty or test default
        {_res, st} = perform_sync_channels(state, force: false)
        st
      else
        state
      end

    schedule_next_events_sync()
    schedule_next_channels_sync()

    {:noreply, state}
  end

  @impl true
  def handle_info(:sync_events_tick, state) do
    state =
      if events_sync_enabled?() do
        {_res, st} = perform_sync_events(state, force: false)
        st
      else
        state
      end

    schedule_next_events_sync()
    {:noreply, state}
  end

  @impl true
  def handle_info(:sync_channels_tick, state) do
    state =
      if channels_sync_enabled?() do
        {_res, st} = perform_sync_channels(state, force: false)
        st
      else
        state
      end

    schedule_next_channels_sync()
    {:noreply, state}
  end

  # Internal Sync Implementations

  defp perform_sync_events(state, opts) do
    raw_url = get_events_url()
    url = normalize_github_url(raw_url)
    etag = if Keyword.get(opts, :force, false), do: nil, else: state.status.events.etag

    headers =
      if etag && is_binary(etag) do
        [{"if-none-match", etag}]
      else
        []
      end

    now_iso = DateTime.utc_now() |> DateTime.to_iso8601()

    case Req.get(url, headers: headers, receive_timeout: 30_000) do
      {:ok, %{status: 304}} ->
        Logger.info("[PlaylistSync] Events playlist not modified (304). Using cached events.")

        new_events_status = %{
          state.status.events
          | url: raw_url,
            last_sync: now_iso,
            status: "success (not modified)",
            count: length(EventsStore.list_events()),
            error: nil
        }

        {:ok, %{state | status: %{state.status | events: new_events_status}}}

      {:ok, %{status: 200, body: body} = resp} when is_binary(body) ->
        new_etag = get_resp_header(resp, "etag")
        parsed_events = parse_events_m3u(body)

        case EventsStore.set_events(parsed_events) do
          {:ok, count} ->
            Logger.info(
              "[PlaylistSync] Successfully synced #{count} live events from #{url}"
            )

            new_events_status = %{
              state.status.events
              | url: raw_url,
                last_sync: now_iso,
                status: "success",
                count: count,
                error: nil,
                etag: new_etag
            }

            {{:ok, count}, %{state | status: %{state.status | events: new_events_status}}}

          {:error, reason} ->
            err_msg = "Failed to update events store: #{inspect(reason)}"
            Logger.error("[PlaylistSync] #{err_msg}")

            new_events_status = %{
              state.status.events
              | url: raw_url,
                last_sync: now_iso,
                status: "error",
                error: err_msg
            }

            {{:error, reason}, %{state | status: %{state.status | events: new_events_status}}}
        end

      {:ok, %{status: status}} ->
        err_msg = "Remote server returned HTTP status #{status}"
        Logger.error("[PlaylistSync] Events sync failed: #{err_msg}")

        new_events_status = %{
          state.status.events
          | url: raw_url,
            last_sync: now_iso,
            status: "error",
            error: err_msg
        }

        {{:error, err_msg}, %{state | status: %{state.status | events: new_events_status}}}

      {:error, reason} ->
        err_msg = "Network error: #{inspect(reason)}"
        Logger.error("[PlaylistSync] Events sync error: #{err_msg}")

        new_events_status = %{
          state.status.events
          | url: raw_url,
            last_sync: now_iso,
            status: "error",
            error: err_msg
        }

        {{:error, reason}, %{state | status: %{state.status | events: new_events_status}}}
    end
  rescue
    e ->
      err_msg = "Exception: #{Exception.message(e)}"
      Logger.error("[PlaylistSync] Events sync exception: #{err_msg}")
      now_iso = DateTime.utc_now() |> DateTime.to_iso8601()

      new_events_status = %{
        state.status.events
        | url: get_events_url(),
          last_sync: now_iso,
          status: "error",
          error: err_msg
      }

      {{:error, err_msg}, %{state | status: %{state.status | events: new_events_status}}}
  end

  defp perform_sync_channels(state, opts) do
    raw_url = get_channels_url()
    url = normalize_github_url(raw_url)
    etag = if Keyword.get(opts, :force, false), do: nil, else: state.status.channels.etag

    headers =
      if etag && is_binary(etag) do
        [{"if-none-match", etag}]
      else
        []
      end

    now_iso = DateTime.utc_now() |> DateTime.to_iso8601()
    mode = get_channels_sync_mode()

    case Req.get(url, headers: headers, receive_timeout: 30_000) do
      {:ok, %{status: 304}} ->
        Logger.info("[PlaylistSync] Channels playlist not modified (304). Using cached channels.")

        new_channels_status = %{
          state.status.channels
          | url: raw_url,
            last_sync: now_iso,
            status: "success (not modified)",
            count: length(ChannelsStore.list_channels()),
            error: nil
        }

        {:ok, %{state | status: %{state.status | channels: new_channels_status}}}

      {:ok, %{status: 200, body: body} = resp} when is_binary(body) ->
        new_etag = get_resp_header(resp, "etag")

        case ChannelsStore.import_channels(body, %{mode: mode, default_group: "Live TV"}) do
          {:ok, imported} when is_list(imported) ->
            count = length(imported)

            Logger.info(
              "[PlaylistSync] Successfully synced #{count} channels (mode: #{mode}) from #{url}"
            )

            new_channels_status = %{
              state.status.channels
              | url: raw_url,
                last_sync: now_iso,
                status: "success",
                count: count,
                error: nil,
                etag: new_etag
            }

            {{:ok, count}, %{state | status: %{state.status | channels: new_channels_status}}}

          {:ok, count} when is_integer(count) ->
            Logger.info(
              "[PlaylistSync] Successfully synced #{count} channels (mode: #{mode}) from #{url}"
            )

            new_channels_status = %{
              state.status.channels
              | url: raw_url,
                last_sync: now_iso,
                status: "success",
                count: count,
                error: nil,
                etag: new_etag
            }

            {{:ok, count}, %{state | status: %{state.status | channels: new_channels_status}}}

          {:error, reason} ->
            err_msg = "Failed to import channels: #{inspect(reason)}"
            Logger.error("[PlaylistSync] #{err_msg}")

            new_channels_status = %{
              state.status.channels
              | url: raw_url,
                last_sync: now_iso,
                status: "error",
                error: err_msg
            }

            {{:error, reason}, %{state | status: %{state.status | channels: new_channels_status}}}
        end

      {:ok, %{status: status}} ->
        err_msg = "Remote server returned HTTP status #{status}"
        Logger.error("[PlaylistSync] Channels sync failed: #{err_msg}")

        new_channels_status = %{
          state.status.channels
          | url: raw_url,
            last_sync: now_iso,
            status: "error",
            error: err_msg
        }

        {{:error, err_msg}, %{state | status: %{state.status | channels: new_channels_status}}}

      {:error, reason} ->
        err_msg = "Network error: #{inspect(reason)}"
        Logger.error("[PlaylistSync] Channels sync error: #{err_msg}")

        new_channels_status = %{
          state.status.channels
          | url: raw_url,
            last_sync: now_iso,
            status: "error",
            error: err_msg
        }

        {{:error, reason}, %{state | status: %{state.status | channels: new_channels_status}}}
    end
  rescue
    e ->
      err_msg = "Exception: #{Exception.message(e)}"
      Logger.error("[PlaylistSync] Channels sync exception: #{err_msg}")
      now_iso = DateTime.utc_now() |> DateTime.to_iso8601()

      new_channels_status = %{
        state.status.channels
        | url: get_channels_url(),
          last_sync: now_iso,
          status: "error",
          error: err_msg
      }

      {{:error, err_msg}, %{state | status: %{state.status | channels: new_channels_status}}}
  end

  # Events Parser

  @doc """
  Parses raw M3U text specifically formatted for sports events (e.g. eventos.m3u).
  Extracts event title, time, sport type from icons, and merges identical events' acestream hashes.
  """
  def parse_events_m3u(text) when is_binary(text) do
    lines = String.split(text, ~r/\r?\n/)

    {events, _} =
      Enum.reduce(lines, {[], nil}, fn raw_line, {acc, current_meta} ->
        line = String.trim(raw_line)

        cond do
          String.starts_with?(line, "#EXTINF") ->
            meta = extract_event_meta(line)
            {acc, meta}

          String.starts_with?(line, "#") or line == "" ->
            {acc, current_meta}

          true ->
            hashes =
              Regex.scan(~r/[a-fA-F0-9]{40}/, line)
              |> Enum.map(&String.downcase(hd(&1)))
              |> Enum.uniq()

            case hashes do
              [_ | _] ->
                meta = current_meta || %{}
                name = meta[:name] || "Live Event #{length(acc) + 1}"
                id = meta[:id] || EventsStore.generate_slug(name)
                logo = meta[:logo] || ""
                group = meta[:group] || EventsStore.detect_sport_group(name, logo)

                ev = %{
                  "id" => id,
                  "name" => name,
                  "group" => group,
                  "logo" => logo,
                  "source_type" => "content_id",
                  "sources" => hashes
                }

                # Retain current_meta so consecutive streams for same event merge together
                {acc ++ [ev], current_meta}

              [] ->
                {acc, current_meta}
            end
        end
      end)

    EventsStore.consolidate_events(events)
  end

  defp extract_event_meta(line) do
    name_from_comma =
      case Regex.run(~r/,(.+)$/, line) do
        [_, val] -> String.trim(val)
        _ -> nil
      end

    tvg_name = extract_attr(line, "tvg-name")
    raw_name = tvg_name || name_from_comma || "Live Event"

    logo = extract_attr(line, "tvg-logo") || ""
    group = extract_attr(line, "group-title")
    group = if group && group != "", do: group, else: EventsStore.detect_sport_group(raw_name, logo)

    id = EventsStore.generate_slug(raw_name)

    %{
      id: id,
      name: raw_name,
      group: group,
      logo: logo
    }
  end

  defp extract_attr(line, attr_name) do
    regex = ~r/#{Regex.escape(attr_name)}="([^"]*)"/i

    case Regex.run(regex, line) do
      [_, value] -> String.trim(value)
      nil -> nil
    end
  end

  defp get_resp_header(resp, header_name) do
    case Enum.find(resp.headers, fn {k, _v} -> String.downcase(to_string(k)) == header_name end) do
      {_k, v} -> to_string(v)
      nil -> nil
    end
  end

  # GitHub URL Normalizer

  @doc """
  Normalizes GitHub Web URLs (blob) to raw content URLs.
  Example:
  https://github.com/Icastresana/lista1/blob/main/eventos.m3u
  ->
  https://raw.githubusercontent.com/Icastresana/lista1/main/eventos.m3u
  """
  def normalize_github_url(url) when is_binary(url) do
    url = String.trim(url)

    case Regex.run(~r|^https?://github\.com/([^/]+)/([^/]+)/blob/([^/]+)/(.+)$|, url) do
      [_, user, repo, branch, path] ->
        "https://raw.githubusercontent.com/#{user}/#{repo}/#{branch}/#{path}"

      nil ->
        url
    end
  end

  def normalize_github_url(other), do: to_string(other)

  # Timers & Settings Helpers

  defp schedule_next_events_sync do
    interval_mins = get_events_sync_interval_mins()
    interval_ms = max(interval_mins, 1) * 60 * 1_000
    Process.send_after(self(), :sync_events_tick, interval_ms)
  end

  defp schedule_next_channels_sync do
    interval_hours = get_channels_sync_interval_hours()
    interval_ms = max(interval_hours, 1) * 3600 * 1_000
    Process.send_after(self(), :sync_channels_tick, interval_ms)
  end

  defp get_events_url do
    case SettingsStore.get_setting(:events_m3u_url) do
      val when is_binary(val) and val != "" -> val
      _ -> System.get_env("EVENTS_M3U_URL", @default_events_url)
    end
  end

  defp get_channels_url do
    case SettingsStore.get_setting(:channels_m3u_url) do
      val when is_binary(val) and val != "" -> val
      _ -> System.get_env("CHANNELS_M3U_URL", @default_channels_url)
    end
  end

  defp events_sync_enabled? do
    case SettingsStore.get_setting(:events_sync_enabled) do
      val when is_boolean(val) -> val
      _ -> System.get_env("EVENTS_SYNC_ENABLED", "true") in ["true", "1"]
    end
  end

  defp channels_sync_enabled? do
    case SettingsStore.get_setting(:channels_sync_enabled) do
      val when is_boolean(val) -> val
      _ -> System.get_env("CHANNELS_SYNC_ENABLED", "true") in ["true", "1"]
    end
  end

  defp get_events_sync_interval_mins do
    case SettingsStore.get_setting(:events_sync_interval_mins) do
      val when is_integer(val) and val > 0 -> val
      _ -> 15
    end
  end

  defp get_channels_sync_interval_hours do
    case SettingsStore.get_setting(:channels_sync_interval_hours) do
      val when is_integer(val) and val > 0 -> val
      _ -> 6
    end
  end

  defp get_channels_sync_mode do
    case SettingsStore.get_setting(:channels_sync_mode) do
      val when val in ["merge", "replace"] -> val
      _ -> "replace"
    end
  end
end
