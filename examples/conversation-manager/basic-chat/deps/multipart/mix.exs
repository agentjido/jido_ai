defmodule Multipart.MixProject do
  use Mix.Project

  @version "0.4.0"

  def project do
    [
      app: :multipart,
      version: @version,
      elixir: "~> 1.12",
      name: "Multipart",
      source_url: "https://github.com/breakroom/multipart",
      description: "Multipart message generator",
      package: package(),
      deps: deps(),
      docs: docs()
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      maintainers: ["Tom Taylor"],
      links: %{"GitHub" => "https://github.com/breakroom/multipart"}
    ]
  end

  defp docs do
    [
      source_ref: "v#{@version}"
    ]
  end

  def application do
    [
      extra_applications: [:logger, :inets, :ssl]
    ]
  end

  defp deps do
    [
      {:mime, "~> 1.2 or ~> 2.0"},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end
end
