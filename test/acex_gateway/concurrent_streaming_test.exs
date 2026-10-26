defmodule AcexGateway.ConcurrentStreamingTest do
  use ExUnit.Case, async: false

  alias AcexGateway.Stream.Broadcaster
  alias AcexGateway.Stream.ChannelBroadcaster

  setup do
    # Clear any active channels before each test
    Broadcaster.force_reset()
    :ok
  end

  test "multiple clients subscribing to the same channel share Broadcaster and RingBuffer" do
    channel_key = "shared-test-channel"

    # Start broadcaster in streaming mode
    {:ok, pid} =
      DynamicSupervisor.start_child(
        AcexGateway.StreamSupervisor,
        {ChannelBroadcaster,
         channel_key: channel_key,
         target: channel_key,
         sources: ["hash1"],
         source_type: :content_id}
      )

    # Put in streaming state manually for isolated test
    :sys.replace_state(pid, fn state ->
      %{state | status: :streaming, active_hash: "hash1"}
    end)

    # Client 1 subscribes
    assert {:ok, :joined_active_stream} = ChannelBroadcaster.subscribe(pid, self())

    info = ChannelBroadcaster.get_info(pid)
    assert info.client_count == 1

    # Dispatch a chunk
    ChannelBroadcaster.dispatch_chunk(pid, "initial_packet")

    assert_receive {:stream_chunk, "initial_packet"}

    # Client 2 subscribes later and receives RingBuffer burst
    client2 =
      spawn_link(fn ->
        receive do
          {:subscribe, caller} ->
            res = ChannelBroadcaster.subscribe(pid, self())
            send(caller, {:subscribe_result, res})
            client_loop()
        end
      end)

    send(client2, {:subscribe, self()})
    assert_receive {:subscribe_result, {:ok, :joined_active_stream}}

    # Verify client 2 received the buffered chunk
    send(client2, {:check_burst, self()})
    assert_receive {:burst_received, "initial_packet"}

    # Dispatch next chunk -> both receive it
    ChannelBroadcaster.dispatch_chunk(pid, "live_chunk_2")

    assert_receive {:stream_chunk, "live_chunk_2"}

    info = ChannelBroadcaster.get_info(pid)
    assert info.client_count == 2
  end

  test "multiple channels run concurrently without mutual disruption" do
    # Start Channel A
    {:ok, pid_a} =
      DynamicSupervisor.start_child(
        AcexGateway.StreamSupervisor,
        {ChannelBroadcaster,
         channel_key: "channel-a",
         target: "channel-a",
         sources: ["hash_a"],
         source_type: :content_id}
      )

    # Start Channel B
    {:ok, pid_b} =
      DynamicSupervisor.start_child(
        AcexGateway.StreamSupervisor,
        {ChannelBroadcaster,
         channel_key: "channel-b",
         target: "channel-b",
         sources: ["hash_b"],
         source_type: :content_id}
      )

    :sys.replace_state(pid_a, fn state -> %{state | status: :streaming, active_hash: "hash_a"} end)

    :sys.replace_state(pid_b, fn state -> %{state | status: :streaming, active_hash: "hash_b"} end)

    # Client A watches Channel A
    assert {:ok, :joined_active_stream} = ChannelBroadcaster.subscribe(pid_a, self())

    # Client B watches Channel B in separate process
    client_b =
      spawn_link(fn ->
        ChannelBroadcaster.subscribe(pid_b, self())
        client_loop()
      end)

    # Dispatch to Channel A -> Only Client A receives
    ChannelBroadcaster.dispatch_chunk(pid_a, "data_for_a")
    assert_receive {:stream_chunk, "data_for_a"}

    # Dispatch to Channel B -> Only Client B receives
    ChannelBroadcaster.dispatch_chunk(pid_b, "data_for_b")
    refute_receive {:stream_chunk, "data_for_b"}

    # Check aggregate session info
    session = Broadcaster.get_session_info()
    assert session.active_channels_count == 2
    assert session.client_count == 2
    assert is_list(session.channels)
    assert length(session.channels) == 2
    assert Map.has_key?(hd(session.channels), :channel_name)

    # Unsubscribe from Channel A -> Channel A enters cooldown, Channel B remains streaming
    ChannelBroadcaster.unsubscribe(pid_a, self())

    info_a = ChannelBroadcaster.get_info(pid_a)
    info_b = ChannelBroadcaster.get_info(pid_b)

    assert info_a.status == :cooldown
    assert info_b.status == :streaming
    assert info_b.client_count == 1

    # Cleanup
    Process.exit(client_b, :kill)
  end

  test "force_reset removes specific channel or all channels" do
    {:ok, _pid_a} =
      DynamicSupervisor.start_child(
        AcexGateway.StreamSupervisor,
        {ChannelBroadcaster,
         channel_key: "reset-a", target: "reset-a", sources: ["hash_a"], source_type: :content_id}
      )

    {:ok, pid_b} =
      DynamicSupervisor.start_child(
        AcexGateway.StreamSupervisor,
        {ChannelBroadcaster,
         channel_key: "reset-b", target: "reset-b", sources: ["hash_b"], source_type: :content_id}
      )

    assert length(Broadcaster.list_active_channels()) == 2

    # Reset only Channel A
    Broadcaster.force_reset("reset-a")

    active = Broadcaster.list_active_channels()
    assert length(active) == 1
    assert hd(active) == {"reset-b", pid_b}

    # Reset all
    Broadcaster.force_reset()
    assert Broadcaster.list_active_channels() == []
  end

  test "fast early failover auto-switches to fallback source when 0 peers detected" do
    {:ok, pid} =
      DynamicSupervisor.start_child(
        AcexGateway.StreamSupervisor,
        {ChannelBroadcaster,
         channel_key: "failover-test",
         target: "failover-test",
         sources: ["dead_hash_1", "backup_hash_2"],
         source_type: :content_id}
      )

    # Disconnect real socket to isolate test from engine
    :sys.replace_state(pid, fn state -> %{state | socket: nil, peers: 0, speed_kbps: 0} end)

    info_before = ChannelBroadcaster.get_info(pid)
    assert info_before.source_index == 0

    # Simulate early_failover_check arriving when peers == 0
    send(pid, :early_failover_check)
    :timer.sleep(50)

    info_after = ChannelBroadcaster.get_info(pid)
    assert info_after.source_index == 1
    assert info_after.total_sources == 2
  end

  test "early check keeps source if peers > 0" do
    {:ok, pid} =
      DynamicSupervisor.start_child(
        AcexGateway.StreamSupervisor,
        {ChannelBroadcaster,
         channel_key: "healthy-test",
         target: "healthy-test",
         sources: ["source_1", "source_2"],
         source_type: :content_id}
      )

    # Disconnect real socket and set peers to 5
    :sys.replace_state(pid, fn state -> %{state | socket: nil, peers: 5} end)

    # Trigger early check
    send(pid, :early_failover_check)
    :timer.sleep(50)

    info = ChannelBroadcaster.get_info(pid)
    assert info.source_index == 0
    assert info.peers == 5
  end

  # Helper client loop for testing separate process subscriptions
  defp client_loop(chunks \\ []) do
    receive do
      {:stream_chunk, chunk} ->
        client_loop([chunk | chunks])

      {:check_burst, caller} ->
        send(caller, {:burst_received, List.last(chunks)})
        client_loop(chunks)

      :stop ->
        :ok
    end
  end
end
