defmodule SimpleMathReasoning.MixProject do
  use Mix.Project

  def project do
    [
      app: :simple_math_reasoning,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      # Use jido_ai from parent directory
      {:jido_ai, path: "../../.."}
    ]
  end
end
