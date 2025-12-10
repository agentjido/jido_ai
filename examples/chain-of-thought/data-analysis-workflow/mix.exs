defmodule DataAnalysisWorkflow.MixProject do
  use Mix.Project

  def project do
    [
      app: :data_analysis_workflow,
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
      {:jido_ai, path: "../../.."}
    ]
  end
end
