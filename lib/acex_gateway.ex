defmodule AcexGateway do
  @moduledoc """
  AcexGateway - High-Performance 0-Transcode Headless Stream Gateway for AceStream in Elixir/OTP.
  """

  @default_version Mix.Project.config()[:version] || "0.1.0"

  def version do
    System.get_env("APP_VERSION") || @default_version
  end
end
