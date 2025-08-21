defmodule JidoAction.MixProject do
  use Mix.Project

  @version "1.0.0"
  @source_url "https://github.com/agentjido/jido_action"
  @description "Composable, validated actions for Elixir applications with built-in AI tool integration"

  def vsn do
    @version
  end

  def project do
    [
      app: :jido_action,
      version: @version,
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),

      # Docs
      name: "Jido Action",
      description: @description,
      source_url: @source_url,
      homepage_url: @source_url,
      package: package(),
      docs: docs(),

      # Coverage
      test_coverage: [
        tool: ExCoveralls
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

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Jido.Action.Application, []}
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support", "test/jido/bus/support"]
  defp elixirc_paths(:dev), do: ["lib", "bench"]
  defp elixirc_paths(_), do: ["lib"]

  defp docs do
    [
      main: "readme",
      api_reference: false,
      source_ref: "v#{@version}",
      source_url: "https://github.com/agentjido/jido_action",
      authors: ["Mike Hostetler <mike.hostetler@gmail.com>"],
      groups_for_extras: [
        "Getting Started": [
          "guides/getting-started.md",
          "guides/your-second-action.md"
        ],
        "Core Concepts": [
          "guides/actions-guide.md",
          "guides/execution-engine.md",
          "guides/instructions-plans.md",
          "guides/error-handling.md"
        ],
        "How-To Guides": [
          "guides/tools-reference.md",
          "guides/ai-integration.md",
          "guides/configuration.md",
          "guides/security.md",
          "guides/testing.md"
        ],
        "Help & Reference": [
          "guides/faq.md",
          "CHANGELOG.md",
          "LICENSE.md"
        ]
      ],
      extras: [
        # Home & Project
        {"README.md", title: "Home"},
        # Getting Started
        {"guides/getting-started.md", title: "Getting Started"},
        {"guides/your-second-action.md", title: "Your Second Action"},
        # Core Concepts
        {"guides/actions-guide.md", title: "Actions"},
        {"guides/execution-engine.md", title: "Execution Engine"},
        {"guides/instructions-plans.md", title: "Instructions & Plans"},
        {"guides/error-handling.md", title: "Error Handling"},
        # How-To Guides
        {"guides/tools-reference.md", title: "Built-in Tools"},
        {"guides/ai-integration.md", title: "AI Integration"},
        {"guides/configuration.md", title: "Configuration"},
        {"guides/security.md", title: "Security"},
        {"guides/testing.md", title: "Testing"},
        # Help & Reference
        {"guides/faq.md", title: "FAQ"},
        {"CHANGELOG.md", title: "Changelog"},
        {"LICENSE.md", title: "Apache 2.0 License"}
      ],
      extra_section: "Guides",
      formatters: ["html"],
      skip_undefined_reference_warnings_on: [
        "CHANGELOG.md",
        "LICENSE.md"
      ],
      groups_for_modules: [
        Core: [
          Jido.Action,
          Jido.Action.Error,
          Jido.Action.Tool,
          Jido.Action.Util
        ],
        "Execution Engine": [
          Jido.Exec,
          Jido.Exec.Chain,
          Jido.Exec.Closure
        ],
        "Planning & Workflows": [
          Jido.Plan,
          Jido.Plan.PlanInstruction,
          Jido.Instruction
        ],
        "Actions: Basic Tools": [
          Jido.Tools.Arithmetic,
          Jido.Tools.Basic,
          Jido.Tools.Files,
          Jido.Tools.Simplebot,
          Jido.Tools.Weather,
          Jido.Tools.Workflow
        ],
        "Actions: HTTP & Requests": [
          Jido.Tools.Req,
          Jido.Tools.ReqTool
        ],
        "Actions: GitHub": [
          Jido.Tools.Github.Issues,
          Jido.Tools.Github.Issues.Create,
          Jido.Tools.Github.Issues.Filter,
          Jido.Tools.Github.Issues.Find,
          Jido.Tools.Github.Issues.List,
          Jido.Tools.Github.Issues.Update
        ],
        "Actions: Advanced": [
          Jido.Tools.ActionPlan
        ],
        "Error Types": [
          Jido.Action.Error.Config,
          Jido.Action.Error.ConfigurationError,
          Jido.Action.Error.Execution,
          Jido.Action.Error.ExecutionFailureError,
          Jido.Action.Error.Internal,
          Jido.Action.Error.Internal.UnknownError,
          Jido.Action.Error.InternalError,
          Jido.Action.Error.Invalid,
          Jido.Action.Error.InvalidInputError,
          Jido.Action.Error.TimeoutError
        ]
      ]
    ]
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README.md", "LICENSE.md", "usage-rules.md"],
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
      {:jason, "~> 1.4"},
      {:nimble_options, "~> 1.1"},
      {:private, "~> 0.1.2"},
      {:telemetry, "~> 1.3"},
      {:telemetry_metrics, "~> 1.1"},
      {:typed_struct, "~> 0.3.0"},
      {:uniq, "~> 0.6.1"},
      {:splode, "~> 0.2.4"},

      # Skill & Action Dependencies for examples
      {:abacus, "~> 2.1"},
      {:libgraph, "~> 0.16.0"},
      {:req, "~> 0.5.10"},
      {:tentacat, "~> 2.5"},
      {:weather, "~> 0.4.0"},

      # Development & Test Dependencies
      {:credo, "~> 1.7", only: [:dev, :test]},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.0", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.21", only: [:dev, :test], runtime: false},
      {:quokka, "~> 2.10", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18.3", only: [:dev, :test]},
      {:expublish, "~> 2.7", only: [:dev], runtime: false},
      {:mix_test_watch, "~> 1.0", only: [:dev, :test], runtime: false},
      {:mimic, "~> 2.0", only: :test},
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
        "format --check-formatted",
        "deps.unlock --check-unused",
        "compile --warnings-as-errors",
        "dialyzer",
        "credo --strict",
        "doctor",
        "deps.audit --format brief"
      ]
    ]
  end
end
