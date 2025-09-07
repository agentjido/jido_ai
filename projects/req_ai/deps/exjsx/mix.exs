defmodule EXJSX.Mixfile do
  use Mix.Project

  def project do
    [ app: :exjsx,
      version: "4.0.0",
      elixir: ">= 0.13.3",
      consolidate_protocols: Mix.env != :test,
      description: description(),
      package: package(),
      deps: deps()
    ]
  end

  # Configuration for the OTP application
  def application do
    [applications: [:jsx]]
  end

  defp deps do
    [{:jsx, "~> 2.8.0"}, {:ex_doc, "~> 0.14", only: :dev}]
  end

  defp description do
    """
    json for elixir
    """
  end

  defp package do
    [
      files: ["lib", "LICENSE", "mix.exs", "README.md"],
      contributors: [
        "alisdair sullivan",
        "devin torres",
        "eduardo gurgel",
        "d0rc",
        "igor kapkov",
        "parroty",
        "yurii rashkovskii"
      ],
      maintainers: ["@talentdeficit"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/talentdeficit/exjsx"}
    ]
  end
end
