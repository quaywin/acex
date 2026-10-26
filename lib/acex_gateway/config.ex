defmodule AcexGateway.Config do
  @moduledoc """
  Configuration management for AcexGateway, supporting environment variables.
  """

  @default_product_key "n51LvQoTlJzNGaFxseRK-uvnvX-sD4Vm5Axwmc4UcoD-jruxmKsuJaH0eVgE"
  @default_test_channel "dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c"

  def product_key do
    System.get_env("ACE_PRODUCT_KEY", @default_product_key)
  end

  def telnet_host do
    System.get_env("ACE_TELNET_HOST", "127.0.0.1")
  end

  def telnet_port do
    case System.get_env("ACE_TELNET_PORT") do
      nil -> 62062
      val -> String.to_integer(val)
    end
  end

  def http_port do
    case System.get_env("ACE_HTTP_PORT") do
      nil -> 6878
      val -> String.to_integer(val)
    end
  end

  def proxy_port do
    case Application.get_env(:acex_gateway, :port) do
      port when is_integer(port) ->
        port

      _ ->
        port_str = System.get_env("PORT") || System.get_env("ACE_PROXY_PORT") || "8686"
        String.to_integer(port_str)
    end
  end

  def grace_period_ms do
    case System.get_env("GRACE_PERIOD_MS") do
      nil -> 5000
      val -> String.to_integer(val)
    end
  end

  def start_timeout_ms do
    case System.get_env("ACE_START_TIMEOUT_MS") do
      nil -> 60_000
      val -> String.to_integer(val)
    end
  end

  def early_failover_timeout_ms do
    case System.get_env("ACE_EARLY_FAILOVER_TIMEOUT_MS") do
      nil -> 10_000
      val -> String.to_integer(val)
    end
  end

  def default_channel_id do
    System.get_env("DEFAULT_CHANNEL_ID", @default_test_channel)
  end

  def epg_url do
    System.get_env("EPG_URL", "")
  end

  def auth_username do
    System.get_env("AUTH_USERNAME", "")
  end

  def auth_password do
    System.get_env("AUTH_PASSWORD", "")
  end

  def auth_enabled? do
    user = auth_username()
    pass = auth_password()
    is_binary(user) and is_binary(pass) and String.trim(user) != "" and String.trim(pass) != ""
  end

  def authenticate?(username, password) do
    if auth_enabled?() do
      username == auth_username() and password == auth_password()
    else
      true
    end
  end
end
