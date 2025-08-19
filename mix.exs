defmodule Jido.BehaviorTree.MixProject do
  use Mix.Project

  @version "1.0.0"
  @source_url "https://github.com/agentjido/jido_behaviortree"
  @description "Behavior Tree implementation for Jido agents with integrated action support"

  def vsn do
    @version
  end

  def project do
    [
      app: :jido_behaviortree,
      version: @version,
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),

      # Docs
      name: "Jido Behavior Tree",
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

  def application do
    [
      extra_applications: [:logger],
      mod: {Jido.BehaviorTree.Application, []}
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(:dev), do: ["lib", "bench"]
  defp elixirc_paths(_), do: ["lib"]

  defp docs do
    [
      main: "readme",
      api_reference: false,
      source_ref: "v#{@version}",
      source_url: @source_url,
      authors: ["Mike Hostetler <mike.hostetler@gmail.com>"],
      groups_for_extras: [
        "Getting Started": [
          "guides/getting-started.md",
          "guides/your-first-bt.md"
        ],
        "Core Concepts": [
          "guides/behavior-trees.md",
          "guides/nodes.md",
          "guides/action-integration.md"
        ],
        "How-To Guides": [
          "guides/custom-nodes.md",
          "guides/ai-integration.md",
          "guides/testing.md"
        ],
        "Help & Reference": [
          "CHANGELOG.md",
          "LICENSE.md"
        ]
      ],
      extras: [
        {"README.md", title: "Home"},
        {"guides/getting-started.md", title: "Getting Started"},
        {"guides/your-first-bt.md", title: "Your First Behavior Tree"},
        {"guides/behavior-trees.md", title: "Behavior Trees"},
        {"guides/nodes.md", title: "Nodes"},
        {"guides/action-integration.md", title: "Action Integration"},
        {"guides/custom-nodes.md", title: "Custom Nodes"},
        {"guides/ai-integration.md", title: "AI Integration"},
        {"guides/testing.md", title: "Testing"},
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
          Jido.BehaviorTree,
          Jido.BehaviorTree.Status,
          Jido.BehaviorTree.Tick,
          Jido.BehaviorTree.Blackboard,
          Jido.BehaviorTree.Node,
          Jido.BehaviorTree.Tree
        ],
        "Composite Nodes": [
          Jido.BehaviorTree.Nodes.Sequence,
          Jido.BehaviorTree.Nodes.Selector,
          Jido.BehaviorTree.Nodes.Parallel,
          Jido.BehaviorTree.Nodes.MemSequence,
          Jido.BehaviorTree.Nodes.MemSelector
        ],
        "Decorator Nodes": [
          Jido.BehaviorTree.Nodes.Inverter,
          Jido.BehaviorTree.Nodes.Succeeder,
          Jido.BehaviorTree.Nodes.Failer,
          Jido.BehaviorTree.Nodes.Repeat,
          Jido.BehaviorTree.Nodes.UntilSuccess,
          Jido.BehaviorTree.Nodes.UntilFailure,
          Jido.BehaviorTree.Nodes.Timeout
        ],
        "Leaf Nodes": [
          Jido.BehaviorTree.Nodes.Action,
          Jido.BehaviorTree.Nodes.Wait,
          Jido.BehaviorTree.Nodes.SetBlackboard
        ],
        Execution: [
          Jido.BehaviorTree.Agent,
          Jido.BehaviorTree.Skill
        ]
      ]
    ]
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README.md", "LICENSE.md"],
      maintainers: ["Mike Hostetler"],
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @source_url,
        "AgentJido.xyz" => "https://agentjido.xyz"
      }
    ]
  end

  defp deps do
    [
      # Core dependencies
      {:jido_action, path: "../jido_action"},
      {:telemetry, "~> 1.3"},
      {:typed_struct, "~> 0.3.0"},
      {:jason, "~> 1.4"},

      # Development & Test Dependencies
      {:credo, "~> 1.7", only: [:dev, :test]},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.0", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.21", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18.3", only: [:dev, :test]},
      {:mix_test_watch, "~> 1.0", only: [:dev, :test], runtime: false},
      {:mimic, "~> 2.0", only: :test},
      {:stream_data, "~> 1.0", only: [:dev, :test]}
    ]
  end

  defp aliases do
    [
      test: "test --exclude flaky",
      docs: "docs -f html --open",
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
