defmodule SnakepitDspy.MixProject do
  use Mix.Project

  def project do
    [
      app: :snakepit_dspy,
      version: "0.0.1",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      description: "DSPy adapter for Snakepit - high-performance DSPy integration",
      package: package(),
      deps: deps(),
      dialyzer: dialyzer(),
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:snakepit, github: "nshkrdotcom/snakepit"},
      {:jason, "~> 1.0"},
      {:dialyxir, "~> 1.3", only: [:dev], runtime: false},
      {:ex_doc, "~> 0.27", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      description: "DSPy adapter for Snakepit pooler",
      licenses: ["MIT"],
      maintainers: ["NSHkr <ZeroTrust@NSHkr.com>"],
      links: %{
        "GitHub" => "https://github.com/nshkrdotcom/snakepit_dspy",
        "Snakepit" => "https://github.com/nshkrdotcom/snakepit"
      },
      files: ~w(lib .formatter.exs mix.exs README* LICENSE* CHANGELOG*)
    ]
  end

  defp dialyzer do
    [
      plt_core_path: "priv/plts",
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"}
    ]
  end

  defp docs do
    [
      main: "SnakepitDspy",
      source_url: "https://github.com/nshkrdotcom/snakepit_dspy"
    ]
  end
end
