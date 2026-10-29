defmodule AcexGateway.Events.Store do
  @moduledoc """
  High-performance concurrent store that manages ephemeral live sports events and multi-source fallbacks.
  Uses ETS with `read_concurrency: true` for sub-millisecond, lock-free lookups.
  Persists event configurations to a JSON file via atomic write so events survive process restarts.
  """

  use GenServer
  require Logger

  @default_file "data/events.json"
  @table :acex_events

  # Client API

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Lists all configured events. Reads lock-free from ETS.
  """
  def list_events do
    case :ets.whereis(@table) do
      :undefined ->
        GenServer.call(__MODULE__, :list_events)

      _ ->
        case :ets.lookup(@table, :all_events) do
          [{:all_events, events}] -> events
          [] -> GenServer.call(__MODULE__, :list_events)
        end
    end
  end

  @doc """
  Gets a single event by its ID. Reads lock-free O(1) from ETS.
  """
  def get_event(id) when is_binary(id) do
    case :ets.whereis(@table) do
      :undefined ->
        GenServer.call(__MODULE__, {:get_event, id})

      _ ->
        case :ets.lookup(@table, id) do
          [{^id, event}] -> event
          [] -> nil
        end
    end
  end

  def get_event(_), do: nil

  @doc """
  Finds an event by one of its source hashes. Reads lock-free O(1) from ETS index.
  """
  def find_event_by_source(hash) when is_binary(hash) do
    clean = sanitize_hash(hash)

    case :ets.whereis(@table) do
      :undefined ->
        Enum.find(list_events(), fn e -> clean in (e["sources"] || []) end)

      _ ->
        case :ets.lookup(@table, {:source, clean}) do
          [{{:source, ^clean}, event_id}] -> get_event(event_id)
          [] -> nil
        end
    end
  end

  def find_event_by_source(_), do: nil

  @doc """
  Promotes a working source to the front (index 0) of the event's source list.
  If the source is already first or the event does not exist, returns :noop.
  """
  def promote_event_source(event_id_or_hash, working_source)
      when is_binary(event_id_or_hash) and is_binary(working_source) do
    clean_source = sanitize_hash(working_source)

    event =
      get_event(event_id_or_hash) ||
        find_event_by_source(event_id_or_hash)

    case event do
      %{"id" => _id, "sources" => [first | _rest]} when first == clean_source ->
        :noop

      %{"id" => id, "sources" => sources} ->
        if clean_source in sources do
          new_sources = [clean_source | List.delete(sources, clean_source)]
          GenServer.call(__MODULE__, {:reorder_sources, id, new_sources})
        else
          :noop
        end

      _ ->
        :noop
    end
  end

  def promote_event_source(_, _), do: :noop

  @doc """
  Removes a permanently dead source hash from an event's source list.
  """
  def prune_dead_source(event_id_or_hash, dead_source)
      when is_binary(event_id_or_hash) and is_binary(dead_source) do
    clean_source = sanitize_hash(dead_source)

    event =
      get_event(event_id_or_hash) ||
        find_event_by_source(event_id_or_hash)

    case event do
      %{"id" => id, "sources" => sources} ->
        if clean_source in sources do
          GenServer.call(__MODULE__, {:remove_source, id, clean_source})
        else
          :noop
        end

      _ ->
        :noop
    end
  end

  def prune_dead_source(_, _), do: :noop

  @doc """
  Replaces all events atomically with a new list of events.
  """
  def set_events(events) when is_list(events) do
    GenServer.call(__MODULE__, {:set_events, events})
  end

  @doc """
  Clears all events.
  """
  def clear_events do
    GenServer.call(__MODULE__, :clear_events)
  end

  @doc """
  Generates an M3U playlist string for all currently stored events.
  """
  def export_m3u(base_url, auth_opts \\ %{}) when is_binary(base_url) do
    generate_m3u(list_events(), base_url, auth_opts)
  end

  @doc """
  Generates an M3U playlist from a given list of event maps.
  """
  def generate_m3u(events, base_url, auth_opts) do
    base = String.trim_trailing(base_url, "/")
    username = auth_opts[:username] || auth_opts["username"]
    password = auth_opts[:password] || auth_opts["password"]

    has_auth =
      is_binary(username) and is_binary(password) and String.trim(username) != "" and
        String.trim(password) != ""

    header = "#EXTM3U x-tvg-url=\"\""
    format = auth_opts[:format] || auth_opts["format"]

    event_lines =
      events
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {event, index} ->
        id = clean_m3u_attr(event["id"])
        name = event["name"] || "Live Event"
        group = clean_m3u_attr(event["group"] || "Live Events")
        logo = clean_m3u_attr(event["logo"] || "")
        display_name = clean_m3u_attr(name)

        inf =
          "#EXTINF:-1 tvg-id=\"#{id}\" tvg-chno=\"#{index}\" tvg-name=\"#{display_name}\" tvg-logo=\"#{logo}\" group-title=\"#{group}\",#{display_name}"

        url =
          cond do
            format in [:hls, "hls", "m3u8"] and has_auth ->
              "#{base}/h/#{username}/#{password}/#{id}.m3u8"

            format in [:hls, "hls", "m3u8"] ->
              "#{base}/h/#{id}.m3u8"

            format in [:ts, "ts"] and has_auth ->
              "#{base}/t/#{username}/#{password}/#{id}.ts"

            format in [:ts, "ts"] ->
              "#{base}/t/#{id}.ts"

            has_auth ->
              "#{base}/live/#{username}/#{password}/#{id}.ts"

            true ->
              "#{base}/live/#{id}.ts"
          end

        [inf, url]
      end)

    Enum.join([header | event_lines], "\n") <> "\n"
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    file_path =
      Keyword.get(
        opts,
        :file_path,
        Application.get_env(:acex_gateway, :events_file) ||
          System.get_env("EVENTS_FILE", @default_file)
      )

    if :ets.info(@table) == :undefined do
      :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    end

    events = load_events(file_path)
    sync_to_ets(events)

    {:ok, %{file_path: file_path, events: events}}
  end

  @impl true
  def handle_call(:list_events, _from, state) do
    {:reply, state.events, state}
  end

  @impl true
  def handle_call({:get_event, id}, _from, state) do
    event = Enum.find(state.events, fn e -> e["id"] == id end)
    {:reply, event, state}
  end

  @impl true
  def handle_call({:set_events, new_events}, _from, state) do
    normalized =
      new_events
      |> Enum.map(&normalize_event/1)
      |> Enum.reject(&(&1["sources"] == []))
      |> consolidate_events()

    sync_to_ets(normalized)
    persist_events(state.file_path, normalized)

    Logger.info("[Events.Store] Loaded #{length(normalized)} live sports events")
    {:reply, {:ok, length(normalized)}, %{state | events: normalized}}
  end

  @impl true
  def handle_call(:clear_events, _from, state) do
    sync_to_ets([])
    persist_events(state.file_path, [])
    Logger.info("[Events.Store] Cleared all live sports events")
    {:reply, :ok, %{state | events: []}}
  end

  @impl true
  def handle_call({:remove_source, id, dead_source}, _from, state) do
    case Enum.find_index(state.events, fn e -> e["id"] == id end) do
      nil ->
        {:reply, {:error, :not_found}, state}

      idx ->
        existing = Enum.at(state.events, idx)
        updated_sources = List.delete(existing["sources"] || [], dead_source)

        updated_event = Map.put(existing, "sources", updated_sources)
        new_events = List.replace_at(state.events, idx, updated_event)

        sync_to_ets(new_events)
        persist_events(state.file_path, new_events)

        Logger.info("[Events.Store] Pruned dead source #{dead_source} from event '#{id}'")
        {:reply, :ok, %{state | events: new_events}}
    end
  end

  @impl true
  def handle_call({:reorder_sources, id, new_sources}, _from, state) do
    case Enum.find_index(state.events, fn e -> e["id"] == id end) do
      nil ->
        {:reply, :noop, state}

      idx ->
        existing = Enum.at(state.events, idx)
        updated = Map.put(existing, "sources", new_sources)
        new_events = List.replace_at(state.events, idx, updated)

        sync_to_ets(new_events)
        persist_events(state.file_path, new_events)

        Logger.info("[Events.Store] Promoted working source for event '#{id}'")
        {:reply, :ok, %{state | events: new_events}}
    end
  end

  # Helper Functions

  def sanitize_hash(hash) when is_binary(hash) do
    case Regex.run(~r/[a-fA-F0-9]{40}/, hash) do
      [clean | _] -> String.downcase(clean)
      nil -> String.downcase(String.trim(hash))
    end
  end

  def sanitize_hash(other), do: to_string(other)

  defp sync_to_ets(events) do
    if :ets.whereis(@table) != :undefined do
      :ets.delete_all_objects(@table)
      :ets.insert(@table, {:all_events, events})

      for event <- events do
        id = event["id"]
        :ets.insert(@table, {id, event})

        for source <- event["sources"] || [] do
          clean_src = sanitize_hash(source)
          :ets.insert(@table, {{:source, clean_src}, id})
        end
      end
    end

    :ok
  end

  defp load_events(file_path) do
    if File.exists?(file_path) do
      case File.read(file_path) do
        {:ok, content} ->
          case Jason.decode(content) do
            {:ok, list} when is_list(list) ->
              list
              |> Enum.map(&normalize_event/1)
              |> Enum.reject(&(&1["sources"] == []))
              |> consolidate_events()

            _ ->
              []
          end

        _ ->
          []
      end
    else
      []
    end
  end

  defp persist_events(file_path, events) do
    dir = Path.dirname(file_path)
    File.mkdir_p!(dir)

    tmp_path = "#{file_path}.tmp.#{:erlang.unique_integer([:positive])}"

    case Jason.encode(events, pretty: true) do
      {:ok, json} ->
        case File.write(tmp_path, json) do
          :ok ->
            File.rename(tmp_path, file_path)

          {:error, reason} ->
            Logger.error("[Events.Store] Failed to write temp file #{tmp_path}: #{inspect(reason)}")
            File.rm(tmp_path)
            {:error, reason}
        end

      {:error, reason} ->
        Logger.error("[Events.Store] Failed to encode events to JSON: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def normalize_event(params) when is_map(params) do
    name = params["name"] || params[:name] || "Unnamed Event"
    id = params["id"] || params[:id] || generate_slug(name)
    id = if id == "", do: "event-#{:erlang.unique_integer([:positive])}", else: id
    group = params["group"] || params[:group] || detect_sport_group(name, params["logo"] || "")
    logo = params["logo"] || params[:logo] || ""

    raw_sources =
      cond do
        is_list(params["sources"]) -> params["sources"]
        is_list(params[:sources]) -> params[:sources]
        is_binary(params["sources"]) -> String.split(params["sources"], ~r/[\s,]+/)
        params["source"] && params["source"] != "" -> [params["source"]]
        params["content_id"] && params["content_id"] != "" -> [params["content_id"]]
        true -> []
      end

    sources =
      raw_sources
      |> List.flatten()
      |> Enum.flat_map(fn
        item when is_binary(item) ->
          scanned = Regex.scan(~r/[a-fA-F0-9]{40}/, item)

          if length(scanned) > 1 do
            Enum.map(scanned, &String.downcase(hd(&1)))
          else
            [sanitize_hash(item)]
          end

        other ->
          [sanitize_hash(other)]
      end)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    %{
      "id" => id,
      "name" => name,
      "group" => group,
      "logo" => logo,
      "source_type" => "content_id",
      "sources" => sources
    }
  end

  def consolidate_events(events) do
    events
    |> Enum.reduce([], fn ev, acc ->
      case Enum.find_index(acc, fn existing -> existing["id"] == ev["id"] end) do
        nil ->
          acc ++ [ev]

        idx ->
          existing = Enum.at(acc, idx)
          merged_sources = Enum.uniq(existing["sources"] ++ ev["sources"])
          updated = Map.put(existing, "sources", merged_sources)
          List.replace_at(acc, idx, updated)
      end
    end)
  end

  def detect_sport_group(name, logo) do
    logo_str = to_string(logo)
    name_str = to_string(name)

    cond do
      String.contains?(logo_str, "soccer-ball-variant") ->
        "Live Football"

      String.contains?(logo_str, "ball.png") ->
        "Live Tennis"

      String.contains?(logo_str, "basketball") ->
        "Live Basketball"

      String.contains?(logo_str, "golf") ->
        "Live Golf"

      String.contains?(logo_str, "padel") ->
        "Live Padel"

      String.contains?(logo_str, "american-football") ->
        "Live NFL"

      String.contains?(logo_str, "bike") ->
        "Live Cycling / Racing"

      Regex.match?(~r/(f1|formula 1|motogp)/i, name_str) ->
        "Live Motorsport"

      Regex.match?(~r/(ufc|mma|boxeo|boxing)/i, name_str) ->
        "Live Combat Sports"

      true ->
        "Live Sports"
    end
  end

  def generate_slug(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^\w\s-]/u, "")
    |> String.replace(~r/[\s_-]+/, "-")
    |> String.trim("-")
  end

  defp clean_m3u_attr(nil), do: ""

  defp clean_m3u_attr(val) when is_binary(val) do
    val
    |> String.replace("\"", "'")
    |> String.replace("\r", " ")
    |> String.replace("\n", " ")
    |> String.trim()
  end

  defp clean_m3u_attr(val), do: to_string(val)
end
