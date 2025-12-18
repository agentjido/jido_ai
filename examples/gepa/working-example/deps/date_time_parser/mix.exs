defmodule DateTimeParser.MixProject do
  use Mix.Project
  @version "1.3.0"

  def project do
    [
      app: :date_time_parser,
      name: "DateTimeParser",
      version: @version,
      homepage_url: "https://hexdocs.pm/date_time_parser",
      source_url: "https://github.com/dbernheisel/date_time_parser",
      elixir: ">= 1.12.0",
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases(),
      package: package(),
      docs: docs(),
      start_permanent: Mix.env() == :prod,
      preferred_cli_env: [
        tests: :test,
        benchmark: :bench,
        profile: :bench
      ],
      deps: deps(),
      description: "Parse a string into DateTime, NaiveDateTime, Time, or Date struct."
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp package do
    [
      files: [
        "lib",
        "mix.exs",
        "CODE_OF_CONDUCT*",
        "CHANGELOG*",
        "README*",
        "LICENSE*",
        "EXAMPLES*",
        "priv/tzdata*/*"
      ],
      maintainers: ["David Bernheisel"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/dbernheisel/date_time_parser",
        "Readme" => "https://github.com/dbernheisel/date_time_parser/blob/#{@version}/README.md",
        "Changelog" =>
          "https://github.com/dbernheisel/date_time_parser/blob/#{@version}/CHANGELOG.md"
      }
    ]
  end

  defp deps() do
    [
      {:exprof, "~> 0.2.0", only: :bench},
      {:kday, "~> 1.0", runtime: false},
      {:benchee, "~> 1.0", only: [:bench], runtime: false},
      {:tz, "~> 0.24", only: [:dev, :test, :bench], runtime: false},
      {:credo, "~> 1.1", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.20", only: :dev, runtime: false},
      {:nimble_parsec, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp docs() do
    [
      main: "DateTimeParser",
      source_ref: @version,
      extras: [
        "pages/Future-UTC-DateTime.md",
        "CHANGELOG.md",
        "EXAMPLES.livemd",
        "LICENSE.md"
      ]
    ]
  end

  defp tests() do
    []
    |> add_if("compile --force --warnings-as-errors", !System.get_env("CI"))
    |> add_if("compile.nimble", !System.get_env("CI"))
    |> add_if("format --check-formatted", true)
    |> add_if("credo --strict", true)
    |> add_if("test", true)
  end

  defp aliases() do
    [
      "compile.nimble": [
        "cmd rm -f lib/combinators.ex",
        "nimble_parsec.compile lib/combinators.ex.exs",
        "compile"
      ],
      tests: tests(),
      profile: ["run bench/profile.exs"],
      benchmark: [
        "run bench/self.exs",
        "cmd ruby bench/ruby.rb",
        "cmd ruby bench/rails.rb"
      ]
    ]
  end

  defp add_if(commands, command, true), do: commands ++ [command]
  defp add_if(commands, _command, ""), do: commands

  defp add_if(commands, command, version) when is_binary(version) do
    add_if(commands, command, Version.match?(System.version(), version))
  end

  defp add_if(commands, _command, _), do: commands
end
