defmodule Jido.Ai.MixProject do
  use Mix.Project

  @version "0.5.2"
  @source_url "https://github.com/agentjido/jido_ai"

  def project do
    [
      app: :jido_ai,
      version: @version,
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      dialyzer: [
        plt_add_apps: [:mix, :ex_unit],
        flags: [
          :error_handling,
          :underspecs
        ]
      ],
      name: "Jido AI",
      description: "Jido Actions and Workflows for interacting with LLMs",
      package: package(),
      docs: docs(),
      source_url: @source_url,
      consolidate_protocols: Mix.env() != :test,

      # Coverage
      test_coverage: [tool: ExCoveralls, export: "cov"],
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

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {Jido.AI.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Jido
      {:jido, path: "../jido"},
      {:jido_action, github: "agentjido/jido_action"},

      # Deps
      {:dotenvy, "~> 1.1.0"},
      {:nimble_options, "~> 1.1"},
      {:solid, "~> 1.0"},
      {:splode, "~> 0.2.4"},
      {:typed_struct, "~> 0.3.0"},

      # Clients
      {:req, "~> 0.5.8"},
      {:plug, "~> 1.16"},
      {:openai_ex, "~> 0.9.0"},
      {:instructor, "~> 0.1.0"},
      {:langchain, "~> 0.3.1"},
      {:server_sent_events, "~> 0.2.1"},

      # Phoenix Playground (dev only)
      {:phoenix_playground, "~> 0.1.7", only: [:dev, :test]},
      {:earmark, "~> 1.4", only: [:dev]},

      # Testing
      {:credo, "~> 1.7", only: [:dev, :test]},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.22.0", only: [:dev, :test]},
      {:ex_check, "~> 0.12", only: [:dev, :test]},
      {:ex_doc, "~> 0.37-rc", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18.3", only: [:dev, :test]},
      {:expublish, "~> 2.5", only: [:dev], runtime: false},
      {:git_ops, "~> 2.5", only: [:dev, :test]},
      {:igniter, "~> 0.5", only: [:dev, :test]},
      {:mimic, "~> 2.0", only: [:dev, :test]},
      {:mix_audit, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:mix_test_watch, "~> 1.0", only: [:dev, :test], runtime: false},
      {:quokka, "~> 2.10", only: [:dev, :test], runtime: false},
      {:sobelow, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:stream_data, "~> 1.1", only: [:dev, :test]}
    ]
  end

  defp aliases do
    [
      # test: "test --trace",
      docs: "docs -f html --open",
      playground: "jido.ai.playground",
      q: ["quality"],
      quality: [
        "format",
        "format --check-formatted",
        "compile --warnings-as-errors",
        "dialyzer --format dialyxir",
        "credo --all",
        "doctor --short --raise",
        "docs"
      ]
    ]
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README.md", "LICENSE.md"],
      maintainers: ["Mike Hostetler"],
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: [
        "README.md",
        {"guides/getting-started.md", title: "Getting Started"},
        {"guides/keyring.md", title: "Managing Keys"},
        {"guides/prompt.md", title: "Prompting"},
        {"guides/providers.md", title: "LLM Providers"},
        {"guides/agent-skill.md", title: "Agent & Skill"},
        {"guides/actions.md", title: "Actions"}
      ]
    ]
  end
end
