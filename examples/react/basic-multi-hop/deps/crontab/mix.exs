defmodule Crontab.Mixfile do
  use Mix.Project

  @source_url "https://github.com/maennchen/crontab"
  @version "1.2.0"

  def project do
    [
      app: :crontab,
      version: @version,
      elixir: "~> 1.15",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      deps: deps(),
      docs: docs(),
      test_coverage: [tool: ExCoveralls],
      dialyzer:
        [plt_add_apps: [:ecto]] ++
          if (System.get_env("DIALYZER_PLT_PRIV") || "false") in ["1", "true"] do
            [plt_file: {:no_warn, "priv/plts/dialyzer.plt"}]
          else
            []
          end
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp description do
    """
    Elixir library for parsing, writing, and calculating Cron format strings.
    """
  end

  defp deps do
    [
      {:doctest_formatter, "~> 0.4.0", only: [:dev, :test], runtime: false},
      {:ecto, "~> 1.0 or ~> 2.0 or ~> 3.0", optional: true},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:excoveralls, "~> 0.5", only: [:test], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev], runtime: false},
      {:credo, "~> 1.0", only: [:dev], runtime: false},
      {:mix_test_watch, "~> 1.1", only: [:dev, :test], runtime: false},
      {:styler, "~> 1.5", only: [:dev, :test], runtime: false},
      {:tz, "~> 0.26", only: [:dev, :test]}
    ]
  end

  defp package do
    [
      name: :crontab,
      files: ["lib", "mix.exs", "README*", "LICENSE*"],
      maintainers: ["Jonatan Männchen"],
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url, "Changelog" => @source_url <> "/releases"}
    ]
  end

  defp docs do
    [
      extras: ["README.md", "docs/cheatsheets/cron_notation.cheatmd"],
      main: "readme",
      source_url: @source_url,
      source_ref: "v" <> @version,
      logo: "assets/logo-compromise.png",
      assets: %{"assets" => "assets"}
    ]
  end
end
