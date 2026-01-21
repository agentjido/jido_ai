defmodule Dotenvy.MixProject do
  use Mix.Project

  @source_url "https://github.com/fireproofsocks/dotenvy"
  @version "1.1.1"

  def project do
    [
      app: :dotenvy,
      name: "Dotenvy",
      description: description(),
      version: @version,
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      package: package(),
      elixirc_paths: elixirc_paths(Mix.env()),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [coveralls: :test, "coveralls.detail": :test],
      build_per_environment: false,
      docs: [
        main: "readme",
        source_ref: "v#{@version}",
        source_url: @source_url,
        logo: "assets/logo.png",
        extras: extras(),
        groups_for_extras: groups_for_extras(),
        skip_undefined_reference_warnings_on: ["CHANGELOG.md"]
      ]
    ]
  end

  def extras do
    [
      "README.md",
      "docs/guides/getting_started.md",
      "docs/guides/releases.md",
      "docs/guides/phoenix.md",
      "docs/guides/minimal.md",
      "docs/guides/livebooks.md",
      "docs/guides/flyio.md",
      "docs/guides/1password.md",
      "docs/cheatsheets/cheatsheet.cheatmd",
      "docs/reference/philosophy.md",
      "docs/reference/dotenv-file-format.md",
      "docs/reference/configuration_providers.md",
      "docs/reference/generators.md",
      "CHANGELOG.md"
    ]
  end

  defp groups_for_extras do
    [
      Guides: ~r/guides\/[^\/]+\.md/,
      Cheatsheets: ~r/guides\/cheatsheets\/.?/,
      "Extra Info": ~r/reference\/[^\/]+\.md/
    ]
  end

  defp description do
    """
    A port of the original dotenv Ruby gem, for mix and releases.
    Facilitates runtime config per the 12-factor App.
    """
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp package do
    [
      maintainers: ["Everett Griffiths"],
      licenses: ["Apache-2.0"],
      logo: "assets/logo.png",
      links: links(),
      files: [
        "lib",
        "assets/logo.png",
        "mix.exs",
        "README*",
        "CHANGELOG*",
        "LICENSE*"
      ]
    ]
  end

  def links do
    %{
      "GitHub" => @source_url,
      "Readme" => "#{@source_url}/blob/v#{@version}/README.md",
      "Changelog" => "#{@source_url}/blob/v#{@version}/CHANGELOG.md",
      "Sponsor" => "https://github.com/sponsors/fireproofsocks"
    }
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp aliases do
    [
      lint: ["format --check-formatted", "credo --strict"]
    ]
  end

  defp deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:ex_doc, "~> 0.39", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18", only: [:dev, :test], runtime: false},
      {:mox, "~> 1.2", only: [:test]}
    ]
  end
end
