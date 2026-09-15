defmodule JidoAi.MixProject do
  use Mix.Project

  @version "2.3.0"
  @source_url "https://github.com/agentjido/jido_ai"
  @description "AI integration layer for the Jido ecosystem - Actions, Workflows, and LLM orchestration"
  def project do
    [
      app: :jido_ai,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      test_ignore_filters: [~r/test\/authoring\/support\//],
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
        plt_add_apps: [:mix, :ex_unit, :llm_db, :jsv],
        ignore_warnings: "dialyzer.ignore-warnings"
      ]
    ]
  end

  def cli do
    [
      preferred_envs: [
        "test.authoring": :test,
        examples: :test,
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

  defp elixirc_paths(:test), do: ["lib", "test/support", "test/examples/support"] ++ example_paths()
  defp elixirc_paths(:dev), do: ["lib"] ++ example_paths()
  defp elixirc_paths(_), do: ["lib"]

  defp example_paths do
    ["examples/support" | Path.wildcard("examples/[0-9][0-9]_*")]
  end

  defp deps do
    [
      # Jido ecosystem
      {:jido, "~> 3.0.0-beta.1", override: true},
      {:jido_action, "~> 3.0.0-beta.11", override: true},
      {:jido_signal, "~> 3.0.0-beta.4", override: true},
      {:req_llm, github: "agentjido/req_llm", ref: "888fca022fea50785e2a54f7eabfcc47d289ae41", override: true},

      # Runtime
      {:fsmx, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:splode, "~> 0.3.0"},
      {:yaml_elixir, "~> 2.12"},
      {:zoi, "~> 0.18"},

      # Dev/Test
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.22", only: [:dev], runtime: false},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18", only: [:dev, :test]},
      {:git_hooks, "~> 0.8", only: [:dev, :test], runtime: false},
      {:git_ops, "~> 2.9", only: :dev, runtime: false},
      {:mimic, "~> 2.0", only: :test},
      {:igniter, "~> 0.7", optional: true}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "git_hooks.install"],
      test: "test --exclude flaky",
      examples: "test test/examples --only example",
      "test.authoring": "test test/authoring --only authoring --seed 0",
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
      docs: "docs --open"
    ]
  end

  defp package do
    [
      files: [
        "lib",
        "mix.exs",
        "README.md",
        "LICENSE",
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
      formatters: ["html", "markdown"],
      filter_modules: fn module, _metadata ->
        not String.starts_with?(Atom.to_string(module), "Elixir.JidoAI.Examples.")
      end,
      source_ref: "v#{@version}",
      extras: [
        "README.md",
        "LICENSE",
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
        # Upgrading
        "guides/user/migration_plugins_and_signals_v3.md",
        # Extend Jido.AI
        "guides/developer/architecture_and_runtime_flow.md",
        "guides/developer/strategy_internals.md",
        "guides/developer/signals_namespaces_contracts.md",
        "guides/developer/plugins_and_actions_composition.md",
        "guides/developer/skills_system.md",
        "guides/developer/security_and_validation.md",
        "guides/developer/error_model_and_recovery.md",
        # Reference
        "guides/developer/actions_catalog.md",
        "guides/developer/configuration_reference.md",
        "guides/developer/thread_context_projection_model.md"
      ],
      groups_for_extras: [
        {"Build With Jido.AI",
         ~r/guides\/user\/(package_overview|getting_started|first_react_agent|strategy_selection_playbook|strategy_recipes|request_lifecycle_and_concurrency|thread_context_and_message_projection|tool_calling_with_actions|llm_facade_quickstart|model_routing_and_policy|retrieval_and_quota|observability_basics|standalone_react_runtime|turn_and_tool_results)\.md/},
        {"Upgrading", ~r/guides\/user\/migration_plugins_and_signals_v3\.md/},
        {"Extend Jido.AI",
         ~r/guides\/developer\/(architecture_and_runtime_flow|strategy_internals|signals_namespaces_contracts|plugins_and_actions_composition|skills_system|security_and_validation|error_model_and_recovery)\.md/},
        {"Reference",
         ~r/guides\/developer\/(actions_catalog|configuration_reference|thread_context_projection_model)\.md/}
      ],
      groups_for_modules: [
        Core: [
          Jido.AI,
          Jido.AI.Agent,
          Jido.AI.Request,
          Jido.AI.Request.Handle,
          Jido.AI.Output,
          Jido.Thread,
          Jido.Thread.Entry,
          Jido.Session,
          Jido.AI.Turn,
          Jido.AI.Observe,
          Jido.AI.Observe.Sanitize,
          Jido.AI.Validation,
          Jido.AI.ToolAdapter
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
        "Actions — Skill": [
          ~r/Jido\.AI\.Actions\.Skill\..*/
        ],
        "Reasoning Strategies": [
          ~r/Jido\.AI\.Reasoning\..*/
        ],
        Plugins: [
          ~r/Jido\.AI\.Plugins\..*/
        ],
        Signals: [
          Jido.AI.Signal.Helpers,
          ~r/Jido\.AI\.Signal\..*/
        ],
        Testing: [
          Jido.AI.Test,
          Jido.AI.TestCase,
          ~r/Jido\.AI\.Test\..*/
        ],
        Skills: [
          Jido.AI.Skill,
          ~r/Jido\.AI\.Skill\..*/
        ],
        "Quality & Quota": [
          Jido.AI.Quality.Checkpoint,
          Jido.AI.Quota.Store
        ],
        "Mix Tasks": [
          ~r/Mix\.Tasks\..*/
        ]
      ]
    ]
  end
end
