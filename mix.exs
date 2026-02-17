defmodule JidoAi.MixProject do
  use Mix.Project

  @version "2.0.0"
  @source_url "https://github.com/agentjido/jido_ai"
  @description "AI integration layer for the Jido ecosystem - Actions, Workflows, and LLM orchestration"

  def project do
    [
      app: :jido_ai,
      version: @version,
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),

      # Documentation
      name: "Jido AI",
      description: @description,
      source_url: @source_url,
      homepage_url: @source_url,
      package: package(),
      docs: docs(),

      # Test Coverage
      test_coverage: [
        tool: ExCoveralls,
        summary: [threshold: 90]
      ],

      # Dialyzer
      dialyzer: [
        plt_add_apps: [:mix]
      ]
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.github": :test
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Jido ecosystem
      {:jido, "~> 2.0.0-rc.4"},
      {:jido_action, github: "agentjido/jido_action", branch: "main", override: true},
      {:req_llm, github: "agentjido/req_llm", branch: "main"},
      # Example-only browser tools (kept out of Hex runtime dependency graph)
      {:jido_browser, github: "agentjido/jido_browser", branch: "main", only: [:dev, :test], runtime: false},

      # Runtime
      {:fsmx, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:nimble_options, "~> 1.1"},
      {:splode, "~> 0.3.0"},
      {:yaml_elixir, "~> 2.9"},
      {:zoi, "~> 0.16"},

      # Dev/Test
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.22", only: [:dev], runtime: false},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18", only: [:dev, :test]},
      {:git_hooks, "~> 0.8", only: [:dev, :test], runtime: false},
      {:git_ops, "~> 2.9", only: :dev, runtime: false},
      {:mimic, "~> 2.0", only: :test},
      {:stream_data, "~> 1.0", only: [:dev, :test]}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "git_hooks.install"],
      test: "test --exclude flaky",
      q: ["quality"],
      quality: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "credo --min-priority high --all",
        "doctor --summary --raise",
        "dialyzer"
      ],
      docs: "docs -f html"
    ]
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README.md", "LICENSE.md", "CHANGELOG.md", "usage-rules.md", "guides", "examples"],
      maintainers: ["Mike Hostetler <mike.hostetler@gmail.com>", "Pascal Charbon <pcharbon70@gmail.com>"],
      licenses: ["Apache-2.0"],
      links: %{
        "Changelog" => "https://hexdocs.pm/jido_ai/changelog.html",
        "Discord" => "https://agentjido.xyz/discord",
        "Documentation" => "https://hexdocs.pm/jido_ai",
        "GitHub" => @source_url,
        "Website" => "https://agentjido.xyz"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: [
        "README.md",
        "LICENSE.md",
        "CHANGELOG.md",
        "CONTRIBUTING.md",
        # Build With Jido.AI
        "guides/user/getting_started.md",
        "guides/user/strategy_selection_playbook.md",
        "guides/user/first_react_agent.md",
        "guides/user/request_lifecycle_and_concurrency.md",
        "guides/user/thread_context_and_message_projection.md",
        "guides/user/tool_calling_with_actions.md",
        "guides/user/streaming_workflows.md",
        "guides/user/observability_basics.md",
        "guides/user/cli_workflows.md",
        # Extend Jido.AI
        "guides/developer/architecture_and_runtime_flow.md",
        "guides/developer/strategy_internals.md",
        "guides/developer/directives_runtime_contract.md",
        "guides/developer/signals_namespaces_contracts.md",
        "guides/developer/plugins_and_actions_composition.md",
        "guides/developer/skills_system.md",
        "guides/developer/security_and_validation.md",
        "guides/developer/error_model_and_recovery.md",
        # Reference
        "guides/developer/actions_catalog.md",
        "guides/developer/configuration_reference.md",
        # Examples
        "examples/strategies/adaptive_strategy.md",
        "examples/strategies/chain_of_thought.md",
        "examples/strategies/react_agent.md",
        "examples/strategies/tree_of_thoughts.md"
      ],
      groups_for_extras: [
        {"Build With Jido.AI", ~r/guides\/user/},
        {"Extend Jido.AI",
         ~r/guides\/developer\/(architecture_and_runtime_flow|strategy_internals|directives_runtime_contract|signals_namespaces_contracts|plugins_and_actions_composition|skills_system|security_and_validation|error_model_and_recovery)\.md/},
        {"Reference", ~r/guides\/developer\/(actions_catalog|configuration_reference)\.md/},
        {"Examples - Strategies", ~r/examples\/strategies/}
      ],
      groups_for_modules: [
        Core: [
          Jido.AI,
          Jido.AI.Error
        ]
      ]
    ]
  end
end
