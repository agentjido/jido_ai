defmodule AbnfParsec.MixProject do
  use Mix.Project

  @version "2.1.0"

  def project do
    [
      app: :abnf_parsec,
      version: @version,
      elixir: "~> 1.14",
      deps: deps(),
      name: "AbnfParsec",
      description: "ABNF in, parser out",
      source_url: "https://github.com/princemaple/abnf_parsec",
      homepage_url: "https://github.com/princemaple/abnf_parsec",
      package: package(),
      docs: docs(),
      preferred_cli_env: [
        docs: :docs,
        "hex.publish": :docs
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:nimble_parsec, "~> 1.4"},
      {:ex_doc, ">= 0.0.0", only: :docs, runtime: false}
    ]
  end

  defp package do
    [
      files: ~w(lib priv mix.exs README* LICENSE* CHANGELOG*),
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/princemaple/abnf_parsec"}
    ]
  end

  defp docs do
    [
      source_ref: "v#{@version}",
      main: "AbnfParsec",
      canonical: "http://hexdocs.pm/abnf_parsec",
      source_url: "https://github.com/princemaple/abnf_parsec",
      extras: ["CHANGELOG.md", "README.md"]
    ]
  end
end
