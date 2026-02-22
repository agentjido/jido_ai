defmodule JidoAi.MixProject do
  use Mix.Project

  @version "2.0.0-beta"
  @source_url "https://github.com/agentjido/jido_ai"
  @description "AI integration layer for the Jido ecosystem - Actions, Workflows, and LLM orchestration"
  def project do
    [
      app: :jido_ai,
      version: @version,
      elixir: "~> 1.18",
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
        summary: [threshold: 80]
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
      {:jido, "~> 2.0.0-rc.5"},
      {:jido_action, "~> 2.0.0-rc.5"},
      {:req_llm, "~> 1.6"},
      # Example-only browser tools (kept out of Hex runtime dependency graph)
      {:jido_browser, "~> 0.8.1", only: [:dev, :test], runtime: false},

      # Runtime
      {:fsmx, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:nimble_options, "~> 1.1"},
      {:splode, "~> 0.3.0"},
      {:yaml_elixir, "~> 2.12"},
      {:zoi, "~> 0.17"},

      # Dev/Test
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.22", only: [:dev], runtime: false},
      {:dotenvy, "~> 1.1"},
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
      "test.fast": "cmd env MIX_ENV=test mix test --exclude flaky --only stable_smoke",
      precommit: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "doctor --summary --raise",
        "test.fast"
      ],
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
      files: [
        "lib",
        "mix.exs",
        "README.md",
        "LICENSE.md",
        "CHANGELOG.md",
        "usage-rules.md",
        "guides"
      ],
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
        # Build With Jido.AI
        "guides/user/package_overview.md",
        "guides/user/getting_started.md",
        "guides/user/first_react_agent.md",
        "guides/user/strategy_selection_playbook.md",
        "guides/user/strategy_recipes.md",
        "guides/user/request_lifecycle_and_concurrency.md",
        "guides/user/thread_context_and_message_projection.md",
        "guides/user/tool_calling_with_actions.md",
        "guides/user/llm_facade_quickstart.md",
        "guides/user/model_routing_and_policy.md",
        "guides/user/retrieval_and_quota.md",
        "guides/user/observability_basics.md",
        "guides/user/standalone_react_runtime.md",
        "guides/user/turn_and_tool_results.md",
        "guides/user/cli_workflows.md",
        # Upgrading
        "guides/user/migration_plugins_and_signals_v3.md",
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
        "guides/developer/configuration_reference.md"
      ],
      groups_for_extras: [
        {"Build With Jido.AI",
         ~r/guides\/user\/(package_overview|getting_started|first_react_agent|strategy_selection_playbook|strategy_recipes|request_lifecycle_and_concurrency|thread_context_and_message_projection|tool_calling_with_actions|llm_facade_quickstart|model_routing_and_policy|retrieval_and_quota|observability_basics|standalone_react_runtime|turn_and_tool_results|cli_workflows)\.md/},
        {"Upgrading", ~r/guides\/user\/migration_plugins_and_signals_v3\.md/},
        {"Extend Jido.AI",
         ~r/guides\/developer\/(architecture_and_runtime_flow|strategy_internals|directives_runtime_contract|signals_namespaces_contracts|plugins_and_actions_composition|skills_system|security_and_validation|error_model_and_recovery)\.md/},
        {"Reference", ~r/guides\/developer\/(actions_catalog|configuration_reference)\.md/}
      ],
      groups_for_modules: [
        Core: [
          Jido.AI,
          Jido.AI.Agent,
          Jido.AI.Request,
          Jido.AI.Request.Handle,
          Jido.AI.Thread,
          Jido.AI.Thread.Entry,
          Jido.AI.Turn,
          Jido.AI.Observe,
          Jido.AI.Validation,
          Jido.AI.ToolAdapter,
          Jido.AI.PluginStack
        ],
        Errors: [
          Jido.AI.Error,
          ~r/Jido\.AI\.Error\..*/
        ],
        "Actions — LLM": [
          Jido.AI.Actions.Helpers,
          ~r/Jido\.AI\.Actions\.LLM\..*/
        ],
        "Actions — Planning": [
          ~r/Jido\.AI\.Actions\.Planning\..*/
        ],
        "Actions — Reasoning": [
          ~r/Jido\.AI\.Actions\.Reasoning\..*/
        ],
        "Actions — Retrieval": [
          Jido.AI.Retrieval.Store,
          ~r/Jido\.AI\.Actions\.Retrieval\..*/
        ],
        "Actions — Tool Calling": [
          ~r/Jido\.AI\.Actions\.ToolCalling\..*/
        ],
        "Actions — Quota": [
          ~r/Jido\.AI\.Actions\.Quota\..*/
        ],
        "Reasoning Strategies": [
          Jido.AI.Reasoning.Helpers,
          ~r/Jido\.AI\.Reasoning\..*/
        ],
        "Convenience Agents": [
          Jido.AI.AdaptiveAgent,
          Jido.AI.AoTAgent,
          Jido.AI.CoDAgent,
          Jido.AI.CoTAgent,
          Jido.AI.GoTAgent,
          Jido.AI.ToTAgent,
          Jido.AI.TRMAgent
        ],
        Plugins: [
          ~r/Jido\.AI\.Plugins\..*/
        ],
        Signals: [
          Jido.AI.Signal.Helpers,
          ~r/Jido\.AI\.Signal\..*/
        ],
        Directives: [
          ~r/Jido\.AI\.Directive\..*/
        ],
        Skills: [
          Jido.AI.Skill,
          ~r/Jido\.AI\.Skill\..*/
        ],
        "Quality & Quota": [
          Jido.AI.Quality.Checkpoint,
          Jido.AI.Quota.Store
        ],
        CLI: [
          Jido.AI.CLI.Adapter
        ],
        "Mix Tasks": [
          ~r/Mix\.Tasks\..*/
        ],
        Examples: [
          ~r/Jido\.AI\.Examples\..*/
        ]
      ]
    ]
  end
end
