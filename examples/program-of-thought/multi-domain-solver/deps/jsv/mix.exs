defmodule JSV.MixProject do
  use Mix.Project

  @source_url "https://github.com/lud/jsv"
  @version "0.13.1"
  @jsts_ref "a247442bca7a4798ab6187e035200feacd5423ed"

  def project do
    [
      app: :jsv,
      description: "A JSON Schema Validator with complete support for the latest specifications.",
      version: @version,
      elixir: "~> 1.15",
      # no protocol consolidation for the generation of the test suite
      consolidate_protocols: false,
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      source_url: @source_url,
      docs: docs(),
      package: package(),
      modkit: modkit(),
      dialyzer: dialyzer(),
      versioning: versioning()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test) do
    ["lib", "test/support"]
  end

  defp elixirc_paths(:dev) do
    ["lib", "dev"]
  end

  defp elixirc_paths(_) do
    ["lib"]
  end

  defp deps do
    [
      # Actual dependencies
      {:nimble_options, "~> 1.0"},

      # Optional JSON support
      {:jason, "~> 1.0", optional: true},
      {:poison, ">= 3.0.0 and < 7.0.0", optional: true},
      {:decimal, "~> 2.0", optional: true},

      # Optional Formats
      {:abnf_parsec, "~> 2.0"},
      {:texture, "~> 0.3"},
      {:idna, "~> 6.1"},

      # Dev
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:readmix, "~> 0.6", only: [:dev, :test], runtime: false},

      # Test
      {:briefly, "~> 0.5.1", only: :test},
      {:patch, "~> 0.16.0", only: :test},
      {:ex_check, "~> 0.16.0", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:mox, "~> 1.2", only: :test},

      # JSON Schema Test Suite
      json_schema_test_suite(),
      {:modkit, "~> 0.8.0", only: [:dev, :test], runtime: false}
    ]
  end

  defp json_schema_test_suite do
    {:json_schema_test_suite,
     git: "https://github.com/json-schema-org/JSON-Schema-Test-Suite.git",
     ref: @jsts_ref,
     only: [:dev, :test],
     compile: false,
     app: false}
  end

  defp docs do
    [
      main: "JSV",
      extra_section: "GUIDES",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: doc_extras(),
      groups_for_extras: groups_for_extras(),
      groups_for_modules: groups_for_modules(),
      nest_modules_by_prefix: [JSV.Vocabulary]
    ]
  end

  def doc_extras do
    existing_guides = Path.wildcard("guides/**/*.md")

    defined_guides = [
      "CHANGELOG.md",
      # Schemas
      "guides/schemas/defining-schemas.md",
      "guides/schemas/cast-functions.md",
      # Build
      "guides/build/build-basics.md",
      "guides/build/resolvers.md",
      "guides/build/vocabularies.md",
      # Validation
      "guides/validation/validation-basics.md",
      "guides/validation/decimal-support.md",
      # Dev Log
      "guides/dev-log/api-changes-v0.9.md"
    ]

    case existing_guides -- defined_guides do
      [] ->
        :ok
        defined_guides

      missed ->
        IO.warn("""

        unreferenced guides

        #{Enum.map(missed, &[inspect(&1), ",\n"])}


        """)

        defined_guides ++ missed
    end
  end

  defp groups_for_extras do
    [
      Schemas: ~r/guides\/schemas\/.?/,
      Build: ~r/guides\/build\/.?/,
      Validation: ~r/guides\/validation\/.?/,
      "Dev Log": ~r/guides\/dev-log\/.?/
    ]
  end

  defp groups_for_modules do
    [
      "Main API": [JSV],
      "Schema Definition": [JSV.Schema, JSV.Schema.Helpers],
      Build: [JSV.FormatValidator, JSV.BuildError],
      Validation: [JSV.Root, JSV.ValidationError],
      Resolvers: [JSV.Resolver, JSV.Resolver.Httpc, JSV.Resolver.Embedded, JSV.Resolver.Internal, JSV.Resolver.Local],
      Vocabulary: [JSV.Vocabulary, ~r/^JSV\.Vocabulary\./],
      Utilities: [
        JSV.Normalizer,
        JSV.Normalizer.Normalize,
        JSV.Codec,
        JSV.Helpers.MapExt,
        JSV.Helpers.Traverse,
        JSV.Schema.Composer
      ],
      Internal: ~r/.*/
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "Github" => @source_url,
        "Changelog" => "https://github.com/lud/jsv/blob/main/CHANGELOG.md"
      }
    ]
  end

  def cli do
    [
      preferred_envs: [
        dialyzer: :test
      ]
    ]
  end

  defp dialyzer do
    [
      flags: [:unmatched_returns, :error_handling, :unknown, :extra_return],
      list_unused_filters: true,
      plt_add_deps: :app_tree,
      plt_add_apps: [:ex_unit, :inets],
      plt_local_path: "_build/plts"
    ]
  end

  defp modkit do
    [
      mount: [
        {JSV, "lib/jsv"},
        {JSV.DocGen, "dev/doc_gen"}
      ]
    ]
  end

  defp versioning do
    [
      annotate: true,
      before_commit: [
        &readmix/1,
        {:add, "README.md"},
        {:add, "guides"},
        &gen_changelog/1,
        {:add, "CHANGELOG.md"}
      ]
    ]
  end

  def readmix(vsn) do
    rdmx = Readmix.new(vars: %{app_vsn: vsn})
    :ok = Readmix.update_file(rdmx, "README.md")

    :ok =
      Enum.each(Path.wildcard("guides/**/*.md"), fn path ->
        :ok = Readmix.update_file(rdmx, path)
      end)
  end

  defp gen_changelog(vsn) do
    case System.cmd("git", ["cliff", "--tag", vsn, "-o", "CHANGELOG.md"], stderr_to_stdout: true) do
      {_, 0} -> IO.puts("Updated CHANGELOG.md with #{vsn}")
      {out, _} -> {:error, "Could not update CHANGELOG.md:\n\n #{out}"}
    end
  end
end
