defmodule Uniq.MixProject do
  use Mix.Project

  def project do
    [
      app: :uniq,
      version: "0.6.2",
      elixir: "~> 1.13",
      description: description(),
      package: package(),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      elixirc_paths: elixirc_paths(Mix.env()),
      preferred_cli_env: [
        bench: :bench,
        docs: :docs,
        "hex.publish": :docs
      ],
      name: "Uniq",
      source_url: "https://github.com/bitwalker/uniq",
      homepage_url: "http://github.com/bitwalker/uniq",
      docs: [
        main: "readme",
        api_reference: false,
        extra_section: "Extras",
        extras: [
          {:"README.md", [title: "About"]},
          "guides/using_with_ecto.md",
          "guides/migration_from_elixir_uuid.md",
          {:"LICENSE.md", [title: "License"]}
        ]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {Uniq.App, []},
      extra_applications: [:crypto]
    ]
  end

  defp aliases do
    [bench: &run_bench/1]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp run_bench([]) do
    for file <- Path.wildcard("bench/*.exs") do
      Mix.Task.run("run", [file])
    end
  end

  defp run_bench([file]) do
    Mix.Task.run("run", [file])
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:benchee, "~> 1.0", only: [:bench]},
      {:ecto, "~> 3.0", optional: true},
      {:ex_doc, "> 0.0.0", only: [:docs], runtime: false},
      {:elixir_uuid, "> 0.0.0", only: [:bench]},
      {:stream_data, "~> 0.5", only: [:test]}
    ]
  end

  defp description do
    "Provides UUID generation, parsing, and formatting. Supports RFC 4122, and the v6 draft extension"
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README.md", "LICENSE.md"],
      maintainers: ["Paul Schoenfelder"],
      licenses: ["Apache-2.0"],
      links: %{
        GitHub: "https://github.com/bitwalker/uniq"
      }
    ]
  end
end
