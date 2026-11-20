defmodule AcexGateway.MixProject do
  use Mix.Project

  default_version = "0.6.4"

  @version (cond do
              (v = System.get_env("ACEX_VERSION")) && v != "" ->
                String.trim_leading(String.trim(v), "v")

              (v = System.get_env("GITHUB_REF_NAME")) && v != "" ->
                String.trim_leading(String.trim(v), "v")

              true ->
                try do
                  case System.cmd("git", ["describe", "--tags", "--abbrev=0"],
                         stderr_to_stdout: true
                       ) do
                    {tag, 0} -> String.trim_leading(String.trim(tag), "v")
                    _ -> default_version
                  end
                rescue
                  _ -> default_version
                end
            end)

  def project do
    [
      app: :acex_gateway,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :runtime_tools],
      mod: {AcexGateway.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:bandit, "~> 1.6"},
      {:plug, "~> 1.16"},
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"}
    ]
  end

  defp releases do
    [
      acex_gateway: [
        include_executables_for: [:unix],
        applications: [runtime_tools: :permanent]
      ]
    ]
  end
end
