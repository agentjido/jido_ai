defmodule Kagi.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :kagi,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),

      # Docs
      name: "Kagi",
      description: "Easy access to LLM API keys and environment configuration",
      source_url: "https://github.com/agentjido/kagi",
      homepage_url: "https://github.com/agentjido/kagi",
      package: package(),
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :telemetry],
      mod: {Kagi.Application, []}
    ]
  end

  defp deps do
    [
      {:dotenvy, "~> 1.1"},
      {:splode, "~> 0.2"},
      {:telemetry, "~> 1.0"},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:doctor, "~> 0.22", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README.md", "LICENSE", "AGENTS.md", "usage-rules.md"],
      maintainers: ["Mike Hostetler"],
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => "https://github.com/agentjido/kagi"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: "https://github.com/agentjido/kagi",
      authors: ["Mike Hostetler <mike.hostetler@gmail.com>"],
      extras: [
        {"README.md", title: "Home"},
        {"AGENTS.md", title: "Development Guide"},
        {"usage-rules.md", title: "Usage Rules"},
        {"LICENSE", title: "Apache 2.0 License"}
      ]
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
