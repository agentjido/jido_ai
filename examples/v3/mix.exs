defmodule JidoAI.V3Examples.MixProject do
  use Mix.Project

  def project do
    [
      app: :jido_ai_v3_examples,
      version: "0.1.0",
      build_path: "../../_build/v3_acceptance/build",
      deps_path: "../../_build/v3_acceptance/deps",
      elixir: "~> 1.18",
      elixirc_paths: ["lib", "support"],
      test_ignore_filters: [~r/\/support\//],
      deps: [
        {:jido_ai, path: "../.."},
        {:jido, path: "../../../jido", override: true},
        {:jido_action, path: "../../../jido_action", override: true},
        {:jido_signal, path: "../../../jido_signal", override: true},
        {:req_llm, "~> 1.22.0"},
        {:jason, "~> 1.4"},
        {:yaml_elixir, "~> 2.12"},
        {:splode, "~> 0.3.0"},
        {:zoi, "~> 0.18"}
      ]
    ]
  end

  def application, do: [extra_applications: [:logger]]
end
