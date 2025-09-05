defmodule Kagi.MixProject do
  use Mix.Project

  def project do
    [
      app: :kagi,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      description: "Centralized configuration and secret management system",
      deps: deps(),
      aliases: aliases()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Kagi.Application, []}
    ]
  end

  defp deps do
    [
      {:dotenvy, "~> 1.1"},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      test: ["test --warnings-as-errors"],
      quality: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "dialyzer",
        "credo --strict"
      ]
    ]
  end
end
