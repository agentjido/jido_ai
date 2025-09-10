defmodule ReqLLM.MixProject do
  use Mix.Project

  def project do
    [
      app: :req_llm,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      elixirc_paths: elixirc_paths(Mix.env()),
      
      # Documentation
      name: "ReqLLM",
      source_url: "https://github.com/your_org/req_llm",
      homepage_url: "https://github.com/your_org/req_llm",
      docs: [
        main: "readme",
        extras: [
          "README.md",
          "guides/adding_a_provider.md"
        ],
        groups_for_extras: [
          Guides: ~r/guides\/.*/
        ]
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {ReqLLM.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:nimble_options, "~> 1.1"},
      {:typed_struct, "~> 0.3.0"},
      {:splode, "~> 0.2.3"},
      {:server_sent_event, "~> 1.0"},
      {:kagi, path: "../kagi"},

      # Dev/test dependencies
      {:plug, "~> 1.15", only: [:test]},
      {:mimic, "~> 1.7", only: [:test]},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      quality: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "dialyzer",
        "credo --strict"
      ],
      q: ["quality"]
    ]
  end
end
