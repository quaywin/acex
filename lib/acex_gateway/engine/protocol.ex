defmodule AcexGateway.Engine.Protocol do
  @moduledoc """
  Pure helper functions for encoding and decoding the AceStream Telnet protocol.
  """

  @default_product_key "n51LvQoTlJzNGaFxseRK-uvnvX-sD4Vm5Axwmc4UcoD-jruxmKsuJaH0eVgE"

  @doc """
  Computes the READY key for AceStream authentication.
  Formula: <prefix>-<sha1(req_key + product_key)>
  """
  def compute_ready_key(req_key, product_key \\ @default_product_key) do
    sha1 =
      :crypto.hash(:sha, "#{req_key}#{product_key}")
      |> Base.encode16(case: :lower)

    prefix = hd(String.split(product_key, "-"))
    "#{prefix}-#{sha1}"
  end

  @doc """
  Parses HELLOTS message line to extract key and http_port.
  Example: "HELLOTS version=3.1.74 key=abcdef http_port=6878"
  """
  def parse_hellots(line) do
    parts = String.split(String.trim(line), " ")

    key =
      Enum.find_value(parts, fn part ->
        if String.starts_with?(part, "key="), do: String.replace_prefix(part, "key=", "")
      end)

    http_port =
      Enum.find_value(parts, fn part ->
        if String.starts_with?(part, "http_port=") do
          case Integer.parse(String.replace_prefix(part, "http_port=", "")) do
            {port, _} -> port
            :error -> nil
          end
        end
      end)

    %{key: key, http_port: http_port || 6878}
  end

  @doc """
  Parses LOADRESP line to extract infohash or explicit engine error.
  """
  def parse_loadresp(line) do
    cond do
      match = Regex.run(~r/"infohash"\s*:\s*"([a-fA-F0-9]{40})"/, line) ->
        [_, infohash] = match
        {:ok, String.downcase(infohash)}

      match = Regex.run(~r/"error"\s*:\s*"([^"]+)"/, line) ->
        [_, err] = match
        {:error, err}

      String.contains?(line, "\"status\": 0") or String.contains?(line, "\"status\":0") ->
        {:error, "cannot_load_torrent"}

      true ->
        :none
    end
  end

  @doc """
  Parses LOADRESP line to extract infohash if present in JSON.
  """
  def parse_infohash_from_loadresp(line) do
    case parse_loadresp(line) do
      {:ok, infohash} -> {:ok, infohash}
      _ -> :none
    end
  end

  @doc """
  Parses START response line to extract the playback URL.
  Example: "START url=http%3A%2F%2F127.0.0.1%3A6878%2Face%2Fgetstream%3Fid%3D123"
  """
  def parse_start_url(line) do
    parts = String.split(String.trim(line), " ")

    url_encoded =
      Enum.find_value(parts, fn part ->
        if String.starts_with?(part, "url="), do: String.replace_prefix(part, "url=", "")
      end)

    if url_encoded do
      {:ok, URI.decode(url_encoded)}
    else
      :error
    end
  end

  @doc """
  Parses STATE message line from AceStream Engine.
  Format: "STATE <id>" where:
  0 = idle
  1 = prebuffering
  2 = downloading
  3 = buffering
  4 = completed
  5 = checking
  6 = error

  Returns:
  - {:ok, state_atom, code} for normal states (0..5)
  - {:error, :engine_error, 6} for fatal error (6)
  """
  def parse_state("STATE " <> rest) do
    code_str = hd(String.split(String.trim(rest), " "))

    case Integer.parse(code_str) do
      {0, _} -> {:ok, :idle, 0}
      {1, _} -> {:ok, :prebuf, 1}
      {2, _} -> {:ok, :downloading, 2}
      {3, _} -> {:ok, :buffering, 3}
      {4, _} -> {:ok, :completed, 4}
      {5, _} -> {:ok, :checking, 5}
      {6, _} -> {:error, :engine_error, 6}
      {other, _} -> {:ok, :unknown, other}
      :error -> :error
    end
  end

  def parse_state(_), do: :error

  @doc """
  Parses STATUS line to extract telemetry (peers, speed_down in KB/s, progress, engine_state).
  Supports both key-value format ("STATUS main:dl|peers:15|speed_down:1500")
  and positional prebuffer format ("STATUS main:prebuf|55|4|10").
  """
  def parse_status(line) do
    line = String.trim(line)
    clean_line = String.replace_prefix(line, "STATUS ", "")
    parts = String.split(clean_line, "|")

    # First part contains "main:<substate>" or "<substate>"
    first_part = hd(parts)
    tail_parts = tl(parts)

    substate =
      cond do
        String.starts_with?(first_part, "main:") ->
          case String.replace_prefix(first_part, "main:", "") do
            "prebuf" -> :prebuf
            "dl" -> :downloading
            "buf" -> :buffering
            "check" -> :checking
            "idle" -> :idle
            "error" -> :error
            "wait" -> :waiting
            "starting" -> :starting
            "stopping" -> :stopping
            _other -> :unknown
          end

        true ->
          nil
      end

    initial_acc = if substate, do: %{engine_state: substate}, else: %{}

    # Check for positional parameters when substate is prebuf, buffering, or checking
    initial_acc =
      if substate in [:prebuf, :buffering, :checking] and tail_parts != [] do
        parse_positional_status(substate, tail_parts, initial_acc)
      else
        initial_acc
      end

    # Parse key-value parts
    Enum.reduce(tail_parts, initial_acc, fn part, acc ->
      cond do
        String.starts_with?(part, "peers:") ->
          case Integer.parse(String.replace_prefix(part, "peers:", "")) do
            {val, _} -> Map.put(acc, :peers, val)
            _ -> acc
          end

        String.starts_with?(part, "speed_down:") ->
          case Integer.parse(String.replace_prefix(part, "speed_down:", "")) do
            {val, _} -> Map.put(acc, :speed_kbps, val)
            _ -> acc
          end

        String.starts_with?(part, "progress:") ->
          case Float.parse(String.replace_prefix(part, "progress:", "")) do
            {val, _} ->
              Map.put(acc, :progress, val)

            :error ->
              case Integer.parse(String.replace_prefix(part, "progress:", "")) do
                {val, _} -> Map.put(acc, :progress, val)
                _ -> acc
              end
          end

        true ->
          acc
      end
    end)
  end

  defp parse_positional_status(:prebuf, [progress_str | rest], acc) do
    acc =
      case Integer.parse(progress_str) do
        {val, ""} -> Map.put(acc, :progress, val)
        _ -> acc
      end

    case rest do
      [peers_str | _] ->
        case Integer.parse(peers_str) do
          {peers, ""} -> Map.put_new(acc, :peers, peers)
          _ -> acc
        end

      _ ->
        acc
    end
  end

  defp parse_positional_status(substate, [progress_str | _], acc)
       when substate in [:buffering, :checking] do
    case Integer.parse(progress_str) do
      {val, ""} -> Map.put(acc, :progress, val)
      _ -> acc
    end
  end

  defp parse_positional_status(_, _, acc), do: acc
end
