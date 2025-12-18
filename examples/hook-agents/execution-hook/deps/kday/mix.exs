defmodule Kday.MixProject do
  use Mix.Project

  @version "1.1.0"

  def project do
    [
      app: :kday,
      version: @version,
      elixir: "~> 1.11",
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      name: "Kday",
      source_url: "https://github.com/kipcole9/kday",
      docs: docs(),
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      test_coverage: [tool: ExCoveralls],
      aliases: aliases(),
      elixirc_paths: elixirc_paths(Mix.env()),
      dialyzer: [
        ignore_warnings: ".dialyzer_ignore_warnings",
        plt_add_apps: []
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp description do
    """
    Calculations for the first, last or nth day of the week on, nearest, after or before a date.
    """
  end

  defp package do
    [
      maintainers: ["Kip Cole"],
      licenses: ["Apache-2.0"],
      links: links(),
      files: [
        "lib",
        "mix.exs",
        "README*",
        "CHANGELOG*",
        "LICENSE*"
      ]
    ]
  end

  def docs do
    [
      source_ref: "v#{@version}",
      main: "readme",
      logo: "logo.png",
      formatters: ["html"],
      extras: [
        "README.md",
        "LICENSE.md",
        "CHANGELOG.md"
      ],
      skip_undefined_reference_warnings_on: ["changelog", "CHANGELOG.md", "README.md"]
    ]
  end

  def links do
    %{
      "GitHub" => "https://github.com/kipcole9/kday",
      "Readme" => "https://github.com/kipcole9/kday/blob/v#{@version}/README.md",
      "Changelog" =>
        "https://github.com/kipcole9/kday/blob/v#{@version}/CHANGELOG.md"
    }
  end

  defp deps do
    [
      {:ex_doc, "~> 0.21", optional: true, runtime: false},
      {:dialyxir, "~> 1.0", optional: true, only: [:dev, :test], runtime: false}
    ]
  end

  def aliases do
    []
  end

  defp elixirc_paths(:test), do: ["lib", "mix", "test", "test/support"]
  defp elixirc_paths(:dev), do: ["lib", "mix", "bench"]
  defp elixirc_paths(_), do: ["lib"]
end
