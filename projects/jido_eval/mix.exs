defmodule JidoEval.MixProject do
  use Mix.Project

  def project do
    [
      app: :jido_eval,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {JidoEval.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Jido
      jido_dep(:jido_ai, "../jido_ai", "~> 0.5.0"),

      # Core
      {:typed_struct, "~> 0.3.0"},
      {:nimble_csv, "~> 1.2"},

      # Testing
      {:credo, "~> 1.7", only: [:dev, :test]},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.22.0", only: [:dev, :test]},
      {:ex_check, "~> 0.12", only: [:dev, :test]},
      {:ex_doc, "~> 0.37-rc", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18.5", only: [:dev, :test]},
      {:expublish, "~> 2.5", only: [:dev], runtime: false},
      {:git_ops, "~> 2.5", only: [:dev, :test]},
      {:igniter, "~> 0.5", only: [:dev, :test]},
      {:mimic, "~> 2.0", only: [:dev, :test]},
      {:mix_audit, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:mix_test_watch, "~> 1.0", only: [:dev, :test], runtime: false},
      {:quokka, "~> 2.10", only: [:dev, :test], runtime: false},
      {:sobelow, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:stream_data, "~> 1.1", only: [:dev, :test]}
    ]
  end

  defp aliases do
    [
      # test: "test --trace",
      docs: "docs -f html --open",
      playground: "jido.ai.playground",
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
end
