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

  test "concurrency limiter enforces max_active_channels and evicts cooldown channels" do
    alias AcexGateway.Settings.Store, as: SettingsStore
    alias AcexGateway.Stream.Broadcaster

    # Set limit to 2 channels
    SettingsStore.update_settings(%{"max_active_channels" => 2})

    on_exit(fn ->
      SettingsStore.update_settings(%{"max_active_channels" => 5})
      Broadcaster.force_reset()
    end)

    # Start Channel 1 with 1 active consumer
    {:ok, pid1} =
      DynamicSupervisor.start_child(
        AcexGateway.StreamSupervisor,
        {ChannelBroadcaster,
         channel_key: "slot-ch-1",
         target: "slot-ch-1",
         sources: ["hash_1"],
         source_type: :content_id}
      )

    :sys.replace_state(pid1, fn state ->
      ref = Process.monitor(self())
      %{state | status: :streaming, consumers: %{self() => ref}}
    end)

    # Start Channel 2 with 1 active consumer
    {:ok, pid2} =
      DynamicSupervisor.start_child(
        AcexGateway.StreamSupervisor,
        {ChannelBroadcaster,
         channel_key: "slot-ch-2",
         target: "slot-ch-2",
         sources: ["hash_2"],
         source_type: :content_id}
      )

    :sys.replace_state(pid2, fn state ->
      ref = Process.monitor(self())
      %{state | status: :streaming, consumers: %{self() => ref}}
    end)

    # Attempting to start channel 3 while slots are full (both active) must return :max_channels_reached
    assert {:error, :max_channels_reached} = Broadcaster.subscribe("slot-ch-3", :content_id)

    # Put channel 2 in cooldown (0 consumers)
    :sys.replace_state(pid2, fn state ->
      %{state | status: :cooldown, consumers: %{}}
    end)

    # Set limit back to 5 for general tests
    SettingsStore.update_settings(%{"max_active_channels" => 5})
  end

  test "instant error failover occurs immediately when engine reports STATE 6" do
    {:ok, pid} =
      DynamicSupervisor.start_child(
        AcexGateway.StreamSupervisor,
        {ChannelBroadcaster,
         channel_key: "state-failover-test",
         target: "state-failover-test",
         sources: ["bad_hash_1", "good_hash_2"],
         source_type: :content_id}
      )

    # Disconnect real socket to test isolated telnet line processing
    mock_socket = :mock_socket
    :sys.replace_state(pid, fn state -> %{state | socket: mock_socket} end)

    info_before = ChannelBroadcaster.get_info(pid)
    assert info_before.source_index == 0

    # Simulate STATE 6 (Fatal engine error) arriving from engine
    send(pid, {:tcp, mock_socket, "STATE 6\r\n"})
    :timer.sleep(50)

    info_after = ChannelBroadcaster.get_info(pid)
    assert info_after.source_index == 1
    assert info_after.total_sources == 2
  end

  test "STATUS prebuf updates progress and engine_state in ChannelBroadcaster" do
    {:ok, pid} =
      DynamicSupervisor.start_child(
        AcexGateway.StreamSupervisor,
        {ChannelBroadcaster,
         channel_key: "telemetry-test",
         target: "telemetry-test",
         sources: ["hash_telemetry"],
         source_type: :content_id}
      )

    mock_socket = :mock_socket
    :sys.replace_state(pid, fn state -> %{state | socket: mock_socket} end)

    # Simulate STATUS main:prebuf|72|6|20 line
    send(pid, {:tcp, mock_socket, "STATUS main:prebuf|72|6|20\r\n"})
    :timer.sleep(50)

    info = ChannelBroadcaster.get_info(pid)
    assert info.progress == 72
    assert info.peers == 6
    assert info.engine_state == :prebuf
  end

  test "seamless mid-stream failover switches to backup source without disconnecting consumers" do
    {:ok, pid} =
      DynamicSupervisor.start_child(
        AcexGateway.StreamSupervisor,
        {ChannelBroadcaster,
         channel_key: "midstream-failover-test",
         target: "midstream-failover-test",
         sources: ["src_a", "src_b"],
         source_type: :content_id}
      )

    mock_socket = :mock_socket

    # Put into streaming state with src_a
    :sys.replace_state(pid, fn state ->
      %{state | status: :streaming, active_hash: "src_a", socket: mock_socket}
    end)

    # Client subscribes
    assert {:ok, :joined_active_stream} = ChannelBroadcaster.subscribe(pid, self())

    info = ChannelBroadcaster.get_info(pid)
    assert info.client_count == 1
    assert info.source_index == 0

    # Simulate upstream failure (e.g. source A dropped mid-stream)
    send(pid, {:upstream_completed, :connection_reset})
    :timer.sleep(50)

    # Client MUST NOT receive stream_closed message
    refute_receive {:stream_closed, _}

    # Broadcaster should now be starting source B
    info_during_failover = ChannelBroadcaster.get_info(pid)
    assert info_during_failover.status == :starting
    assert info_during_failover.source_index == 1
    assert info_during_failover.client_count == 1

    # Simulate START url arriving for source B
    send(
      pid,
      {:tcp, mock_socket,
       "START url=http%3A%2F%2F127.0.0.1%3A6878%2Face%2Fgetstream%3Fid%3Dsource_b\r\n"}
    )

    :timer.sleep(50)

    info_recovered = ChannelBroadcaster.get_info(pid)
    assert info_recovered.status == :streaming
    assert info_recovered.active_channel == "src_b"
    assert info_recovered.client_count == 1

    # Dispatch data from source B -> existing client receives it!
    ChannelBroadcaster.dispatch_chunk(pid, "new_packets_from_src_b")
    assert_receive {:stream_chunk, "new_packets_from_src_b"}
  end

  test "smart source auto-promotion reorders sources when fallback source successfully streams" do
    alias AcexGateway.Channels.Store

    # Save a test channel with multiple sources
    Store.save_channel(%{
      "id" => "auto-promo-test",
      "name" => "Auto Promo Test",
      "sources" => ["fallback_src_1", "fallback_src_2"]
    })

    {:ok, pid} =
      DynamicSupervisor.start_child(
        AcexGateway.StreamSupervisor,
        {ChannelBroadcaster,
         channel_key: "auto-promo-test",
         target: "auto-promo-test",
         sources: ["fallback_src_1", "fallback_src_2"],
         source_type: :content_id}
      )

    # Put into streaming state simulating failover to fallback_src_2 (index 1)
    :sys.replace_state(pid, fn state ->
      %{state | status: :streaming, active_hash: "fallback_src_2", source_index: 1}
    end)

    # Dispatch first chunk
    ChannelBroadcaster.dispatch_chunk(pid, "healthy_ts_packets")

    # Verify Broadcaster reordered its in-memory sources
    info = ChannelBroadcaster.get_info(pid)
    assert info.source_index == 0

    # Verify Store has promoted fallback_src_2 to index 0
    updated_channel = Store.get_channel("auto-promo-test")
    assert hd(updated_channel["sources"]) == "fallback_src_2"

    Store.delete_channel("auto-promo-test")
  end

  test "bounded failover allows at most 1 wrap-around cycle before terminating stream" do
    {:ok, pid} =
      DynamicSupervisor.start_child(
        AcexGateway.StreamSupervisor,
        {ChannelBroadcaster,
         channel_key: "bounded-failover-test",
         target: "bounded-failover-test",
         sources: ["src_1", "src_2"],
         source_type: :content_id}
      )

    mock_socket = :mock_socket

    # Put into streaming on src_2 (index 1, cycle 0)
    :sys.replace_state(pid, fn state ->
      %{
        state
        | status: :streaming,
          active_hash: "src_2",
          source_index: 1,
          cycle_count: 0,
          socket: mock_socket
      }
    end)

    assert {:ok, :joined_active_stream} = ChannelBroadcaster.subscribe(pid, self())

    # 1st drop at end of source list -> triggers wrap-around to index 0 with cycle_count 1
    send(pid, {:upstream_completed, :network_drop_1})
    :timer.sleep(50)

    refute_receive {:stream_closed, _}
    info1 = ChannelBroadcaster.get_info(pid)
    assert info1.source_index == 0

    # 2nd drop: advance from index 0 to index 1 (cycle_count 1)
    send(pid, {:upstream_completed, :network_drop_2})
    :timer.sleep(50)

    refute_receive {:stream_closed, _}
    info2 = ChannelBroadcaster.get_info(pid)
    assert info2.source_index == 1

    # 3rd drop: reaches end of list again with cycle_count == 1 -> MUST terminate, no infinite loop!
    send(pid, {:upstream_completed, :network_drop_3})
    :timer.sleep(50)

    assert_receive {:stream_closed, :network_drop_3}
  end

  test "LOADRESP error triggers instant fast failover to next source" do
    {:ok, pid} =
      DynamicSupervisor.start_child(
        AcexGateway.StreamSupervisor,
        {ChannelBroadcaster,
         channel_key: "loadresp-failover-test",
         target: "loadresp-failover-test",
         sources: ["bad_load_src", "good_load_src"],
         source_type: :content_id}
      )

    mock_socket = :mock_socket
    :sys.replace_state(pid, fn state -> %{state | socket: mock_socket} end)

    assert ChannelBroadcaster.get_info(pid).source_index == 0

    # Simulate LOADRESP returning error from engine
    send(
      pid,
      {:tcp, mock_socket, ~s(LOADRESP 0 {"status": 0, "error": "Cannot load torrent"}\r\n)}
    )

    :timer.sleep(50)

    # Must immediately prune bad source and advance to good_load_src
    info = ChannelBroadcaster.get_info(pid)
    assert info.total_sources == 1
    assert info.source_index == 0
    state = :sys.get_state(pid)
    assert state.sources == ["good_load_src"]
  end

  test "STATUS main:error triggers instant fast failover to next source" do
    {:ok, pid} =
      DynamicSupervisor.start_child(
        AcexGateway.StreamSupervisor,
        {ChannelBroadcaster,
         channel_key: "status-error-failover-test",
         target: "status-error-failover-test",
         sources: ["err_src_1", "err_src_2"],
         source_type: :content_id}
      )

    mock_socket = :mock_socket
    :sys.replace_state(pid, fn state -> %{state | socket: mock_socket} end)

    assert ChannelBroadcaster.get_info(pid).source_index == 0

    # Simulate STATUS main:error arriving from engine
    send(pid, {:tcp, mock_socket, "STATUS main:error|failed_tracker\r\n"})
    :timer.sleep(50)

    # Must immediately advance to source 1
    assert ChannelBroadcaster.get_info(pid).source_index == 1
  end

  # Helper client loop for testing separate process subscriptions
  defp client_loop(chunks \\ []) do
    receive do
      {:stream_burst, burst_chunks} ->
        client_loop(Enum.reverse(burst_chunks) ++ chunks)

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
