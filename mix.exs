defmodule Ecto.DevLogger.MixProject do
  use Mix.Project
  @version "0.5.0"
  @source_url "https://github.com/fuelen/ecto_dev_logger"

  def project do
    [
      app: :ecto_dev_logger,
      version: @version,
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      description: "An alternative Ecto logger for development",
      package: package(),
      deps: deps(),
      docs: [
        formatters: ["html"],
        main: "readme",
        extras: ["README.md": [title: "README"]],
        source_url: @source_url,
        source_ref: "v#{@version}",
        assets: "assets"
      ]
    ]
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{
        GitHub: @source_url
      }
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:ecto, "~> 3.7"},
      {:ecto_sql, "~> 3.7", only: :test},
      {:postgrex, "~> 0.16", only: :test},
      {:jason, "~> 1.0"},
      {:ex_doc, "~> 0.28", only: :dev, runtime: false}
    ]
  end
end
