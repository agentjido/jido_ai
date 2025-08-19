defmodule Jido.Character.MixProject do
  use Mix.Project

  def project do
    [
      app: :jido_character,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      # Add this line
      aliases: aliases()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ecto, "~> 3.12"},
      {:ecto_enum, "~> 1.4"},
      {:elixir_uuid, "~> 1.2"},
      {:faker, "~> 0.18.0"},
      {:jason, "~> 1.4"},
      {:typed_ecto_schema, "~> 0.4.1"},

      # Testing
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:mix_test_watch, "~> 1.0", only: [:dev, :test], runtime: false},
      {:stream_data, "~> 1.1", only: [:dev, :test]}
    ]
  end

  # Define aliases
  defp aliases do
    [
      # test: ["test --trace"]
    ]
  end
end
