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
        plt_add_apps: [:ex_unit, :llm_db, :jsv],
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
      {:mimic, "~> 2.0", only: :test}
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
        "guides/v3/learning_path.md",
        "guides/v3/01_first_agent.md",
        "guides/livebooks/first_answer.livemd",
        "guides/v3/02_tools_and_react.md",
        "guides/livebooks/three_tool_rounds.livemd",
        "guides/v3/03_results_and_state.md",
        "guides/v3/04_dsl_map.md",
        "guides/v3/05_models_profiles_instructions.md",
        "guides/v3/06_tool_contracts.md",
        "guides/v3/07_structured_results.md",
        "guides/livebooks/repair_result.livemd",
        "guides/v3/08_reasoning_methods.md",
        "guides/livebooks/reasoning_methods.livemd",
        "guides/v3/09_turn_sequence.md",
        "guides/v3/10_long_running_turns.md",
        "guides/livebooks/long_turn.livemd",
        "guides/v3/11_controls_and_limits.md",
        "guides/v3/12_stream_steer_cancel.md",
        "guides/livebooks/steer_turn.livemd",
        "guides/v3/13_failures_and_recovery.md",
        "guides/v3/14_tool_policy.md",
        "guides/livebooks/tool_policy.livemd",
        "guides/v3/15_budgets_and_quotas.md",
        "guides/v3/16_observability.md",
        "guides/v3/17_session_thread_context.md",
        "guides/livebooks/two_requests.livemd",
        "guides/v3/18_context_projection.md",
        "guides/v3/19_multiple_contexts.md",
        "guides/livebooks/switch_context.livemd",
        "guides/v3/20_checkpoint_resume.md",
        "guides/livebooks/resume_context.livemd",
        "guides/v3/21_testing_agents.md",
        "guides/v3/22_dsl_reference.md"
      ],
      groups_for_extras: [
        {"Start Here", ~r/guides\/(v3\/(learning_path|0[1-3]_)|livebooks\/(first_answer|three_tool_rounds)\.)/},
        {"Author the Agent", ~r/guides\/(v3\/0[4-8]_|livebooks\/(repair_result|reasoning_methods)\.)/},
        {"Understand a Turn", ~r/guides\/(v3\/(09_|1[0-3]_)|livebooks\/(long_turn|steer_turn)\.)/},
        {"Govern and Inspect", ~r/guides\/(v3\/1[4-6]_|livebooks\/tool_policy\.)/},
        {"Work with Context",
         ~r/guides\/(v3\/1[7-9]_|v3\/20_|livebooks\/(two_requests|switch_context|resume_context)\.)/},
        {"Reference", ~r/guides\/v3\/2[1-2]_/}
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
        Quota: [
          Jido.AI.Quota.Store
        ]
      ]
    ]
  end
end
