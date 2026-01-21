defmodule ServerSentEvents.MixProject do
  use Mix.Project

  @version "0.2.1"

  @github_repo_url "https://github.com/benjreinhart/server_sent_events"

  @description "Lightweight, ultra-fast Server Sent Event parser"

  def project do
    [
      app: :server_sent_events,
      version: @version,
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      name: "Server Sent Events",
      description: @description,
      source_url: @github_repo_url,
      homepage_url: @github_repo_url,
      package: package(),
      deps: deps(),
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  def description do
    @description
  end

  defp package do
    [
      maintainers: ["Ben Reinhart"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => @github_repo_url
      }
    ]
  end

  defp deps do
    [
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  defp docs do
    [
      main: "readme",
      source_url: @github_repo_url,
      source_ref: "v#{@version}",
      extras: [
        "README.md",
        "CHANGELOG.md"
      ]
    ]
  end
end
