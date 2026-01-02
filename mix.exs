defmodule JidoAi.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/agentjido/jido_ai"

  def project do
    [
      app: :jido_ai,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      description: "Jido Actions and Workflows for interacting with LLMs",
      package: package(),
      docs: docs(),
      name: "Jido Ai",
      source_url: @source_url
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
      {:jido, path: "../jido"},
      {:instructor, github: "thmsmlr/instructor_ex"},

      # Testing
      {:ex_doc, "~> 0.24", only: :dev, runtime: false},
      {:mimic, "~> 1.10"}
    ]
  end

  defp aliases do
    [
      test: "test --trace"
    ]
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README.md", "LICENSE"],
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
      extras: ["README.md"]
    ]
  end
end
