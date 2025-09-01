defmodule JidoHtn.MixProject do
  use Mix.Project

  def project do
    [
      app: :jido_htn,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      aliases: aliases()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:deep_merge, "~> 1.0"},
      {:ex_dbug, "~> 2.0"},
      {:proper_case, "~> 1.3"},
      {:private, "~> 0.1.2"},
      jido_dep(:jido, "../jido", "~> 1.3.0"),
      jido_dep(:jido_action, "../jido_action", "~> 1.3.0"),

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
