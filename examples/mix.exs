defmodule JidoAiExamples.MixProject do
  use Mix.Project

  def project do
    [
      app: :jido_ai_examples,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:jido_ai, path: ".."},
      {:jido, "~> 2.0"},
      {:jido_action, "~> 2.0"},
      {:dotenvy, "~> 1.1"},
      {:req, "~> 0.5"},
      {:tentacat, "~> 2.5"},
      {:jido_browser, "~> 1.0", only: [:dev, :test], runtime: false},
      {:mimic, "~> 2.0", only: :test}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get"],
      test: "test --exclude flaky"
    ]
  end
end
