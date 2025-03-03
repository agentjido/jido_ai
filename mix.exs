defmodule Jido.Ai.MixProject do
  use Mix.Project

  @version "0.5.0"
  @source_url "https://github.com/agentjido/jido_ai"

  def project do
    [
      app: :jido_ai,
      version: @version,
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      name: "Jido AI",
      description: "Jido Actions and Workflows for interacting with LLMs",
      package: package(),
      docs: docs(),
      source_url: @source_url,
      consolidate_protocols: Mix.env() != :test,

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

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {Jido.AI.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    require Logger
    use_local_deps = System.get_env("LOCAL_JIDO_DEPS") == "true" || false
    Logger.info("Using local Jido dependencies: #{inspect(use_local_deps)}")

    deps = [
      {:typed_struct, "~> 0.3.0"},
      {:dotenvy, "~> 1.0.0"},

      # Clients
      {:req, "~> 0.5.8"},
      {:openai_ex, "~> 0.8.6"},
      {:instructor, "~> 0.1.0"},
      {:langchain, "~> 0.3.1"},

      # Testing
      {:credo, "~> 1.7", only: [:dev, :test]},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:doctor, "~> 0.22.0", only: [:dev, :test]},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18.3", only: [:dev, :test]},
      {:expublish, "~> 2.5", only: [:dev], runtime: false},
      {:mix_test_watch, "~> 1.0", only: [:dev, :test], runtime: false},
      {:mimic, "~> 1.7", only: [:dev, :test]},
      {:stream_data, "~> 1.1", only: [:dev, :test]}
    ]

    if use_local_deps do
      require Logger
      Logger.warning("Using local Jido dependencies")

      deps ++
        [
          {:jido, path: "../jido"}
          # {:jido_memory, path: "../jido_memory"}
        ]
    else
      deps ++
        [
          {:jido, github: "agentjido/jido", branch: "main"}
          # {:jido_memory, github: "agentjido/jido_memory"}
        ]
    end
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

  defp package do
    [
      files: ["lib", "mix.exs", "README.md", "LICENSE.md"],
      maintainers: ["Mike Hostetler"],
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: [
        "README.md",
        "guides/getting-started.md"
      ]
    ]
  end
end
