defmodule ExDbug.MixProject do
  use Mix.Project

  @version "2.1.0"

  def project do
    [
      app: :ex_dbug,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),

      # Docs
      name: "ExDbug",
      description: "Debug utility for Elixir, inspired by Node.js debug package",
      source_url: "https://github.com/mikehostetler/ex_dbug",
      homepage_url: "https://github.com/mikehostetler/ex_dbug",
      package: package(),
      docs: docs()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp docs do
    [
      main: "ExDbug",
      source_ref: "v#{@version}",
      source_url: "https://github.com/mikehostetler/ex_dbug",
      extras: ["README.md"]
    ]
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README.md", "LICENSE.md"],
      maintainers: ["Mike Hostetler"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/mikehostetler/ex_dbug"
      }
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Testing
      {:credo, "~> 1.7", only: [:dev, :test]},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_check, "~> 0.16.0", only: [:dev, :test]},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:git_ops, "~> 2.7", only: [:dev, :test]},
      {:mix_test_watch, "~> 1.2", only: [:dev, :test]}
    ]
  end
end
