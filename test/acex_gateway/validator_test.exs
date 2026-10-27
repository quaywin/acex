defmodule AcexGateway.Engine.ValidatorTest do
  use ExUnit.Case, async: false

  alias AcexGateway.Engine.Validator
  alias AcexGateway.Channels.Store

  @valid_hash_1 "1111222233334444555566667777888899990000"
  @dead_hash_2 "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"

  setup do
    Validator.ensure_cache()
    # Clean cache table before each test
    :ets.delete_all_objects(:acex_validator_cache)
    :ok
  end

  test "validate_source rejects invalid hash length" do
    assert {:ok, res} = Validator.validate_source("too_short")
    assert res.valid == false
    assert res.error == "invalid_hash_format"
    assert res.response_time_ms == 0
  end

  test "validate_source returns cached result on subsequent calls" do
    clean = @valid_hash_1

    fake_result = %{
      source: clean,
      clean_source: clean,
      valid: true,
      infohash: "infohash_test",
      response_time_ms: 12,
      error: nil
    }

    # Manually populate cache
    expires_at = System.monotonic_time(:second) + 60
    :ets.insert(:acex_validator_cache, {clean, fake_result, expires_at})

    # Query with force: false
    assert {:ok, res} = Validator.validate_source(clean, force: false)
    assert res.valid == true
    assert res.infohash == "infohash_test"
    assert res.response_time_ms == 12

    # Query with force: true and an unreachable port bypasses cache
    assert {:error, {:connect_failed, _}} =
             Validator.validate_source(clean, force: true, port: 54321, timeout: 50)
  end

  test "validate_source with mock engine validates active and dead torrents" do
    # Start a mock TCP telnet server
    {:ok, listen_socket} =
      :gen_tcp.listen(0, [:binary, packet: :line, active: false, reuseaddr: true])

    {:ok, port} = :inet.port(listen_socket)

    # Spawn mock server process
    server_pid =
      spawn(fn ->
        mock_server_loop(listen_socket)
      end)

    # 1. Test active hash
    assert {:ok, res_alive} =
             Validator.validate_source(@valid_hash_1,
               host: "127.0.0.1",
               port: port,
               force: true,
               timeout: 1000
             )

    assert res_alive.valid == true
    assert res_alive.infohash == "aa" <> String.slice(@valid_hash_1, 2..-1//1)
    assert res_alive.error == nil

    # 2. Test dead hash
    assert {:ok, res_dead} =
             Validator.validate_source(@dead_hash_2,
               host: "127.0.0.1",
               port: port,
               force: true,
               timeout: 1000
             )

    assert res_dead.valid == false
    assert res_dead.error == "Cannot load torrent"

    # Stop server
    Process.exit(server_pid, :kill)
    :gen_tcp.close(listen_socket)
  end

  test "validate_sources validates multiple hashes concurrently" do
    # Pre-cache one alive and one dead
    alive_hash = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    dead_hash = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

    now = System.monotonic_time(:second) + 60

    :ets.insert(
      :acex_validator_cache,
      {alive_hash,
       %{
         source: alive_hash,
         clean_source: alive_hash,
         valid: true,
         infohash: "info_alive",
         response_time_ms: 5,
         error: nil
       }, now}
    )

    :ets.insert(
      :acex_validator_cache,
      {dead_hash,
       %{
         source: dead_hash,
         clean_source: dead_hash,
         valid: false,
         infohash: nil,
         response_time_ms: 5,
         error: "not_found"
       }, now}
    )

    results = Validator.validate_sources([alive_hash, dead_hash, "invalid_hash"], force: false)
    assert length(results) == 3

    alive_res = Enum.find(results, &(&1.clean_source == alive_hash))
    assert alive_res.valid == true

    dead_res = Enum.find(results, &(&1.clean_source == dead_hash))
    assert dead_res.valid == false

    invalid_res = Enum.find(results, &(&1.clean_source == "invalid_hash"))
    assert invalid_res.valid == false
    assert invalid_res.error == "invalid_hash_format"
  end

  test "validate_channel returns 404 error for non-existent channel" do
    assert {:error, :channel_not_found} = Validator.validate_channel("unknown_ch_id")
  end

  test "validate_channel aggregates alive and dead counts for existing channel" do
    ch = %{
      "id" => "val-channel-test",
      "name" => "Val Channel Test",
      "sources" => [@valid_hash_1, @dead_hash_2]
    }

    Store.save_channel(ch)

    now = System.monotonic_time(:second) + 60

    :ets.insert(
      :acex_validator_cache,
      {@valid_hash_1,
       %{
         source: @valid_hash_1,
         clean_source: @valid_hash_1,
         valid: true,
         infohash: "info_ok",
         response_time_ms: 10,
         error: nil
       }, now}
    )

    :ets.insert(
      :acex_validator_cache,
      {@dead_hash_2,
       %{
         source: @dead_hash_2,
         clean_source: @dead_hash_2,
         valid: false,
         infohash: nil,
         response_time_ms: 10,
         error: "Cannot load torrent"
       }, now}
    )

    assert {:ok, report} = Validator.validate_channel("val-channel-test", force: false)
    assert report.channel_id == "val-channel-test"
    assert report.total_sources == 2
    assert report.alive_count == 1
    assert report.dead_count == 1
    assert length(report.results) == 2

    # Cleanup
    Store.delete_channel("val-channel-test")
  end

  # Helpers for mock AceStream Telnet server
  defp mock_server_loop(listen_socket) do
    case :gen_tcp.accept(listen_socket, 2000) do
      {:ok, client} ->
        spawn(fn -> handle_mock_client(client) end)
        mock_server_loop(listen_socket)

      _ ->
        :ok
    end
  end

  defp handle_mock_client(client) do
    # 1. Expect HELLOBG
    case :gen_tcp.recv(client, 0, 1000) do
      {:ok, "HELLOBG" <> _} ->
        :gen_tcp.send(client, "HELLOTS version=3.1.74 key=mock_key http_port=6878\r\n")

        # 2. Expect READY
        case :gen_tcp.recv(client, 0, 1000) do
          {:ok, "READY " <> _} ->
            :gen_tcp.send(client, "AUTH 1 user_level=2\r\n")

            # 3. Expect LOADASYNC
            case :gen_tcp.recv(client, 0, 1000) do
              {:ok, "LOADASYNC 1 PID " <> rest} ->
                hash = String.trim(rest)

                if String.starts_with?(hash, "11112222") do
                  clean_infohash = "aa" <> String.slice(hash, 2..-1//1)

                  resp =
                    ~s(LOADRESP 1 {"status": 1, "infohash": "#{clean_infohash}", "checksum": "mock"}\r\n)

                  :gen_tcp.send(client, resp)
                else
                  resp = ~s(LOADRESP 1 {"status": 0, "error": "Cannot load torrent"}\r\n)
                  :gen_tcp.send(client, resp)
                end

              _ ->
                :ok
            end

          _ ->
            :ok
        end

      _ ->
        :ok
    end

    :gen_tcp.close(client)
  end
end
