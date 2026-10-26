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
  Parses LOADRESP line to extract infohash if present in JSON.
  """
  def parse_infohash_from_loadresp(line) do
    case Regex.run(~r/"infohash"\s*:\s*"([a-fA-F0-9]{40})"/, line) do
      [_, infohash] -> {:ok, String.downcase(infohash)}
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
  Parses STATUS line to extract telemetry (peers, speed_down in KB/s, progress).
  Example: "STATUS main:dl|peers:15|speed_down:1500"
  """
  def parse_status(line) do
    line = String.trim(line)
    parts = String.split(line, "|")

    Enum.reduce(parts, %{}, fn part, acc ->
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
            {val, _} -> Map.put(acc, :progress, val)
            _ -> acc
          end

        true ->
          acc
      end
    end)
  end
end
