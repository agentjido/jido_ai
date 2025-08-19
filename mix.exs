defmodule JidoWorkspace.MixProject do
  use Mix.Project

  def project do
    [
      app: :jido_workspace,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      config_path: "config/workspace.exs"
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    []
  end

  defp aliases do
    [
      morning: ["workspace.pull", "compile"],
      sync: ["workspace.pull", "workspace.test.all"],
      "ws.pull": ["workspace.pull"],
      "ws.push": ["workspace.push"],
      "ws.status": ["workspace.status"],
      "ws.test": ["workspace.test.all"],
      "ws.quality": ["workspace.quality"],
      "ws.deps": ["workspace.deps"],
      "ws.diff": ["workspace.diff"],
      "slidev.dev": ["slidev.dev"],
      "slidev.build": ["slidev.build"],
      "slidev.install": ["slidev.install"],
      "slidev.new": ["slidev.new"]
    ]
  end
end
