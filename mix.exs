defmodule Jido.Ai.MixProject do
  use Mix.Project

  @version "0.5.3"
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
      test_coverage: [tool: ExCoveralls, export: "cov"]
    ]
  end

  def cli do
    [
      preferred_envs: [
        "test.unit": :test,
        "test.integration": :test,
        "test.providers": :test,
        "test.all": :test,
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
  defp elixirc_paths(:dev), do: ["lib"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    require Logger
    use_local_deps = System.get_env("LOCAL_JIDO_DEPS") == "true" || false

    deps = [
      {:dotenvy, "~> 1.1.0"},
      {:solid, "~> 1.2.0"},
      {:typed_struct, "~> 0.3.0"},

      # Clients
      {:req, "~> 0.5.8"},
      {:req_llm, "~> 1.0.0-rc.5"},
      {:openai_ex, "~> 0.9.0"},

      # Testing
      {:credo, "~> 1.7", only: [:dev, :test]},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.22.0", only: [:dev, :test]},
      {:ex_check, "~> 0.12", only: [:dev, :test]},
      {:ex_doc, "~> 0.39.3", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18.3", only: [:dev, :test]},
      {:expublish, "~> 2.5", only: [:dev], runtime: false},
      {:git_ops, "~> 2.5", only: [:dev, :test]},
      {:igniter, "~> 0.5", only: [:dev, :test]},
      {:mimic, "~> 2.0", only: [:dev, :test]},
      {:mix_audit, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:mix_test_watch, "~> 1.0", only: [:dev, :test], runtime: false},
      {:sobelow, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:stream_data, "~> 1.1", only: [:dev, :test]}
    ]

    if use_local_deps do
      require Logger
      Logger.warning("Using local Jido dependencies")

      deps ++
        [
          {:jido, path: "../jido"}
          # {:jido_memory, path: "../jido_memory"}
        ]
    else
      deps ++
        [
          {:jido, "~> 1.2.0"}
          # {:jido_memory, github: "agentjido/jido_memory"}
        ]
    end
  end

  defp aliases do
    [
      # Memory-friendly test aliases
      "test.unit": "test --exclude integration_testing --exclude provider_validation",
      "test.integration": "test --only integration_testing --max-cases 1",
      "test.providers": "test --only provider_validation --max-cases 1",
      "test.all": ["test.unit", "test.integration", "test.providers"],

      # Other aliases
      docs: "docs -f html --open",
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

        # User Guides
        {"guides/user/getting-started.md", title: "Getting Started"},
        {"guides/user/models.md", title: "Models"},
        {"guides/user/prompts.md", title: "Prompts"},
        {"guides/user/configuration.md", title: "Configuration"},
        {"guides/user/chat-completion.md", title: "Chat Completion"},
        {"guides/user/conversations.md", title: "Conversations"},

        # Runners
        {"guides/user/runners/overview.md", title: "Runners Overview"},
        {"guides/user/runners/chain-of-thought.md", title: "Chain of Thought"},
        {"guides/user/runners/react.md", title: "ReAct"},
        {"guides/user/runners/self-consistency.md", title: "Self-Consistency"},
        {"guides/user/runners/tree-of-thoughts.md", title: "Tree of Thoughts"},
        {"guides/user/runners/gepa.md", title: "GEPA"}
      ],
      groups_for_extras: [
        "Getting Started": ~r/guides\/user\/(getting-started|models|prompts|configuration|chat-completion|conversations)\.md/,
        Runners: ~r/guides\/user\/runners\/.*/
      ]
    ]
  end
end
