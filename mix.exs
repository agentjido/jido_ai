defmodule JidoKeys.MixProject do
  use Mix.Project

  @version "1.0.0"

  def project do
    [
      app: :jido_keys,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.github": :test,
        "coveralls.json": :test
      ],

      # Docs
      name: "Jido Keys",
      description: "Easy access to LLM API keys and environment configuration",
      source_url: "https://github.com/agentjido/jido_keys",
      homepage_url: "https://github.com/agentjido/jido_keys",
      package: package(),
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {JidoKeys.Application, []}
    ]
  end

  defp deps do
    [
      {:dotenvy, "~> 1.1"},
      {:splode, "~> 0.2"},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:doctor, "~> 0.22", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18", only: :test}
    ]
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README.md", "LICENSE", "AGENTS.md", "usage-rules.md"],
      maintainers: ["Mike Hostetler"],
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => "https://github.com/agentjido/jido_keys"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: "https://github.com/agentjido/jido_keys",
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
