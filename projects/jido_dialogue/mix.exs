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
      {:elixir_uuid, "~> 1.2"},
      {:jido, path: "../jido"},
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
end
