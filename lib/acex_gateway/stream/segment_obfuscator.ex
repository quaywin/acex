defmodule AcexGateway.Stream.SegmentObfuscator do
  @moduledoc """
  Deterministic two-way obfuscator that transforms raw HLS segment filenames
  (e.g. `seg_1712345678_00001.ts`) into innocuous high-resolution image assets
  (e.g. `thumb_9f83a21b4e.webp`, `photo_c02e88a1.jpg`, `tile_3fa9bc12.png`).

  Key properties:
  - Deterministic: Same segment always maps to the exact same obfuscated filename,
    guaranteeing 100% Cloudflare Edge Cache HIT rates.
  - Reversible: The original segment filename is encoded directly within the asset name,
    requiring zero in-memory lookup tables or database lookups.
  - Image-Centric: Exclusively uses realistic image extensions (.webp, .jpg, .jpeg, .png, .avif)
    where 1.5MB - 3.5MB payloads and continuous pagination/infinite scrolling are standard
    behavior, completely avoiding anomaly flags triggered by oversized script/font files.
  """

  @prefixes ~w(thumb photo img avatar cover asset tile media frame preview)
  @extensions ~w(.webp .jpg .jpeg .png .avif)

  # 16-byte fixed key for reversible lightweight obfuscation
  @obf_key :crypto.hash(:md5, "acex_hls_stream_obfuscator_v1")

  @doc """
  Determines the appropriate deceptive Content-Type MIME header for an asset name.
  Defaults to "image/jpeg" or "application/octet-stream" to ensure seamless CDN masking.
  """
  def content_type_for(asset_name) when is_binary(asset_name) do
    case Path.extname(asset_name) do
      ".webp" -> "image/webp"
      ".png" -> "image/png"
      ".avif" -> "image/avif"
      ext when ext in [".jpg", ".jpeg"] -> "image/jpeg"
      _ -> "application/octet-stream"
    end
  end

  @doc """
  Obfuscates a raw segment name (e.g. "seg_1712345678_00001.ts") into a deceptive asset name.
  If the name doesn't match the standard segment pattern, it is returned unchanged.
  """
  def obfuscate(segment_name) when is_binary(segment_name) do
    case parse_raw_segment(segment_name) do
      {:ok, epoch, seq} ->
        # Pack epoch (40 bits / 5 bytes) and seq (24 bits / 3 bytes) into 8 bytes
        payload = <<epoch::unsigned-integer-40, seq::unsigned-integer-24>>
        encrypted = :crypto.crypto_one_time(:aes_128_ecb, @obf_key, payload <> <<0::64>>, true)
        token = Base.url_encode64(encrypted, padding: false)

        # Pick deterministic prefix and extension based on MD5 of segment name
        hash = :crypto.hash(:md5, segment_name)
        <<p_idx::8, e_idx::8, _rest::binary>> = hash

        prefix = Enum.at(@prefixes, rem(p_idx, length(@prefixes)))
        ext = Enum.at(@extensions, rem(e_idx, length(@extensions)))

        "#{prefix}_#{token}#{ext}"

      :error ->
        segment_name
    end
  end

  @doc """
  De-obfuscates an asset name (e.g. "avatar_xxxxxx.webp") back to its original raw segment name
  (e.g. "seg_1712345678_00001.ts"). If the input is already a raw segment name or cannot be
  decoded, it returns the input unchanged or an error.
  """
  def deobfuscate(asset_name) when is_binary(asset_name) do
    clean_name = Path.basename(asset_name)

    cond do
      # Already raw segment format
      String.starts_with?(clean_name, "seg_") and String.ends_with?(clean_name, ".ts") ->
        clean_name

      true ->
        case extract_token(clean_name) do
          {:ok, token} ->
            case decode_token(token) do
              {:ok, epoch, seq} ->
                seq_str = String.pad_leading(to_string(seq), 5, "0")
                "seg_#{epoch}_#{seq_str}.ts"

              _ ->
                clean_name
            end

          :error ->
            clean_name
        end
    end
  end

  @doc """
  Obfuscates all segment filenames present within an HLS playlist manifest (.m3u8).
  Converts raw .ts segment filenames to deterministic deceptive image asset paths.
  """
  def obfuscate_manifest(manifest_content) when is_binary(manifest_content) do
    manifest_content
    |> String.split(["\r\n", "\n"])
    |> Enum.map(&obfuscate_manifest_line/1)
    |> Enum.join("\n")
  end

  defp obfuscate_manifest_line(line) do
    trimmed = String.trim(line)

    cond do
      String.starts_with?(trimmed, "#") ->
        line

      String.ends_with?(trimmed, ".ts") ->
        # May be relative path, e.g. /cast/target/seg_xxx.ts or seg_xxx.ts
        dir = Path.dirname(line)
        base = Path.basename(line)
        obfuscated = obfuscate(base)

        if dir == "." do
          obfuscated
        else
          Path.join(dir, obfuscated)
        end

      true ->
        line
    end
  end

  defp parse_raw_segment(name) do
    # Matches seg_<epoch>_<seq>.ts
    case Regex.run(~r/^seg_(\d+)_(\d+)\.ts$/, name) do
      [_, epoch_str, seq_str] ->
        {epoch, _} = Integer.parse(epoch_str)
        {seq, _} = Integer.parse(seq_str)
        {:ok, epoch, seq}

      _ ->
        :error
    end
  end

  defp extract_token(name) do
    # Name format: <prefix>_<token>.<ext>
    case Regex.run(~r/^[a-z]+_([A-Za-z0-9_-]+)\.[a-z0-9]+$/, name) do
      [_, token] -> {:ok, token}
      _ -> :error
    end
  end

  defp decode_token(token) do
    case Base.url_decode64(token, padding: false) do
      {:ok, encrypted} when byte_size(encrypted) == 16 ->
        case :crypto.crypto_one_time(:aes_128_ecb, @obf_key, encrypted, false) do
          <<epoch::unsigned-integer-40, seq::unsigned-integer-24, 0::64>> ->
            {:ok, epoch, seq}

          _ ->
            :error
        end

      _ ->
        :error
    end
  rescue
    _ -> :error
  end
end
