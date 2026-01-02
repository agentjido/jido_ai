defmodule JidoAi.MixProject do
  use Mix.Project

  @version "2.0.0"
  @source_url "https://github.com/agentjido/jido_ai"
  @description "AI integration layer for the Jido ecosystem - Actions, Workflows, and LLM orchestration"

  def project do
    [
      app: :jido_ai,
      version: @version,
      elixir: "~> 1.17",
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
        summary: [threshold: 90]
      ],

      # Dialyzer
      dialyzer: [
        plt_local_path: "priv/plts/project.plt",
        plt_core_path: "priv/plts/core.plt"
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
    jido_deps() ++ runtime_deps() ++ dev_test_deps()
  end

  defp jido_deps do
    [
      jido_dep(:req_llm, "../req_llm", "~> 1.2")
    ]
  end

  defp runtime_deps do
    [
      {:jason, "~> 1.4"},
      {:nimble_options, "~> 1.1"},
      {:splode, "~> 0.2.4"},
      {:typedstruct, "~> 0.5"},
      {:uniq, "~> 0.6"},
      {:zoi, "~> 0.14"}
    ]
  end

  defp dev_test_deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18", only: [:dev, :test]},
      {:git_hooks, "~> 0.8", only: [:dev, :test], runtime: false},
      {:git_ops, "~> 2.9", only: :dev, runtime: false},
      {:mimic, "~> 2.0", only: :test},
      {:quokka, "~> 2.10", only: [:dev, :test], runtime: false},
      {:stream_data, "~> 1.0", only: [:dev, :test]}
    ]
  end

  defp jido_dep(app, rel_path, hex_req, extra_opts \\ []) do
    path = Path.expand(rel_path, __DIR__)

    if File.dir?(path) and File.exists?(Path.join(path, "mix.exs")) do
      {app, Keyword.merge([path: rel_path, override: true], extra_opts)}
    else
      {app, hex_req, extra_opts}
    end
    |> case do
      {app, opts} when is_list(opts) -> {app, opts}
      {app, req, opts} -> {app, req, opts}
    end
  end

  defp aliases do
    [
      setup: ["deps.get", "git_hooks.install"],
      test: "test --exclude flaky",
      q: ["quality"],
      quality: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "credo --min-priority higher",
        "dialyzer"
      ],
      docs: "docs -f html"
    ]
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README.md", "LICENSE", "CHANGELOG.md", "usage-rules.md"],
      maintainers: ["Mike Hostetler"],
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
        "CHANGELOG.md",
        "CONTRIBUTING.md"
      ],
      groups_for_modules: [
        Core: [
          Jido.AI,
          Jido.AI.Error
        ]
      ]
    ]
  end
end
