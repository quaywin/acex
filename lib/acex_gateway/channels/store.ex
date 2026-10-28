defmodule AcexGateway.Channels.Store do
  @moduledoc """
  High-performance concurrent store that manages the IPTV channel lineup and multi-source fallbacks.
  Uses ETS with `read_concurrency: true` for sub-millisecond, lock-free lookups.
  Persists channel configurations to a JSON file via atomic write.
  """

  use GenServer
  require Logger

  @default_file "data/channels.json"
  @default_groups_file "data/groups.json"
  @table :acex_channels

  @baseline_groups ["General", "Sports", "News", "Movies", "Entertainment"]

  @default_channels [
    %{
      "id" => "big-buck-bunny",
      "name" => "Big Buck Bunny (Benchmark Test)",
      "group" => "Benchmark & Demo",
      "logo" =>
        "https://upload.wikimedia.org/wikipedia/commons/c/c5/Big_buck_bunny_poster_big.jpg",
      "source_type" => "content_id",
      "sources" => [
        "dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c"
      ]
    }
  ]

  # Client API

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Lists all configured channels. Reads lock-free from ETS.
  """
  def list_channels do
    case :ets.whereis(@table) do
      :undefined ->
        GenServer.call(__MODULE__, :list_channels)

      _ ->
        case :ets.lookup(@table, :all_channels) do
          [{:all_channels, channels}] -> channels
          [] -> GenServer.call(__MODULE__, :list_channels)
        end
    end
  end

  @doc """
  Gets a single channel by its ID. Reads lock-free O(1) from ETS.
  """
  def get_channel(id) when is_binary(id) do
    case :ets.whereis(@table) do
      :undefined ->
        GenServer.call(__MODULE__, {:get_channel, id})

      _ ->
        case :ets.lookup(@table, id) do
          [{^id, channel}] -> channel
          [] -> nil
        end
    end
  end

  @doc """
  Finds a channel by one of its source hashes. Reads lock-free O(1) from ETS index.
  """
  def find_channel_by_source(hash) when is_binary(hash) do
    clean = sanitize_hash(hash)

    case :ets.whereis(@table) do
      :undefined ->
        Enum.find(list_channels(), fn c -> clean in (c["sources"] || []) end)

      _ ->
        case :ets.lookup(@table, {:source, clean}) do
          [{{:source, ^clean}, channel_id}] -> get_channel(channel_id)
          [] -> nil
        end
    end
  end

  def find_channel_by_source(_), do: nil

  @doc """
  Promotes a working source to the front (index 0) of the channel's source list.
  If the source is already first or the channel does not exist, returns :noop.
  """
  def promote_channel_source(channel_id_or_hash, working_source)
      when is_binary(channel_id_or_hash) and is_binary(working_source) do
    clean_source = sanitize_hash(working_source)

    channel =
      get_channel(channel_id_or_hash) ||
        find_channel_by_source(channel_id_or_hash) ||
        find_channel_by_source(clean_source)

    case channel do
      %{"id" => id, "sources" => sources} = ch when is_list(sources) and length(sources) > 1 ->
        clean_sources = Enum.map(sources, &sanitize_hash/1)

        case Enum.find_index(clean_sources, &(&1 == clean_source)) do
          nil ->
            :noop

          0 ->
            :noop

          _idx ->
            promoted = [clean_source | Enum.reject(clean_sources, &(&1 == clean_source))]
            updated_channel = Map.put(ch, "sources", promoted)
            save_channel(updated_channel)

            Logger.info(
              "[Store] Promoted working source #{clean_source} to index 0 for channel '#{id}'"
            )

            {:ok, updated_channel}
        end

      _ ->
        :noop
    end
  rescue
    _ -> :noop
  end

  def promote_channel_source(_, _), do: :noop

  @doc """
  Removes a specific source hash from a channel.
  Refuses to remove the last source (channel must keep at least 1 source).
  """
  def remove_channel_source(channel_id, source)
      when is_binary(channel_id) and is_binary(source) do
    clean_source = sanitize_hash(source)

    case get_channel(channel_id) do
      %{"sources" => sources} = ch when is_list(sources) and length(sources) > 1 ->
        clean_sources = Enum.map(sources, &sanitize_hash/1)

        if clean_source in clean_sources do
          remaining = Enum.reject(clean_sources, &(&1 == clean_source))
          updated_channel = Map.put(ch, "sources", remaining)
          save_channel(updated_channel)

          Logger.info(
            "[Store] Removed source #{clean_source} from channel '#{channel_id}'. Remaining: #{length(remaining)}"
          )

          {:ok, updated_channel}
        else
          :noop
        end

      %{"sources" => sources} when is_list(sources) and length(sources) <= 1 ->
        {:error, :cannot_remove_last_source}

      nil ->
        {:error, :channel_not_found}

      _ ->
        :noop
    end
  end

  def remove_channel_source(_, _), do: {:error, :invalid_arguments}

  @doc """
  Prunes a dead source from a channel, looked up by channel ID or by source hash.
  Safe no-op if the channel has only 1 source.
  """
  def prune_dead_source(channel_id_or_hash, dead_source)
      when is_binary(channel_id_or_hash) and is_binary(dead_source) do
    clean_dead = sanitize_hash(dead_source)

    channel =
      get_channel(channel_id_or_hash) ||
        find_channel_by_source(channel_id_or_hash) ||
        find_channel_by_source(clean_dead)

    case channel do
      %{"id" => id, "sources" => sources} when is_list(sources) and length(sources) > 1 ->
        remove_channel_source(id, clean_dead)

      _ ->
        :noop
    end
  rescue
    _ -> :noop
  end

  def prune_dead_source(_, _), do: :noop

  @doc """
  Saves (creates or updates) a channel.
  """
  def save_channel(channel_params) when is_map(channel_params) do
    GenServer.call(__MODULE__, {:save_channel, channel_params})
  end

  @doc """
  Deletes a channel by ID.
  """
  def delete_channel(id) when is_binary(id) do
    GenServer.call(__MODULE__, {:delete_channel, id})
  end

  @doc """
  Generates an M3U playlist pointing to the provided base URL, optionally attaching Xtream auth credentials.
  Runs concurrently inside caller process without blocking GenServer.
  """
  def export_m3u(base_url, auth_opts \\ %{}) when is_binary(base_url) do
    generate_m3u(list_channels(), base_url, auth_opts)
  end

  @doc """
  Exports channel lineup as clean pipe-delimited text (Content ID | Name | Country | Group).
  Runs concurrently inside caller process without blocking GenServer.
  """
  def export_txt do
    generate_txt(list_channels())
  end

  @doc """
  Imports channels from raw text (M3U or line-by-line Content IDs) or a list of channel maps.
  Options:
    - :default_group (string, default: "General")
    - :default_country (string, default: "")
    - :mode (:merge or :replace, default: :merge)
  """
  def import_channels(input, opts \\ %{}) do
    GenServer.call(__MODULE__, {:import_channels, input, opts})
  end

  @doc """
  Lists all configured playlist groups, enriched with live channel counts.
  Reads lock-free from ETS.
  """
  def list_groups do
    groups =
      case :ets.whereis(@table) do
        :undefined ->
          GenServer.call(__MODULE__, :list_groups)

        _ ->
          case :ets.lookup(@table, :all_groups) do
            [{:all_groups, list}] -> list
            [] -> GenServer.call(__MODULE__, :list_groups)
          end
      end

    channels = list_channels()
    counts = Enum.frequencies_by(channels, fn c -> c["group"] || "General" end)

    Enum.map(groups, fn g ->
      count = Map.get(counts, g["name"], 0)
      Map.put(g, "channel_count", count)
    end)
  end

  @doc """
  Gets a group by its slug ID, enriched with live channel count.
  """
  def get_group(id) when is_binary(id) do
    Enum.find(list_groups(), fn g -> g["id"] == id end)
  end

  def get_group(_), do: nil

  @doc """
  Creates a new group.
  """
  def create_group(attrs_or_name) do
    GenServer.call(__MODULE__, {:create_group, attrs_or_name})
  end

  @doc """
  Renames a group and cascades the new name to all matching channels.
  """
  def rename_group(id, new_name) when is_binary(id) and is_binary(new_name) do
    GenServer.call(__MODULE__, {:rename_group, id, new_name})
  end

  @doc """
  Deletes a group and reassigns any member channels to fallback_group (default "General").
  """
  def delete_group(id, fallback_group \\ "General") when is_binary(id) do
    GenServer.call(__MODULE__, {:delete_group, id, fallback_group})
  end

  @doc """
  Moves multiple channels to a target group. Auto-creates the group if it doesn't exist.
  """
  def move_channels_group(channel_ids, target_group_name)
      when is_list(channel_ids) and is_binary(target_group_name) do
    GenServer.call(__MODULE__, {:move_channels_group, channel_ids, target_group_name})
  end

  @doc """
  Moves a single channel to a target group.
  """
  def set_channel_group(channel_id, target_group_name)
      when is_binary(channel_id) and is_binary(target_group_name) do
    move_channels_group([channel_id], target_group_name)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    end

    file_path =
      Keyword.get(
        opts,
        :file_path,
        Application.get_env(:acex_gateway, :channels_file) ||
          System.get_env("CHANNELS_FILE", @default_file)
      )

    groups_file =
      Keyword.get(
        opts,
        :groups_file,
        Application.get_env(:acex_gateway, :groups_file) ||
          System.get_env("GROUPS_FILE", @default_groups_file)
      )

    channels = load_channels(file_path)
    groups = load_groups(groups_file, channels)
    sync_to_ets(channels, groups)

    {:ok, %{file_path: file_path, groups_file: groups_file, channels: channels, groups: groups}}
  end

  @impl true
  def handle_call(:list_channels, _from, state) do
    {:reply, state.channels, state}
  end

  def handle_call({:get_channel, id}, _from, state) do
    channel = Enum.find(state.channels, fn c -> c["id"] == id end)
    {:reply, channel, state}
  end

  def handle_call({:save_channel, params}, _from, state) do
    channel = normalize_channel_param(params)
    group_name = channel["group"] || "General"

    {new_groups, groups_changed} = maybe_add_group(state.groups, group_name)

    # Upsert channel
    new_channels =
      case Enum.find_index(state.channels, fn c -> c["id"] == channel["id"] end) do
        nil -> state.channels ++ [channel]
        idx -> List.replace_at(state.channels, idx, channel)
      end

    sync_to_ets(new_channels, new_groups)
    new_state = %{state | channels: new_channels, groups: new_groups}
    persist_channels(new_state.file_path, new_channels)
    if groups_changed, do: persist_groups(new_state.groups_file, new_groups)

    {:reply, {:ok, channel}, new_state}
  end

  def handle_call({:delete_channel, id}, _from, state) do
    new_channels = Enum.reject(state.channels, fn c -> c["id"] == id end)
    sync_to_ets(new_channels, state.groups)
    new_state = %{state | channels: new_channels}
    persist_channels(new_state.file_path, new_channels)

    {:reply, :ok, new_state}
  end

  def handle_call({:import_channels, input, opts}, _from, state) do
    opts_map = if is_map(opts), do: opts, else: Enum.into(opts, %{})

    default_group =
      Map.get(opts_map, :default_group) || Map.get(opts_map, "default_group") || "General"

    default_country =
      Map.get(opts_map, :default_country) || Map.get(opts_map, "default_country") || ""

    mode = to_string(Map.get(opts_map, :mode) || Map.get(opts_map, "mode") || "merge")

    parsed_channels =
      cond do
        is_list(input) ->
          Enum.map(input, &normalize_channel_param/1)
          |> Enum.reject(&(&1["sources"] == []))
          |> consolidate_channels()

        is_binary(input) and String.trim(input) != "" ->
          parse_import_text(input, default_group, default_country)

        true ->
          []
      end

    if parsed_channels == [] do
      {:reply, {:error, :no_valid_channels_found}, state}
    else
      new_channels =
        if mode == "replace" do
          parsed_channels
        else
          # Merge with existing channels
          Enum.reduce(parsed_channels, state.channels, fn imported, acc ->
            case Enum.find_index(acc, fn c -> c["id"] == imported["id"] end) do
              nil ->
                acc ++ [imported]

              idx ->
                existing = Enum.at(acc, idx)
                merged_sources = Enum.uniq(existing["sources"] ++ imported["sources"])

                updated =
                  existing
                  |> Map.put("sources", merged_sources)
                  |> maybe_update_field("country", imported["country"])
                  |> maybe_update_field("group", imported["group"])
                  |> maybe_update_field("logo", imported["logo"])

                List.replace_at(acc, idx, updated)
            end
          end)
        end

      # Extract groups and sync
      imported_groups =
        new_channels
        |> Enum.map(&(&1["group"] || "General"))
        |> Enum.uniq()

      {new_groups, groups_changed} =
        Enum.reduce(imported_groups, {state.groups, false}, fn gname, {acc_groups, acc_changed} ->
          {updated_groups, changed} = maybe_add_group(acc_groups, gname)
          {updated_groups, acc_changed or changed}
        end)

      sync_to_ets(new_channels, new_groups)
      new_state = %{state | channels: new_channels, groups: new_groups}
      persist_channels(new_state.file_path, new_channels)
      if groups_changed, do: persist_groups(new_state.groups_file, new_groups)

      {:reply, {:ok, parsed_channels}, new_state}
    end
  end

  def handle_call(:list_groups, _from, state) do
    {:reply, state.groups, state}
  end

  def handle_call({:create_group, attrs_or_name}, _from, state) do
    name =
      cond do
        is_binary(attrs_or_name) ->
          String.trim(attrs_or_name)

        is_map(attrs_or_name) ->
          String.trim(to_string(attrs_or_name["name"] || attrs_or_name[:name] || ""))

        true ->
          ""
      end

    if name == "" do
      {:reply, {:error, :invalid_name}, state}
    else
      exists =
        Enum.find(state.groups, fn g ->
          String.downcase(g["name"]) == String.downcase(name)
        end)

      if exists do
        {:reply, {:error, :already_exists}, state}
      else
        new_group = build_new_group(state.groups, name)
        new_groups = state.groups ++ [new_group]
        sync_to_ets(state.channels, new_groups)
        persist_groups(state.groups_file, new_groups)

        {:reply, {:ok, new_group}, %{state | groups: new_groups}}
      end
    end
  end

  def handle_call({:rename_group, id, new_name}, _from, state) do
    clean_name = String.trim(new_name)

    if clean_name == "" do
      {:reply, {:error, :invalid_name}, state}
    else
      case Enum.find_index(state.groups, fn g -> g["id"] == id end) do
        nil ->
          {:reply, {:error, :not_found}, state}

        idx ->
          exists =
            Enum.find(state.groups, fn g ->
              g["id"] != id and String.downcase(g["name"]) == String.downcase(clean_name)
            end)

          if exists do
            {:reply, {:error, :already_exists}, state}
          else
            old_group = Enum.at(state.groups, idx)
            old_name = old_group["name"]
            updated_group = Map.put(old_group, "name", clean_name)
            new_groups = List.replace_at(state.groups, idx, updated_group)

            # Cascade rename to all channels
            {new_channels, channels_changed} =
              Enum.map_reduce(state.channels, false, fn ch, changed ->
                if ch["group"] == old_name do
                  {Map.put(ch, "group", clean_name), true}
                else
                  {ch, changed}
                end
              end)

            sync_to_ets(new_channels, new_groups)
            persist_groups(state.groups_file, new_groups)
            if channels_changed, do: persist_channels(state.file_path, new_channels)

            {:reply, {:ok, updated_group}, %{state | groups: new_groups, channels: new_channels}}
          end
      end
    end
  end

  def handle_call({:delete_group, id, fallback_group}, _from, state) do
    case Enum.find(state.groups, fn g -> g["id"] == id end) do
      nil ->
        {:reply, {:error, :not_found}, state}

      target_group ->
        if length(state.groups) <= 1 do
          {:reply, {:error, :cannot_delete_last_group}, state}
        else
          old_name = target_group["name"]
          remaining_groups = Enum.reject(state.groups, fn g -> g["id"] == id end)
          clean_fallback = String.trim(fallback_group || "")

          fallback_name =
            cond do
              clean_fallback != "" and clean_fallback != old_name and
                  Enum.any?(remaining_groups, &(&1["name"] == clean_fallback)) ->
                clean_fallback

              Enum.any?(remaining_groups, &(&1["name"] == "General")) ->
                "General"

              true ->
                hd(remaining_groups)["name"]
            end

          {final_groups, _} = maybe_add_group(remaining_groups, fallback_name)

          # Reassign orphan channels to fallback group
          {new_channels, channels_changed} =
            Enum.map_reduce(state.channels, false, fn ch, changed ->
              if ch["group"] == old_name do
                {Map.put(ch, "group", fallback_name), true}
              else
                {ch, changed}
              end
            end)

          sync_to_ets(new_channels, final_groups)
          persist_groups(state.groups_file, final_groups)
          if channels_changed, do: persist_channels(state.file_path, new_channels)

          {:reply, {:ok, %{deleted: id, reassigned_to: fallback_name}},
           %{state | groups: final_groups, channels: new_channels}}
        end
    end
  end

  def handle_call({:move_channels_group, channel_ids, target_group_name}, _from, state) do
    clean_target = String.trim(target_group_name || "")
    clean_target = if clean_target == "", do: "General", else: clean_target
    target_ids_set = MapSet.new(channel_ids)

    {new_groups, groups_changed} = maybe_add_group(state.groups, clean_target)

    {new_channels, moved_count} =
      Enum.map_reduce(state.channels, 0, fn ch, acc ->
        if MapSet.member?(target_ids_set, ch["id"]) do
          {Map.put(ch, "group", clean_target), acc + 1}
        else
          {ch, acc}
        end
      end)

    sync_to_ets(new_channels, new_groups)
    if moved_count > 0, do: persist_channels(state.file_path, new_channels)
    if groups_changed, do: persist_groups(state.groups_file, new_groups)

    {:reply, {:ok, %{moved_count: moved_count, target_group: clean_target}},
     %{state | channels: new_channels, groups: new_groups}}
  end

  def handle_call({:export_m3u, base_url, auth_opts}, _from, state) do
    m3u_content = generate_m3u(state.channels, base_url, auth_opts)
    {:reply, m3u_content, state}
  end

  def handle_call(:export_txt, _from, state) do
    txt_content = generate_txt(state.channels)
    {:reply, txt_content, state}
  end

  # Fast ETS Synchronization

  defp sync_to_ets(channels, groups) do
    if :ets.whereis(@table) != :undefined do
      :ets.delete_all_objects(@table)
      :ets.insert(@table, {:all_channels, channels})
      :ets.insert(@table, {:all_groups, groups})

      for channel <- channels do
        id = channel["id"]
        :ets.insert(@table, {id, channel})

        for source <- channel["sources"] || [] do
          clean_src = sanitize_hash(source)
          :ets.insert(@table, {{:source, clean_src}, id})
        end
      end
    end

    :ok
  end

  # Playlist Generation Logic (Pure Functions, executed in caller process)

  @doc false
  def generate_m3u(channels, base_url, auth_opts) do
    base = String.trim_trailing(base_url, "/")
    epg = AcexGateway.Config.epg_url()
    username = auth_opts[:username] || auth_opts["username"]
    password = auth_opts[:password] || auth_opts["password"]

    has_auth =
      is_binary(username) and is_binary(password) and String.trim(username) != "" and
        String.trim(password) != ""

    header =
      if is_binary(epg) and String.trim(epg) != "" do
        clean_epg = clean_m3u_attr(epg)
        "#EXTM3U x-tvg-url=\"#{clean_epg}\" url-tvg=\"#{clean_epg}\""
      else
        "#EXTM3U x-tvg-url=\"\""
      end

    format = auth_opts[:format] || auth_opts["format"]

    channel_lines =
      channels
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {c, index} ->
        id = clean_m3u_attr(c["id"])
        name = c["name"] || "Channel"
        group = clean_m3u_attr(c["group"] || "General")
        logo = clean_m3u_attr(c["logo"] || "")
        country = c["country"]

        display_name = format_playlist_title(name, country)
        clean_name = clean_m3u_attr(display_name)

        country_attr =
          if is_binary(country) and String.trim(country) != "" do
            " tvg-country=\"#{clean_m3u_attr(String.trim(country))}\""
          else
            ""
          end

        inf =
          "#EXTINF:-1 tvg-id=\"#{id}\" tvg-chno=\"#{index}\" tvg-name=\"#{clean_name}\"#{country_attr} tvg-logo=\"#{logo}\" group-title=\"#{group}\",#{display_name}"

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
              "#{base}/live?channel=#{id}"
          end

        [inf, url]
      end)

    Enum.join([header] ++ channel_lines, "\n") <> "\n"
  end

  @doc false
  def generate_txt(channels) do
    lines =
      Enum.flat_map(channels, fn c ->
        name = c["name"] || "Channel"
        country = c["country"] || ""
        group = c["group"] || "General"
        sources = c["sources"] || []

        case sources do
          [] ->
            []

          [single] ->
            ["#{single} | #{name} | #{country} | #{group}"]

          multiple ->
            Enum.map(multiple, fn src ->
              "#{src} | #{name} | #{country} | #{group}"
            end)
        end
      end)

    Enum.join(lines, "\n") <> "\n"
  end

  @doc """
  Amends country tag before the channel title for playlist generation.
  Example:
      format_playlist_title("VTV3 HD", "VN") => "[VN] VTV3 HD"
      format_playlist_title("Sky Sports", "UK") => "[UK] Sky Sports"
  """
  def format_playlist_title(name, country) do
    country_str = if is_binary(country), do: String.trim(country), else: ""
    name_str = if is_binary(name), do: String.trim(name), else: ""

    cond do
      country_str == "" ->
        name_str

      String.starts_with?(name_str, "[#{country_str}]") or
          String.starts_with?(name_str, country_str) ->
        name_str

      String.starts_with?(country_str, "[") and String.ends_with?(country_str, "]") ->
        "#{country_str} #{name_str}"

      true ->
        "[#{country_str}] #{name_str}"
    end
  end

  # Helpers

  defp load_channels(file_path) do
    if File.exists?(file_path) do
      case File.read(file_path) do
        {:ok, content} ->
          case Jason.decode(content) do
            {:ok, list} when is_list(list) ->
              list

            _ ->
              Logger.warning(
                "[Channels.Store] Failed to parse #{file_path}. Using default channels."
              )

              @default_channels
          end

        {:error, _} ->
          @default_channels
      end
    else
      # Initialize default file
      persist_channels(file_path, @default_channels)
      @default_channels
    end
  end

  defp persist_channels(file_path, channels) do
    dir = Path.dirname(file_path)

    if dir != "." and not File.dir?(dir) do
      File.mkdir_p!(dir)
    end

    case Jason.encode(channels, pretty: true) do
      {:ok, json} ->
        tmp_path = "#{file_path}.tmp.#{:erlang.unique_integer([:positive])}"

        case File.write(tmp_path, json) do
          :ok ->
            File.rename(tmp_path, file_path)

          {:error, reason} ->
            Logger.error(
              "[Channels.Store] Failed to write channels temp file '#{tmp_path}': #{inspect(reason)}"
            )
        end

      {:error, reason} ->
        Logger.error("[Channels.Store] Failed to serialize channels: #{inspect(reason)}")
    end
  end

  defp load_groups(groups_file, channels) do
    with {:ok, content} <- File.read(groups_file),
         {:ok, list} when is_list(list) and list != [] <- Jason.decode(content) do
      normalized =
        list
        |> Enum.with_index(1)
        |> Enum.map(fn {g, idx} ->
          name = g["name"] || "General"
          base_id = g["id"] || generate_slug(name)
          id = if base_id == "", do: "group-#{idx}", else: base_id
          order = g["order"] || idx
          %{"id" => id, "name" => name, "order" => order}
        end)

      channel_groups =
        channels
        |> Enum.map(&(&1["group"] || "General"))
        |> Enum.uniq()

      {merged, changed} =
        Enum.reduce(channel_groups, {normalized, false}, fn gname, {acc, chg} ->
          {res, c} = maybe_add_group(acc, gname)
          {res, chg or c}
        end)

      if changed, do: persist_groups(groups_file, merged)
      Enum.sort_by(merged, &(&1["order"] || 0))
    else
      _ ->
        bootstrap_groups(groups_file, channels)
    end
  end

  defp bootstrap_groups(groups_file, channels) do
    channel_groups =
      channels
      |> Enum.map(& &1["group"])
      |> Enum.reject(&(is_nil(&1) or String.trim(&1) == ""))

    distinct_names =
      ["General" | channel_groups ++ @baseline_groups]
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq_by(&String.downcase/1)

    groups =
      distinct_names
      |> Enum.with_index(1)
      |> Enum.map(fn {name, idx} ->
        base = generate_slug(name)
        id = if base == "", do: "group-#{idx}", else: base

        %{
          "id" => id,
          "name" => name,
          "order" => idx
        }
      end)

    persist_groups(groups_file, groups)
    groups
  end

  defp persist_groups(file_path, groups) do
    dir = Path.dirname(file_path)

    if dir != "." and not File.dir?(dir) do
      File.mkdir_p!(dir)
    end

    case Jason.encode(groups, pretty: true) do
      {:ok, json} ->
        tmp_path = "#{file_path}.tmp.#{:erlang.unique_integer([:positive])}"

        case File.write(tmp_path, json) do
          :ok ->
            File.rename(tmp_path, file_path)

          {:error, reason} ->
            Logger.error(
              "[Channels.Store] Failed to write groups temp file '#{tmp_path}': #{inspect(reason)}"
            )
        end

      {:error, reason} ->
        Logger.error("[Channels.Store] Failed to serialize groups: #{inspect(reason)}")
    end
  end

  defp maybe_add_group(groups, name) do
    clean_name = String.trim(name || "")
    clean_name = if clean_name == "", do: "General", else: clean_name

    case Enum.find(groups, fn g -> String.downcase(g["name"]) == String.downcase(clean_name) end) do
      nil ->
        new_group = build_new_group(groups, clean_name)
        {groups ++ [new_group], true}

      _existing ->
        {groups, false}
    end
  end

  defp build_new_group(groups, name) do
    clean_name = String.trim(name || "")
    clean_name = if clean_name == "", do: "General", else: clean_name

    order =
      case Enum.map(groups, &(&1["order"] || 0)) do
        [] -> 1
        orders -> Enum.max(orders) + 1
      end

    base_slug = generate_slug(clean_name)
    slug = if base_slug == "", do: "group-#{order}", else: base_slug

    unique_slug =
      if Enum.any?(groups, &(&1["id"] == slug)) do
        "#{slug}-#{order}"
      else
        slug
      end

    %{
      "id" => unique_slug,
      "name" => clean_name,
      "order" => order
    }
  end

  @doc """
  Sanitizes input string into a pure 40-character hex hash, removing acestream://, &pid=..., etc.
  """
  def sanitize_hash(raw) when is_binary(raw) do
    trimmed = String.trim(raw)

    case Regex.run(~r/([a-fA-F0-9]{40})/, trimmed) do
      [_, clean_hash] -> String.downcase(clean_hash)
      _ -> trimmed
    end
  end

  def sanitize_hash(other), do: to_string(other)

  @doc """
  Parses raw import text (M3U or line-by-line Content IDs) into a normalized list of channel maps.
  """
  def parse_import_text(text, default_group \\ "General", default_country \\ "")
      when is_binary(text) do
    if String.contains?(text, "#EXTINF") do
      parse_m3u_text(text, default_group, default_country)
    else
      parse_lines_text(text, default_group, default_country)
    end
  end

  @doc """
  Normalizes an individual channel parameter map.
  """
  def normalize_channel_param(params) when is_map(params) do
    name = params["name"] || params[:name] || "Unnamed Channel"
    id = params["id"] || params[:id] || generate_slug(name)
    id = if id == "", do: "channel-#{:erlang.unique_integer([:positive])}", else: id
    country = to_string(params["country"] || params[:country] || "") |> String.trim()
    group = params["group"] || params[:group] || "General"
    logo = params["logo"] || params[:logo] || ""
    source_type = params["source_type"] || params[:source_type] || "content_id"

    raw_sources =
      cond do
        is_list(params["sources"]) -> params["sources"]
        is_list(params[:sources]) -> params[:sources]
        is_binary(params["sources"]) -> String.split(params["sources"], ~r/[\s,]+/)
        is_binary(params[:sources]) -> String.split(params[:sources], ~r/[\s,]+/)
        params["source"] && params["source"] != "" -> [params["source"]]
        params[:source] && params[:source] != "" -> [params[:source]]
        params["content_id"] && params["content_id"] != "" -> [params["content_id"]]
        params[:content_id] && params[:content_id] != "" -> [params[:content_id]]
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
      "country" => country,
      "group" => group,
      "logo" => logo,
      "source_type" => source_type,
      "sources" => sources
    }
  end

  defp parse_m3u_text(text, default_group, default_country) do
    lines = String.split(text, ~r/\r?\n/)

    {channels, _} =
      Enum.reduce(lines, {[], nil}, fn raw_line, {acc, current_meta} ->
        line = String.trim(raw_line)

        cond do
          String.starts_with?(line, "#EXTINF") ->
            meta = extract_extinf_meta(line, default_group, default_country)
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
                name = meta[:name] || "AceStream Channel #{length(acc) + 1}"
                id = meta[:id] || generate_slug(name)
                first_hash = hd(hashes)
                id = if id == "", do: "channel-#{String.slice(first_hash, 0, 8)}", else: id

                ch = %{
                  "id" => id,
                  "name" => name,
                  "country" => meta[:country] || default_country,
                  "group" => meta[:group] || default_group,
                  "logo" => meta[:logo] || "",
                  "source_type" => "content_id",
                  "sources" => hashes
                }

                # Retain current_meta so consecutive stream lines under the same EXTINF merge together
                {acc ++ [ch], current_meta}

              [] ->
                {acc, current_meta}
            end
        end
      end)

    consolidate_channels(channels)
  end

  defp extract_extinf_meta(line, default_group, default_country) do
    name_from_comma =
      case Regex.run(~r/,(.+)$/, line) do
        [_, val] -> String.trim(val)
        _ -> nil
      end

    tvg_name = extract_attr(line, "tvg-name")
    raw_name = tvg_name || name_from_comma || "Imported Channel"

    {country_from_name, clean_name} = extract_country_from_bracket(raw_name)

    tvg_country = extract_attr(line, "tvg-country")
    country = tvg_country || country_from_name || default_country

    group = extract_attr(line, "group-title") || default_group
    logo = extract_attr(line, "tvg-logo") || ""
    id = extract_attr(line, "tvg-id")

    %{
      id: id,
      name: clean_name,
      country: country,
      group: group,
      logo: logo
    }
  end

  defp extract_attr(line, attr_name) do
    case Regex.run(~r/#{attr_name}="([^"]*)"/i, line) do
      [_, val] when val != "" -> val
      _ -> nil
    end
  end

  defp extract_country_from_bracket(name) do
    case Regex.run(~r/^\s*\[([A-Za-z0-9_-]{2,4})\]\s*(.+)$/, name) do
      [_, country, clean_name] -> {country, clean_name}
      _ -> {nil, name}
    end
  end

  defp parse_lines_text(text, default_group, default_country) do
    lines = String.split(text, ~r/\r?\n/)

    raw_items =
      lines
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(String.starts_with?(&1, "#") or &1 == ""))
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {line, idx} ->
        hashes =
          Regex.scan(~r/[a-fA-F0-9]{40}/, line)
          |> Enum.map(&String.downcase(hd(&1)))
          |> Enum.uniq()

        case hashes do
          [_ | _] ->
            meta = parse_line_meta(line, hashes, idx, default_group, default_country)
            [meta]

          [] ->
            []
        end
      end)

    consolidate_channels(raw_items)
  end

  defp parse_line_meta(line, hashes, idx, default_group, default_country) do
    cond do
      String.contains?(line, "|") ->
        parts = String.split(line, "|") |> Enum.map(&String.trim/1)

        other_parts =
          Enum.reject(parts, fn part ->
            tokens =
              String.split(part, ~r/[\s,]+/)
              |> Enum.reject(&(&1 == ""))

            tokens != [] and
              Enum.all?(tokens, fn token ->
                clean = sanitize_hash(token)
                clean in hashes or clean == ""
              end)
          end)

        case other_parts do
          [] ->
            build_channel_item("Channel #{idx}", hashes, default_country, default_group)

          [name] ->
            build_channel_item(name, hashes, default_country, default_group)

          [p1, p2] ->
            if String.length(p2) <= 3 and String.upcase(p2) == p2 do
              build_channel_item(p1, hashes, p2, default_group)
            else
              build_channel_item(p1, hashes, default_country, p2)
            end

          [name, country, group | _] ->
            build_channel_item(name, hashes, country, group)
        end

      String.contains?(line, "#") ->
        [_url, name] = String.split(line, "#", parts: 2)
        build_channel_item(String.trim(name), hashes, default_country, default_group)

      line =~ ~r/:\s*(?:acestream:\/\/)?/i and not String.starts_with?(line, "http") and
          not String.starts_with?(line, "acestream") ->
        [name | _] = String.split(line, ":", parts: 2)
        build_channel_item(String.trim(name), hashes, default_country, default_group)

      line =~ ~r/\s+-\s+/ ->
        [name | _] = String.split(line, ~r/\s+-\s+/, parts: 2)
        build_channel_item(String.trim(name), hashes, default_country, default_group)

      true ->
        build_channel_item("Channel #{idx}", hashes, default_country, default_group)
    end
  end

  defp build_channel_item(raw_name, hashes, country, group) do
    {country_from_name, clean_name} = extract_country_from_bracket(raw_name)

    final_country =
      if country != "" and country != nil, do: country, else: country_from_name || ""

    sources = if is_list(hashes), do: hashes, else: [hashes]
    first_hash = hd(sources)

    id = generate_slug(clean_name)
    id = if id == "", do: "channel-#{String.slice(first_hash, 0, 8)}", else: id

    %{
      "id" => id,
      "name" => clean_name,
      "country" => final_country,
      "group" => if(group != "" and group != nil, do: group, else: "General"),
      "logo" => "",
      "source_type" => "content_id",
      "sources" => sources
    }
  end

  defp consolidate_channels(channels) do
    channels
    |> Enum.reduce([], fn ch, acc ->
      case Enum.find_index(acc, fn existing -> existing["id"] == ch["id"] end) do
        nil ->
          acc ++ [ch]

        idx ->
          existing = Enum.at(acc, idx)
          merged_sources = Enum.uniq(existing["sources"] ++ ch["sources"])
          updated = Map.put(existing, "sources", merged_sources)
          List.replace_at(acc, idx, updated)
      end
    end)
  end

  defp maybe_update_field(map, field, new_val) do
    if is_binary(new_val) and String.trim(new_val) != "" and
         (Map.get(map, field) == nil or Map.get(map, field) == "" or
            Map.get(map, field) == "General") do
      Map.put(map, field, new_val)
    else
      map
    end
  end

  defp generate_slug(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^\w\s-]/u, "")
    |> String.replace(~r/[\s_-]+/, "-")
    |> String.trim("-")
  end

  defp clean_m3u_attr(nil), do: ""

  defp clean_m3u_attr(val) when is_binary(val) do
    val
    |> String.replace("\"", "")
    |> String.replace("\r", "")
    |> String.replace("\n", " ")
    |> String.trim()
  end

  defp clean_m3u_attr(val), do: to_string(val)
end
