defmodule Erlex.MixProject do
  use Mix.Project

  @version "VERSION" |> File.read!() |> String.trim()
  @elixir_version System.version() |> Version.parse!()
  @erlang_version :erlang.system_info(:otp_release) |> List.to_string() |> String.to_integer()
  # Path.join([
  #   :code.root_dir(),
  #   "releases",
  #   :erlang.system_info(:otp_release),
  #   "OTP_VERSION"
  # ])
  # |> File.read!()
  # |> String.trim()
  # |> String.split(".")
  # |> Stream.unfold(fn
  #   [] -> nil
  #   [head | tail] -> {head, tail}
  # end)
  # |> Stream.concat(Stream.repeatedly(fn -> 0 end))
  # |> Enum.take(3)
  # |> Enum.join(".")
  # |> Version.parse!()

  @name "Erlex"
  @description "Convert Erlang style structs and error messages to equivalent Elixir."

  @maintainers ["Chris Keele"]
  @authors ["Andrew Summers"]

  @github_url "https://github.com/christhekeele/erlex"
  @homepage_url @github_url

  @dev_envs [:dev, :test]

  def project do
    [
      # Application
      app: :erlex,
      elixir: "~> 1.6",
      # elixirc_options: [debug_info: Mix.env() in @dev_envs],
      start_permanent: Mix.env() == :prod,
      compilers: [:leex, :yecc] ++ Mix.compilers(),
      version: @version,
      # Informational
      name: @name,
      description: @description,
      source_url: @github_url,
      homepage_url: @homepage_url,
      # Configuration
      aliases: aliases(),
      deps: deps(),
      docs: docs(),
      dialyzer: dialyzer(),
      package: package(),
      # pre 1.16 cli env mechanism
      preferred_cli_env: preferred_cli_env(),
      test_coverage: test_coverage()
    ]
  end

  # post 1.16 cli env mechanism
  def cli do
    [preferred_envs: preferred_cli_env()]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp aliases do
    [
      ####
      # Developer tools
      ###

      # Installation tasks
      install: [
        "install.rebar",
        "install.hex",
        "install.deps"
      ],
      "install.rebar": "local.rebar --force",
      "install.hex": "local.hex --force",
      "install.deps": "deps.get",

      # Build tasks
      build: [
        "compile",
        "typecheck.build-cache"
      ],

      # Clean tasks
      clean: [
        &clean_extra_folders/1,
        "typecheck.clean",
        &clean_build_folders/1
      ],

      ####
      # Quality control tools
      ###

      # Check-all task
      check: [
        "test",
        "lint"
        # "typecheck"
      ],

      # Linting tasks
      lint: [
        "lint.compile",
        "lint.deps",
        "lint.format",
        "lint.style"
      ],
      "lint.compile": "compile --force --warnings-as-errors",
      "lint.deps": "deps.unlock --check-unused",
      "lint.format": "format --check-formatted",
      "lint.style": "credo --strict",

      # Typecheck tasks
      typecheck: [
        "typecheck.run"
      ],
      "typecheck.build-cache": "dialyzer --plt --format dialyxir",
      "typecheck.clean": "dialyzer.clean",
      "typecheck.explain": "dialyzer.explain --format dialyxir",
      "typecheck.run": "dialyzer --format dialyxir",

      # Test tasks
      "test.coverage": "coveralls",
      "test.coverage.report": "coveralls.github"
    ]
  end

  defp dialyzer do
    [
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
      plt_core_path: "priv/plts",
      flags:
        ["-Wunmatched_returns", "-Wno_opaque", :error_handling, :underspecs] ++
          if @erlang_version < 25 do
            [:race_conditions]
          else
            []
          end,
      ignore_warnings: "dialyzer.ignore_warnings.exs",
      list_unused_filters: true,
      plt_add_apps: [:mix, :erts, :kernel, :stdlib],
      plt_ignore_apps: []
    ]
  end

  defp deps() do
    [
      # {:dialyxir, "~> 1.4", only: @dev_envs, runtime: false, override: true}, # Transative dependency on ErlEx
      {:excoveralls, "~> 0.18", only: :test},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ] ++ deps(:credo) ++ deps(:nimble_parsec)
  end

  defp deps(:credo) do
    cond do
      Version.match?(@elixir_version, "< 1.7.0") ->
        [{:credo, "< 1.5.0", only: @dev_envs, runtime: false}]

      Version.match?(@elixir_version, "< 1.10.0") ->
        [{:credo, "< 1.7.0", only: @dev_envs, runtime: false}]

      Version.match?(@elixir_version, "< 1.13.0") ->
        [{:credo, "< 1.7.7", only: @dev_envs, runtime: false}]

      true ->
        [{:credo, ">= 1.7.7", only: @dev_envs, runtime: false}]
    end
  end

  defp deps(:nimble_parsec) do
    cond do
      Version.match?(@elixir_version, "< 1.12.0") ->
        [{:nimble_parsec, "< 1.4.0", only: @dev_envs, override: true, runtime: false}]

      true ->
        [{:nimble_parsec, ">= 1.4.0", only: @dev_envs, runtime: false}]
    end
  end

  defp docs() do
    [
      main: "readme",
      source_url: @github_url,
      source_ref: @version,
      homepage_url: @homepage_url,
      authors: @authors,
      extras: ["CHANGELOG.md", "README.md"]
    ]
  end

  defp package do
    [
      files: [
        "lib",
        "mix.exs",
        "README.md",
        "LICENSE.md",
        "VERSION",
        "src/erlex_lexer.xrl",
        "src/erlex_parser.yrl"
      ],
      maintainers: @maintainers,
      licenses: ["Apache-2.0"],
      links: %{
        "Changelog" => "https://hexdocs.pm/erlex/changelog.html",
        "GitHub" => @github_url
      }
    ]
  end

  defp test_coverage do
    [
      tool: ExCoveralls
    ]
  end

  defp preferred_cli_env do
    test_by_default = aliases() |> Keyword.keys() |> Enum.map(&{&1, :test})
    dev_overrides = ["docs", "hex.publish"] |> Enum.map(&{&1, :dev})

    test_by_default ++ dev_overrides
  end

  defp clean_build_folders(_) do
    ~w[_build deps] |> Enum.map(&File.rm_rf!/1)
  end

  defp clean_extra_folders(_) do
    ~w[cover doc] |> Enum.map(&File.rm_rf!/1)
  end
end
