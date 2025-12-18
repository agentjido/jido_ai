defmodule TypedStructNimbleOptions.MixProject do
  use Mix.Project

  def project do
    [
      app: :typed_struct_nimble_options,
      version: "0.1.1",
      description: "TypedStruct plugin for validation & documentation with NimbleOptions",
      package: [
        links: %{"GitHub" => "https://github.com/kzemek/typed_struct_nimble_options"},
        licenses: ["Apache-2.0"]
      ],
      source_url: "https://github.com/kzemek/typed_struct_nimble_options",
      docs: [main: "readme", extras: ["README.md", "LICENSE"]],
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    []
  end

  defp deps do
    [
      {:typed_struct, "~> 0.3.0"},
      {:nimble_options, "~> 1.1.1"},
      {:ex_doc, "~> 0.34.2", only: :dev, runtime: false}
    ]
  end
end
