defmodule TelemetryRegistry.MixProject do
  use Mix.Project

  def project do
    {app, desc} = load_app()
    config = load_config()

    [
      app: app,
      version: version(Keyword.fetch!(desc, :vsn)),
      description: to_string(Keyword.fetch!(desc, :description)),
      elixir: "~> 1.8",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(Keyword.fetch!(config, :deps)),
      name: "Telemetry Registry",
      source_url: "https://github.com/beam-telemetry/telemetry_registry",
      docs: [
        main: "TelemetryRegistry",
        # logo: "path/to/logo.png",
        extras: erlang_docs()
      ],
      aliases: [
        # when build docs first build edocs with rebar3
        docs: ["cmd rebar3 edoc", "docs"]
      ],
      package: package()
    ]
  end

  defp version(version) when is_list(version) do
    List.to_string(version)
  end

  defp version({:file, path}) do
    path
    |> File.read!()
    |> String.trim()
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps(rebar) do
    rebar
    |> Enum.map(fn
      {dep, version} -> {dep, to_string(version)}
      dep when is_atom(dep) -> {dep, ">= 0.0.0"}
    end)
    |> Enum.concat([
      {:ex_doc, "~> 0.29", only: :dev, runtime: false}
    ])
  end

  defp package() do
    [
      description: "Registry and helpers for Telemetry events",
      build_tools: ["rebar3", "mix"],
      files:
        ~w(lib mix.exs README.md LICENSE CODEOWNERS rebar.config rebar.lock VERSION src .formatter.exs),
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/beam-telemetry/telemetry_registry"}
    ]
  end

  def erlang_docs() do
    files =
      for file <- Path.wildcard("edoc/*.md"),
          file != "edoc/README.md",
          do: {String.to_atom(file), [title: Path.basename(file, ".md")]}

    [{:"README.md", [title: "Overview"]} | files]
  end

  defp load_config do
    {:ok, config} = :file.consult("rebar.config")

    config
  end

  defp load_app do
    {:ok, [{:application, name, desc}]} = :file.consult("src/telemetry_registry.app.src")

    {name, desc}
  end
end
