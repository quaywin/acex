defmodule AcexGateway do
  @moduledoc """
  AcexGateway - High-Performance 0-Transcode Headless Stream Gateway for AceStream in Elixir/OTP.
  """

  @default_version Mix.Project.config()[:version] || "0.6.4"

  def version do
    System.get_env("APP_VERSION") || read_version_from_git() || @default_version
  end

  defp read_version_from_git do
    case System.cmd("git", ["describe", "--tags", "--abbrev=0"], stderr_to_stdout: true) do
      {tag, 0} ->
        tag |> String.trim() |> String.trim_leading("v")

      _ ->
        nil
    end
  rescue
    _ -> nil
  end
end
