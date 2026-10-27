# Start a lightweight mock AceStream Telnet server so tests run fully self-contained
{:ok, listen_socket} =
  :gen_tcp.listen(0, [:binary, packet: :line, active: false, reuseaddr: true])

{:ok, port} = :inet.port(listen_socket)

Application.put_env(:acex_gateway, :ace_telnet_port, port)
System.put_env("ACE_TELNET_PORT", to_string(port))

defmodule AcexGateway.Test.FakeTelnet do
  def start(listen_socket) do
    spawn_link(fn -> accept_loop(listen_socket) end)
  end

  defp accept_loop(listen_socket) do
    case :gen_tcp.accept(listen_socket) do
      {:ok, client} ->
        spawn(fn -> client_handshake(client) end)
        accept_loop(listen_socket)

      _ ->
        :ok
    end
  end

  defp client_handshake(client) do
    case :gen_tcp.recv(client, 0, 5000) do
      {:ok, _line} ->
        :gen_tcp.send(client, "HELLOTS version=3.1.74 key=fake_key http_port=6878\r\n")
        client_loop(client)

      _ ->
        :gen_tcp.close(client)
    end
  end

  defp client_loop(client) do
    case :gen_tcp.recv(client, 0) do
      {:ok, "READY " <> _} ->
        :gen_tcp.send(client, "AUTH 1 user_level=2\r\n")
        client_loop(client)

      {:ok, "LOADASYNC 1 PID " <> rest} ->
        hash = String.trim(rest)

        if String.starts_with?(hash, "11112222") do
          clean_infohash = "aa" <> String.slice(hash, 2..-1//1)

          :gen_tcp.send(
            client,
            ~s(LOADRESP 1 {"status": 1, "infohash": "#{clean_infohash}", "checksum": "mock"}\r\n)
          )
        else
          :gen_tcp.send(client, ~s(LOADRESP 1 {"status": 0, "error": "Cannot load torrent"}\r\n))
        end

        client_loop(client)

      {:ok, _line} ->
        client_loop(client)

      _ ->
        :gen_tcp.close(client)
    end
  end
end

AcexGateway.Test.FakeTelnet.start(listen_socket)

ExUnit.start()
