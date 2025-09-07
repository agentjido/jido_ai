defmodule RenameProject.Mixfile do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/petalframework/rename_project"

  def project do
    [
      app: :rename_project,
      version: @version,
      elixir: "~> 1.14",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      deps: deps(),
      docs: docs(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ]
    ]
  end

  defp description do
    """
    For thoroughly renaming your Elixir projects
    """
  end

  defp package do
    [
      licenses: ["MIT"],
      maintainers: ["PetalFramework"],
      links: %{github: @source_url}
    ]
  end

  defp deps do
    [
      {:excoveralls, "~> 0.6", only: :test},
      {:ex_doc, ">= 0.0.0", only: :dev}
    ]
  end

  defp docs() do
    [
      main: "readme",
      name: "Rename Project",
      source_ref: "v#{@version}",
      canonical: "http://hexdocs.pm/rename_project",
      source_url: @source_url,
      extras: ["README.md"]
    ]
  end
end
