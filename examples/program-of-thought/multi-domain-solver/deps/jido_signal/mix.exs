defmodule Jido.Signal.MixProject do
  use Mix.Project

  @version "1.0.0"
  @source_url "https://github.com/agentjido/jido_signal"
  @description "Agent Communication Envelope and Utilities"

  def vsn do
    @version
  end

  def project do
    [
      app: :jido_signal,
      version: @version,
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),

      # Docs
      name: "Jido Signal",
      description: @description,
      source_url: @source_url,
      homepage_url: @source_url,
      package: package(),
      docs: docs(),

      # Coverage
      test_coverage: [
        tool: ExCoveralls,
        summary: [threshold: 80],
        export: "cov",
        ignore_modules: [~r/^JidoTest\./]
      ],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.github": :test,
        "coveralls.lcov": :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.cobertura": :test
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Jido.Signal.Application, []}
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "CONTRIBUTING.md",
        "LICENSE.md",
        "guides/getting-started.md",
        "guides/introduction/what-is-jido-signal.md",
        "guides/introduction/core-components.md",
        "guides/introduction/when-to-use.md",
        "guides/core-concepts/signal-structure.md",
        "guides/core-concepts/signal-bus.md",
        "guides/core-concepts/router.md",
        "guides/core-concepts/dispatch-system.md"
      ],
      groups_for_extras: [
        Introduction: ~r/guides\/introduction\/.*/,
        "Getting Started": ~r/guides\/getting-started.*/,
        "Core Concepts": ~r/guides\/core-concepts\/.*/
      ]
    ]
  end

  def package do
    [
      files: ["lib", "mix.exs", "README*", "LICENSE*"],
      maintainers: ["Mike Hostetler"],
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @source_url,
        "AgentJido.xyz" => "https://agentjido.xyz",
        "Jido Workbench" => "https://github.com/agentjido/jido_workbench"
      }
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Deps
      {:ex_dbug, "~> 2.1"},
      {:jason, "~> 1.4"},
      {:msgpax, "~> 2.3"},
      {:nimble_options, "~> 1.1"},
      {:phoenix_pubsub, "~> 2.1"},
      {:private, "~> 0.1.2"},
      {:telemetry, "~> 1.3"},
      {:telemetry_metrics, "~> 1.1"},
      {:typed_struct, "~> 0.3.0"},
      {:uniq, "~> 0.6.1"},

      # Development & Test Dependencies
      {:credo, "~> 1.7", only: [:dev, :test]},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.21", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18.3", only: [:dev, :test]},
      {:expublish, "~> 2.7", only: [:dev], runtime: false},
      {:mix_test_watch, "~> 1.0", only: [:dev, :test], runtime: false},
      {:mock, "~> 0.3.0", only: :test},
      {:mimic, "~> 1.11", only: :test},
      {:stream_data, "~> 1.0", only: [:dev, :test]}
    ]
  end

  defp aliases do
    [
      # Helper to run tests with trace when needed
      # test: "test --trace --exclude flaky",
      test: "test --exclude flaky",

      # Helper to run docs
      docs: "docs -f html --open",

      # Run to check the quality of your code
      q: ["quality"],
      quality: [
        "format",
        "format --check-formatted",
        "compile --warnings-as-errors",
        "dialyzer --format dialyxir",
        "credo --all"
      ]
    ]
  end
end
