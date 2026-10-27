defmodule AcexGateway.Stream.Broadcaster do
  @moduledoc """
  High-level coordinator facade for multi-channel streaming.
  Discovers and supervises isolated `ChannelBroadcaster` processes via
  `AcexGateway.ChannelRegistry` and `AcexGateway.StreamSupervisor`.
  """

  require Logger

  alias AcexGateway.Channels.Store
  alias AcexGateway.Stream.ChannelBroadcaster

  @registry AcexGateway.ChannelRegistry
  @supervisor AcexGateway.StreamSupervisor

  @doc """
  Subscribes a client to the specified stream target.
  Resolves the canonical channel and returns `{:ok, channel_broadcaster_pid}`.
  """
  def subscribe(target, source_type \\ :content_id, timeout \\ 70_000) do
    {channel_key, sources, resolved_type, channel_name} = resolve_sources(target, source_type)

    case get_or_start_broadcaster(channel_key, target, sources, resolved_type, channel_name) do
      {:ok, pid} ->
        case ChannelBroadcaster.subscribe(pid, self(), timeout) do
          {:ok, _status} ->
            {:ok, pid}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Unsubscribes a client PID from a specific channel broadcaster, or from all active channels.
  """
  def unsubscribe(pid) when is_pid(pid) do
    # Fallback: unsubscribe client PID from all active channels
    for {_key, broadcaster_pid} <- list_active_channels() do
      ChannelBroadcaster.unsubscribe(broadcaster_pid, pid)
    end
  end

  def unsubscribe(channel_broadcaster_pid, client_pid)
      when is_pid(channel_broadcaster_pid) and is_pid(client_pid) do
    ChannelBroadcaster.unsubscribe(channel_broadcaster_pid, client_pid)
  end

  @doc """
  Returns a list of all active `{channel_key, pid}` pairs from the registry.
  """
  def list_active_channels do
    Registry.select(@registry, [{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}])
  end

  @doc """
  Aggregates session information across all active channels for `/stat`.
  Maintains backward compatibility with single-channel clients.
  """
  def get_session_info do
    active = list_active_channels()

    channel_stats =
      Enum.map(active, fn {_key, pid} ->
        try do
          ChannelBroadcaster.get_info(pid)
        catch
          :exit, _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    active_count = length(channel_stats)

    total_clients = Enum.sum(Enum.map(channel_stats, & &1.client_count))
    total_bytes = Enum.sum(Enum.map(channel_stats, & &1.bytes_transferred))
    total_buffered = Enum.sum(Enum.map(channel_stats, & &1.buffered_bytes))
    max_peers = Enum.reduce(channel_stats, 0, fn c, acc -> max(c.peers, acc) end)
    total_speed = Enum.sum(Enum.map(channel_stats, & &1.speed_kbps))

    # Overall system status
    status =
      cond do
        active_count == 0 ->
          :idle

        Enum.any?(channel_stats, &(&1.status == :streaming)) ->
          :streaming

        Enum.any?(channel_stats, &(&1.status == :starting)) ->
          :starting

        true ->
          :cooldown
      end

    first = List.first(channel_stats)

    %{
      status: status,
      active_target: if(first, do: first.target, else: nil),
      active_channel: if(first, do: first.active_channel, else: nil),
      active_channel_name:
        if(first, do: Map.get(first, :channel_name) || first.active_channel, else: nil),
      source_type: if(first, do: first.source_type, else: :content_id),
      client_count: total_clients,
      bytes_transferred: total_bytes,
      buffered_bytes: total_buffered,
      source_index: if(first, do: first.source_index, else: 0),
      total_sources: if(first, do: first.total_sources, else: 0),
      peers: max_peers,
      speed_kbps: total_speed,
      progress: if(first, do: Map.get(first, :progress, 0), else: 0),
      engine_state: if(first, do: Map.get(first, :engine_state, :idle), else: :idle),
      active_channels_count: active_count,
      channels: channel_stats
    }
  end

  @doc """
  Terminates one or all active stream broadcasters.
  """
  def force_reset(channel_key \\ nil) do
    if channel_key do
      candidates = [channel_key, "content_id:#{channel_key}"]

      pids =
        Enum.flat_map(candidates, fn key ->
          case Registry.lookup(@registry, key) do
            [{pid, _}] -> [pid]
            [] -> []
          end
        end)
        |> Enum.uniq()

      for pid <- pids do
        try do
          ChannelBroadcaster.force_stop(pid)
        catch
          :exit, _ -> :ok
        end

        DynamicSupervisor.terminate_child(@supervisor, pid)
      end

      :ok
    else
      for {_key, pid} <- list_active_channels() do
        try do
          ChannelBroadcaster.force_stop(pid)
        catch
          :exit, _ -> :ok
        end

        DynamicSupervisor.terminate_child(@supervisor, pid)
      end

      :ok
    end
  end

  # Helper Functions

  defp get_or_start_broadcaster(channel_key, target, sources, resolved_type, channel_name) do
    case Registry.lookup(@registry, channel_key) do
      [{pid, _}] ->
        {:ok, pid}

      [] ->
        case ensure_channel_slot() do
          :ok ->
            spec = {
              ChannelBroadcaster,
              channel_key: channel_key,
              target: target,
              sources: sources,
              source_type: resolved_type,
              channel_name: channel_name
            }

            case DynamicSupervisor.start_child(@supervisor, spec) do
              {:ok, pid} ->
                {:ok, pid}

              {:error, {:already_started, pid}} ->
                {:ok, pid}

              {:error, reason} ->
                Logger.error(
                  "[Broadcaster] Failed to start channel #{channel_key}: #{inspect(reason)}"
                )

                {:error, reason}
            end

          {:error, :max_channels_reached} = err ->
            err
        end
    end
  end

  defp ensure_channel_slot do
    max_limit = AcexGateway.Config.max_active_channels()
    active_channels = list_active_channels()

    if length(active_channels) < max_limit do
      :ok
    else
      # Check if any active channel is idle / in cooldown (0 consumers)
      cooldown_channel =
        Enum.find_value(active_channels, fn {key, pid} ->
          try do
            info = ChannelBroadcaster.get_info(pid)

            if info.client_count == 0 or info.status == :cooldown do
              {key, pid}
            else
              nil
            end
          catch
            :exit, _ -> {key, pid}
          end
        end)

      case cooldown_channel do
        {cooldown_key, cooldown_pid} ->
          Logger.info(
            "[Broadcaster] Evicting idle/cooldown channel #{cooldown_key} to free slot for new stream."
          )

          try do
            ChannelBroadcaster.force_stop(cooldown_pid)
          catch
            :exit, _ -> :ok
          end

          DynamicSupervisor.terminate_child(@supervisor, cooldown_pid)
          :ok

        nil ->
          {:error, :max_channels_reached}
      end
    end
  end

  def resolve_sources(target, source_type) do
    cond do
      source_type == :channel ->
        case Store.get_channel(target) do
          nil ->
            {target, [target], :content_id, target}

          channel ->
            sources = channel["sources"] || []
            name = channel["name"] || channel["id"]
            {channel["id"], sources, :content_id, name}
        end

      true ->
        clean_target = Store.sanitize_hash(target)

        case Store.find_channel_by_source(clean_target) do
          nil ->
            key = "content_id:#{clean_target}"
            name = "Direct Stream (#{String.slice(clean_target, 0, 8)}...)"
            {key, [clean_target], :content_id, name}

          channel ->
            name = channel["name"] || channel["id"]
            {channel["id"], channel["sources"] || [clean_target], :content_id, name}
        end
    end
  end
end
