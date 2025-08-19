defmodule Jido.Chat.MixProject do
  use Mix.Project

  @version "0.5.0"

  def project do
    [
      app: :jido_chat,
      version: @version,
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),

      # Docs
      name: "JidoChat",
      description:
        "A structured chat room system supporting human and agent participants with customizable turn-taking strategies.",
      source_url: "https://github.com/agentjido/jido_chat",
      homepage_url: "https://github.com/agentjido/jido_chat",
      package: package(),
      docs: docs(),

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

  def application do
    [
      extra_applications: [:logger],
      mod: {Jido.Chat.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: "https://github.com/agentjido/jido_chat",
      extra_section: "Guides",
      extras: [
        {"README.md", title: "Home"},
        {"guides/getting-started.livemd", title: "Getting Started"},
        {"guides/architecture.md", title: "Architecture"},
        {"CONTRIBUTING.md", title: "Contributing"},
        {"LICENSE.md", title: "License"},
        {"CHANGELOG.md", title: "Changelog"}
      ],
      groups_for_modules: [
        Core: [
          Jido.Chat,
          Jido.Chat.Message,
          Jido.Chat.Message.Parser,
          Jido.Chat.Message.Parser.Mention,
          Jido.Chat.Participant,
          Jido.Chat.ParticipantRef
        ],
        "Room Management": [
          Jido.Chat.Application,
          Jido.Chat.Room,
          Jido.Chat.Room.State,
          Jido.Chat.Room.Strategy,
          Jido.Chat.Supervisor
        ],
        "Channel System": [
          Jido.Chat.Channel,
          Jido.Chat.Channels.IExChannel,
          Jido.Chat.Channels.IExChannel.Server,
          Jido.Chat.Channels.IExChannel.Server.State
        ]
      ],
      # Hide modules from the sidebar
      groups_for_extras: [
        Guides: [
          "guides/getting-started",
          "guides/architecture"
        ],
        About: [
          "CONTRIBUTING.md",
          "LICENSE.md",
          "CHANGELOG.md"
        ]
      ],
      sidebar_items: [
        Guides: [
          "guides/getting-started",
          "guides/architecture"
        ]
      ]
    ]
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README.md", "LICENSE.md"],
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => "https://github.com/agentjido/jido_chat"
      }
    ]
  end

  defp deps do
    [
      {:jido, path: "../jido"},
      {:jido_ai, path: "../jido_ai"},
      {:nimble_parsec, "~> 1.4"},
      {:typed_struct, "~> 0.3.0"},

      # Testing
      {:credo, "~> 1.7"},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:doctor, "~> 0.22.0", only: [:dev, :test]},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18.3", only: [:dev, :test]},
      {:expublish, "~> 2.5", only: [:dev], runtime: false},
      {:mix_test_watch, "~> 1.0", only: [:dev, :test], runtime: false},
      {:mimic, "~> 1.7", only: [:dev, :test]},
      {:stream_data, "~> 1.1", only: [:dev, :test]}
    ]
  end

  defp aliases do
    [
      # test: "test --trace",
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
end
