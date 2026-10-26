defmodule AcexGateway.Channels.Store do
  @moduledoc """
  GenServer that stores and manages the IPTV channel lineup and multi-source fallbacks.
  Persists channel configurations to a JSON file.
  """

  use GenServer
  require Logger

  @default_file "data/channels.json"

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
  Lists all configured channels.
  """
  def list_channels do
    GenServer.call(__MODULE__, :list_channels)
  end

  @doc """
  Gets a single channel by its ID.
  """
  def get_channel(id) when is_binary(id) do
    GenServer.call(__MODULE__, {:get_channel, id})
  end

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
  """
  def export_m3u(base_url, auth_opts \\ %{}) when is_binary(base_url) do
    GenServer.call(__MODULE__, {:export_m3u, base_url, auth_opts})
  end

  @doc """
  Exports channel lineup as clean pipe-delimited text (Content ID | Name | Country | Group).
  """
  def export_txt do
    GenServer.call(__MODULE__, :export_txt)
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

  # Server Callbacks

  @impl true
  def init(opts) do
    file_path =
      Keyword.get(
        opts,
        :file_path,
        Application.get_env(:acex_gateway, :channels_file) ||
          System.get_env("CHANNELS_FILE", @default_file)
      )

    channels = load_channels(file_path)
    {:ok, %{file_path: file_path, channels: channels}}
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

    # Upsert channel
    new_channels =
      case Enum.find_index(state.channels, fn c -> c["id"] == channel["id"] end) do
        nil -> state.channels ++ [channel]
        idx -> List.replace_at(state.channels, idx, channel)
      end

    new_state = %{state | channels: new_channels}
    persist_channels(new_state.file_path, new_channels)

    {:reply, {:ok, channel}, new_state}
  end

  def handle_call({:delete_channel, id}, _from, state) do
    new_channels = Enum.reject(state.channels, fn c -> c["id"] == id end)
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

      new_state = %{state | channels: new_channels}
      persist_channels(new_state.file_path, new_channels)

      {:reply, {:ok, parsed_channels}, new_state}
    end
  end

  def handle_call({:export_m3u, base_url}, from, state) do
    handle_call({:export_m3u, base_url, %{}}, from, state)
  end

  def handle_call({:export_m3u, base_url, auth_opts}, _from, state) do
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

    channel_lines =
      state.channels
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
          if has_auth do
            "#{base}/live/#{username}/#{password}/#{id}.ts"
          else
            "#{base}/live?channel=#{id}"
          end

        [inf, url]
      end)

    m3u_content = Enum.join([header] ++ channel_lines, "\n") <> "\n"
    {:reply, m3u_content, state}
  end

  def handle_call(:export_txt, _from, state) do
    lines =
      Enum.flat_map(state.channels, fn c ->
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

    txt_content = Enum.join(lines, "\n") <> "\n"
    {:reply, txt_content, state}
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
        case File.write(file_path, json) do
          :ok ->
            :ok

          {:error, reason} ->
            Logger.error(
              "[Channels.Store] Failed to write channels file '#{file_path}': #{inspect(reason)}"
            )
        end

      {:error, reason} ->
        Logger.error("[Channels.Store] Failed to serialize channels: #{inspect(reason)}")
    end
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
        params["source"] && params["source"] != "" -> [params["source"]]
        params[:source] && params[:source] != "" -> [params[:source]]
        params["content_id"] && params["content_id"] != "" -> [params["content_id"]]
        params[:content_id] && params[:content_id] != "" -> [params[:content_id]]
        true -> []
      end

    sources =
      raw_sources
      |> Enum.map(&sanitize_hash/1)
      |> Enum.reject(&(&1 == ""))

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
            case Regex.run(~r/([a-fA-F0-9]{40})/, line) do
              [_, hash] ->
                clean_hash = String.downcase(hash)
                meta = current_meta || %{}

                name = meta[:name] || "AceStream Channel #{length(acc) + 1}"
                id = meta[:id] || generate_slug(name)
                id = if id == "", do: "channel-#{String.slice(clean_hash, 0, 8)}", else: id

                ch = %{
                  "id" => id,
                  "name" => name,
                  "country" => meta[:country] || default_country,
                  "group" => meta[:group] || default_group,
                  "logo" => meta[:logo] || "",
                  "source_type" => "content_id",
                  "sources" => [clean_hash]
                }

                {acc ++ [ch], nil}

              nil ->
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
        case Regex.run(~r/([a-fA-F0-9]{40})/, line) do
          [_, hash] ->
            clean_hash = String.downcase(hash)
            meta = parse_line_meta(line, clean_hash, idx, default_group, default_country)
            [meta]

          nil ->
            []
        end
      end)

    consolidate_channels(raw_items)
  end

  defp parse_line_meta(line, clean_hash, idx, default_group, default_country) do
    cond do
      String.contains?(line, "|") ->
        parts = String.split(line, "|") |> Enum.map(&String.trim/1)
        other_parts = Enum.reject(parts, &(&1 =~ clean_hash))

        case other_parts do
          [] ->
            build_channel_item("Channel #{idx}", clean_hash, default_country, default_group)

          [name] ->
            build_channel_item(name, clean_hash, default_country, default_group)

          [p1, p2] ->
            if String.length(p2) <= 3 and String.upcase(p2) == p2 do
              build_channel_item(p1, clean_hash, p2, default_group)
            else
              build_channel_item(p1, clean_hash, default_country, p2)
            end

          [name, country, group | _] ->
            build_channel_item(name, clean_hash, country, group)
        end

      String.contains?(line, "#") ->
        [_url, name] = String.split(line, "#", parts: 2)
        build_channel_item(String.trim(name), clean_hash, default_country, default_group)

      line =~ ~r/:\s*(?:acestream:\/\/)?#{clean_hash}/i ->
        [name | _] = String.split(line, ":", parts: 2)
        build_channel_item(String.trim(name), clean_hash, default_country, default_group)

      line =~ ~r/\s+-\s+(?:acestream:\/\/)?#{clean_hash}/i ->
        [name | _] = String.split(line, ~r/\s+-\s+/, parts: 2)
        build_channel_item(String.trim(name), clean_hash, default_country, default_group)

      true ->
        build_channel_item("Channel #{idx}", clean_hash, default_country, default_group)
    end
  end

  defp build_channel_item(raw_name, hash, country, group) do
    {country_from_name, clean_name} = extract_country_from_bracket(raw_name)

    final_country =
      if country != "" and country != nil, do: country, else: country_from_name || ""

    id = generate_slug(clean_name)
    id = if id == "", do: "channel-#{String.slice(hash, 0, 8)}", else: id

    %{
      "id" => id,
      "name" => clean_name,
      "country" => final_country,
      "group" => if(group != "" and group != nil, do: group, else: "General"),
      "logo" => "",
      "source_type" => "content_id",
      "sources" => [hash]
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
