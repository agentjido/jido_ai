defmodule JidoAi.MixProject do
  use Mix.Project

  @version "2.3.0"
  @source_url "https://github.com/agentjido/jido_ai"
  @description "AI integration layer for the Jido ecosystem - Actions, Workflows, and LLM orchestration"
  @guide_toc [
    {"Start Here",
     [
       {"guides/getting-started.livemd", "Getting Started"},
       {"guides/core-concepts.md", "Core Concepts"},
       {"guides/choose-a-reasoning-flow.md", "Choose a Reasoning Flow"}
     ]},
    {"Author AI Agents",
     [
       {"guides/define-an-ai-agent.livemd", "Define an AI Agent"},
       {"guides/agent-authoring.md", "Agent Authoring"},
       {"guides/structured-output.livemd", "Structured Output"},
       {"guides/pure-or-live-execution.md", "Pure or Live Execution"}
     ]},
    {"Context and Conversation",
     [
       {"guides/sessions-and-threads.md", "Sessions and Threads"},
       {"guides/project-a-thread.livemd", "Project a Thread"},
       {"guides/context-lifecycle.md", "Context Lifecycle"},
       {"guides/inspect-model-context.livemd", "Inspect Model Context"}
     ]},
    {"Use Models",
     [
       {"guides/models-and-options.md", "Models and Options"},
       {"guides/embeddings.livemd", "Embeddings"},
       {"guides/stream-model-output.livemd", "Stream Model Output"}
     ]},
    {"Use Tools",
     [
       {"guides/action-tools.livemd", "Action Tools"},
       {"guides/dynamic-tool-sources.md", "Dynamic Tool Sources"},
       {"guides/skills.md", "SKILL.md Instructions"},
       {"guides/tool-execution-and-results.md", "Tool Execution and Results"},
       {"guides/tool-review-and-cycle-limits.livemd", "Tool Review and Cycle Limits"}
     ]},
    {"Reasoning Flows",
     [
       {"guides/react.livemd", "ReAct"},
       {"guides/single-call-reasoning.livemd", "Single-Call Reasoning"},
       {"guides/multi-stage-reasoning.livemd", "Multi-Stage Reasoning"},
       {"guides/adaptive-reasoning.livemd", "Adaptive Reasoning"}
     ]},
    {"Custom Flows", [{"guides/custom-flows.livemd", "Custom Flows"}]},
    {"Run and Operate",
     [
       {"guides/budgets-retries-and-fallbacks.md", "Budgets, Retries, and Fallbacks"},
       {"guides/usage-cache-and-cost.md", "Usage, Cache, and Cost"},
       {"guides/telemetry-and-tracing.livemd", "Telemetry and Tracing"},
       {"guides/errors-and-recovery.md", "Errors and Recovery"},
       {"guides/security-and-portability.md", "Security and Portability"}
     ]},
    {"Test Jido AI",
     [
       {"guides/test-ai-agents.livemd", "Test AI Agents"},
       {"guides/mock-model-calls-with-reqllm.livemd", "Mock Model Calls with ReqLLM"}
     ]},
    {"Reference", [{"guides/public-api-reference.md", "Public API Reference"}]},
    {"Upgrade", [{"guides/v2-to-v3-migration.md", "Migrating from V2"}]}
  ]

  def project do
    [
      app: :jido_ai,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      test_ignore_filters: [&String.starts_with?(&1, "test/bench/")],
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
        "test.live": :test,
        "test.authoring": :test,
        "test.contract": :test,
        "test.ci": :test,
        "bench.react": :test,
        "bench.react.memory": :test,
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
      mod: {Jido.AI.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Jido ecosystem
      {:jido, github: "agentjido/jido", branch: "release/v3", override: true},
      {:jido_action, github: "agentjido/jido_action", branch: "release/v3", override: true},
      {:jido_signal, github: "agentjido/jido_signal", branch: "release/v3", override: true},
      {:runic, "~> 0.1.0-alpha.12", override: true},
      {:req_llm, "~> 1.29"},

      # Runtime
      {:jason, "~> 1.4"},
      {:yaml_elixir, "~> 2.12"},
      {:telemetry, "~> 1.3"},
      {:telemetry_metrics, "~> 1.2"},
      {:opentelemetry_api, "~> 1.0", optional: true},
      {:zoi, "~> 0.18.11", override: true},

      # Dev/Test
      {:covenant,
       github: "mikehostetler/covenant", branch: "feat/component-directories", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.22", only: [:dev], runtime: false},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18", only: [:dev, :test]},
      {:git_hooks, "~> 0.8", only: [:dev, :test], runtime: false},
      {:git_ops, "~> 2.9", only: :dev, runtime: false},
      {:mimic, "~> 2.0", only: :test},
      {:plug, "~> 1.0", only: :test}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "git_hooks.install"],
      test: "test --exclude flaky",
      "test.live": "test --only live",
      examples: "test test/examples --only example",
      "test.authoring": "test test/authoring --only authoring --seed 0",
      "test.contract": "covenant.check",
      "test.ci": ["test --seed 0", "covenant.check"],
      "test.fast": "cmd env MIX_ENV=test mix test --exclude flaky --only stable_smoke",
      "bench.react": &run_react_benchmark/1,
      "bench.react.memory": &run_react_memory_benchmark/1,
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

  defp run_react_benchmark(args),
    do: Mix.Task.run("run", ["test/bench/react_state_growth.exs" | args])

  defp run_react_memory_benchmark(args),
    do: Mix.Task.run("run", ["test/bench/react_memory.exs" | args])

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
      api_reference: true,
      formatters: ["html", "markdown"],
      filter_modules: fn module, _metadata ->
        not String.starts_with?(Atom.to_string(module), "Elixir.JidoAI.Examples.")
      end,
      source_ref: "v#{@version}",
      source_url: @source_url,
      groups_for_extras: project_groups() ++ guide_groups(),
      extras: project_extras() ++ guide_extras(),
      extra_section: "Guides",
      groups_for_modules: [
        Core: [
          Jido.AI,
          Jido.AI.Agent,
          Jido.AI.Agent.Plugin,
          Jido.AI.Reasoning
        ],
        "Context and Conversation": [
          Jido.AI.Context,
          Jido.AI.Context.Snapshot,
          Jido.Thread,
          Jido.Thread.Entry,
          Jido.Session,
          Jido.AI.Thread.Projection
        ],
        "Tools and Model Calls": [
          Jido.AI.Actions.Embed,
          Jido.AI.Skill,
          Jido.AI.Toolset,
          Jido.AI.ToolSource,
          Jido.AI.ToolSource.Tool,
          Jido.AI.ToolResult
        ],
        "Limits and Observability": [
          Jido.AI.Budget,
          Jido.AI.Usage,
          Jido.AI.Telemetry
        ],
        Reasoning: [~r/Jido\.AI\.Reasoning\..*/]
      ]
    ]
  end

  defp project_groups do
    [Project: ["README.md", "CHANGELOG.md", "LICENSE"]]
  end

  defp project_extras do
    [
      {"README.md", title: "Home"},
      {"CHANGELOG.md", title: "Changelog"},
      {"LICENSE", title: "Apache 2.0 License"}
    ]
  end

  defp guide_groups do
    Enum.flat_map(@guide_toc, fn {group, guides} ->
      paths = for {path, _title} <- guides, File.regular?(path), do: path
      if paths == [], do: [], else: [{group, paths}]
    end)
  end

  defp guide_extras do
    for {_group, guides} <- @guide_toc,
        {path, title} <- guides,
        File.regular?(path),
        do: {path, title: title}
  end
end
