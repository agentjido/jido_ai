defmodule ProperCase.Mixfile do
  use Mix.Project

  def project do
    [
      app: :proper_case,
      version: "1.3.1",
      elixir: "~> 1.4",
      description: description(),
      package: package(),
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    [applications: [:logger]]
  end

  defp description do
    """
    An Elixir library that converts keys in maps between `snake_case` and `camel_case`.

    Useful as a plug in Phoenix for converting incoming params from JavaScript's `camelCase` to Elixir's `snake_case`
    """
  end

  defp deps do
    [
      {:ex_doc, "~> 0.22.1", only: :dev},
      {:plug, "~> 1.2.2", only: [:test]},
      {:jason, "~> 1.2.1", only: [:test]}
    ]
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README*", "LICENSE"],
      maintainers: ["Johnny Ji", "Shaun Dern"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/johnnyji/proper_case",
        "Docs" => "https://github.com/johnnyji/proper_case"
      }
    ]
  end
end
