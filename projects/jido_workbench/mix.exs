defmodule JidoWorkbench.MixProject do
  use Mix.Project

  def project do
    [
      app: :jido_workbench,
      version: "0.1.0",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {JidoWorkbench.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    require Logger
    use_local_deps = System.get_env("LOCAL_JIDO_DEPS") == "true" || false
    Logger.info("Using local Jido dependencies: #{inspect(use_local_deps)}")

    deps = [
      {:phoenix, "~> 1.7.17"},
      # {:phoenix_ecto, "~> 4.5"},
      # {:ecto, "~> 3.12", override: true},
      # {:ecto_sql, "~> 3.10"},
      # {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.5", only: [:dev, :test]},
      {:phoenix_live_view, "~> 1.0.1"},
      {:heroicons, github: "tailwindlabs/heroicons", tag: "v2.1.5", app: false, compile: false, sparse: "optimized"},
      {:floki, "~> 0.35"},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.2", runtime: Mix.env() == :dev},
      {:swoosh, "~> 1.5"},
      {:finch, "~> 0.13"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.20"},
      {:jason, "~> 1.2"},
      {:plug_cowboy, "~> 2.5"},
      {:petal_components, "~> 2.8.1"},
      {:plug_canonical_host, "~> 2.0"},
      {:phoenix_seo, "~> 0.1.11"},

      # AI
      {:instructor, "~> 0.1.0", override: true},
      {:langchain, "~> 0.3.1", override: true},

      # Markdown
      {:earmark, "~> 1.4"},
      {:nimble_publisher, "~> 1.1"},
      {:makeup_elixir, "~> 1.0"},
      {:makeup_js, "~> 0.1.0"},
      {:makeup_html, "~> 0.2.0"},

      # Env Vars
      {:dotenvy, "~> 1.0"},

      # Testing
      {:mix_test_watch, "~> 1.0", only: [:dev, :test], runtime: false},
      {:httpoison, "~> 2.0"},
      {:yaml_elixir, "~> 2.9"}
    ]

    if use_local_deps do
      require Logger
      Logger.warning("Using local Jido dependencies")

      deps ++
        [
          {:jido, path: "../jido", override: true},
          # {:jido_chat, path: "../jido_chat", override: true},
          {:jido_ai, path: "../jido_ai", override: true},
          {:jido_tools, path: "../jido_tools", override: true}
          # {:jido_memory, path: "../jido_memory"}
        ]
    else
      deps ++
        [
          {:jido, "~> 1.1.0-rc.2"},
          {:jido_ai, "~> 0.5.0"},
          {:jido_tools, "~> 0.1.0"}
        ]
    end
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "assets.setup", "assets.build"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind default", "esbuild default"],
      "assets.deploy": ["tailwind default --minify", "esbuild default --minify", "phx.digest"]
    ]
  end
end
