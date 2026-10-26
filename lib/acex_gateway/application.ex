defmodule AcexGateway.Application do
  @moduledoc false

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    port = AcexGateway.Config.proxy_port()
    Logger.info("[Application] Starting AcexGateway on port #{port}...")

    children = [
      AcexGateway.Channels.Store,
      AcexGateway.Engine.TelnetClient,
      {Registry, keys: :unique, name: AcexGateway.ChannelRegistry},
      {DynamicSupervisor, strategy: :one_for_one, name: AcexGateway.StreamSupervisor},
      {Bandit, plug: AcexGateway.Web.Router, scheme: :http, port: port}
    ]

    opts = [strategy: :one_for_one, name: AcexGateway.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
