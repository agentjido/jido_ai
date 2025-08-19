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
        summary: [threshold: 90],
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
        "guides/signals-and-dispatch.md",
        "guides/signal-router.md",
        "guides/event-bus.md",
        "guides/signal-journal.md",
        "guides/serialization.md",
        "guides/advanced.md"
      ],
      groups_for_extras: [
        Guides: ~r/guides\/.*/
      ],
      groups_for_modules: [
        "Core Signal": [
          Jido.Signal,
          Jido.Signal.Error,
          Jido.Signal.ID,
          Jido.Signal.Util
        ],
        "Signal Routing": [
          Jido.Signal.Router,
          Jido.Signal.Router.Engine,
          Jido.Signal.Router.HandlerInfo,
          Jido.Signal.Router.Inspect,
          Jido.Signal.Router.NodeHandlers,
          Jido.Signal.Router.PatternMatch,
          Jido.Signal.Router.Route,
          Jido.Signal.Router.Router,
          Jido.Signal.Router.TrieNode,
          Jido.Signal.Router.Validator,
          Jido.Signal.Router.WildcardHandlers
        ],
        "Event Bus": [
          Jido.Signal.Bus,
          Jido.Signal.Bus.Middleware,
          Jido.Signal.Bus.MiddlewarePipeline,
          Jido.Signal.Bus.PersistentSubscription,
          Jido.Signal.Bus.RecordedSignal,
          Jido.Signal.Bus.Snapshot,
          Jido.Signal.Bus.Snapshot.SnapshotData,
          Jido.Signal.Bus.Snapshot.SnapshotRef,
          Jido.Signal.Bus.State,
          Jido.Signal.Bus.Stream,
          Jido.Signal.Bus.Subscriber,
          Jido.Signal.Bus.Middleware.Logger
        ],
        "Signal Dispatch": [
          Jido.Signal.Dispatch,
          Jido.Signal.Dispatch.Adapter,
          Jido.Signal.Dispatch.ConsoleAdapter,
          Jido.Signal.Dispatch.Http,
          Jido.Signal.Dispatch.LoggerAdapter,
          Jido.Signal.Dispatch.Named,
          Jido.Signal.Dispatch.NoopAdapter,
          Jido.Signal.Dispatch.PidAdapter,
          Jido.Signal.Dispatch.PubSub,
          Jido.Signal.Dispatch.Webhook
        ],
        "Signal Journal": [
          Jido.Signal.Journal,
          Jido.Signal.Journal.Adapters.ETS,
          Jido.Signal.Journal.Adapters.InMemory,
          Jido.Signal.Journal.Persistence
        ],
        Serialization: [
          Jido.Signal.Serialization.Config,
          Jido.Signal.Serialization.ErlangTermSerializer,
          Jido.Signal.Serialization.JsonDecoder,
          Jido.Signal.Serialization.JsonSerializer,
          Jido.Signal.Serialization.ModuleNameTypeProvider,
          Jido.Signal.Serialization.MsgpackSerializer,
          Jido.Signal.Serialization.Serializer,
          Jido.Signal.Serialization.TypeProvider
        ],
        "System Infrastructure": [
          Jido.Signal.Application,
          Jido.Signal.Registry,
          Jido.Signal.Registry.Subscription,
          Jido.Signal.Topology,
          Jido.Signal.Topology.ProcessNode
        ],
        "Errors & Exceptions": [
          Jido.Signal.Error.DispatchError,
          Jido.Signal.Error.Execution,
          Jido.Signal.Error.ExecutionFailureError,
          Jido.Signal.Error.Internal,
          Jido.Signal.Error.Internal.UnknownError,
          Jido.Signal.Error.InternalError,
          Jido.Signal.Error.Invalid,
          Jido.Signal.Error.InvalidInputError,
          Jido.Signal.Error.Routing,
          Jido.Signal.Error.RoutingError,
          Jido.Signal.Error.Timeout,
          Jido.Signal.Error.TimeoutError
        ]
      ]
    ]
  end

  def package do
    [
      files: ["lib", "mix.exs", "README*", "LICENSE*", "CHANGELOG*", "usage-rules.md"],
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
      {:splode, "~> 0.2.9"},

      # Development & Test Dependencies
      {:credo, "~> 1.7", only: [:dev, :test]},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.21", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18.3", only: [:dev, :test]},
      {:expublish, "~> 2.7", only: [:dev], runtime: false},
      {:mix_test_watch, "~> 1.0", only: [:dev, :test], runtime: false},
      {:mimic, "~> 2.0", only: :test},
      {:quokka, "~> 2.10", only: [:dev, :test], runtime: false},
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
