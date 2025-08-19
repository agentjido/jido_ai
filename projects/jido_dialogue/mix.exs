defmodule Jido.Dialogue.MixProject do
  use Mix.Project

  def project do
    [
      app: :jido_dialogue,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    case Mix.env() do
      :test ->
        [
          extra_applications: [:logger],
          mod: {Jido.Dialogue.Application, []},
          start_phases: [start_test_app: []]
        ]

      _ ->
        [
          extra_applications: [:logger],
          mod: {Jido.Dialogue.Application, []}
        ]
    end
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      ws_dep(:jido, "../jido", [github: "agentjido/jido"]),

      {:elixir_uuid, "~> 1.2"},
      {:yaml_elixir, "~> 2.11"},

      # Testing
      {:credo, "~> 1.7"},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:doctor, "~> 0.22.0", only: [:dev, :test]},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18.3", only: [:dev, :test]},
      {:mix_test_watch, "~> 1.0", only: [:dev, :test], runtime: false},
      {:mimic, "~> 1.7", only: [:dev, :test]},
      {:stream_data, "~> 1.1", only: [:dev, :test]}
    ]
  end

  defp aliases do
    [
      test: "test --no-start"
    ]
  end

  # Workspace dependency management helpers
  defp workspace? do
    System.get_env("JIDO_WORKSPACE") in ["1", "true"]
  end

  defp ws_dep(app, rel_path, remote_opts, extra_opts \\ []) do
    if workspace?() and File.dir?(Path.expand(rel_path, __DIR__)) do
      {app, [path: rel_path, override: true] ++ extra_opts}
    else
      {app, remote_opts ++ extra_opts}
    end
  end
end
