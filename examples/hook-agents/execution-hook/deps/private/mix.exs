defmodule Private.Mixfile do
  use Mix.Project

  @deps     [
    { :ex_doc, ">= 0.0.0", only: :dev}
  ]
  @version    "0.1.2"
  @name       :private
  @source_url "https://github.com/pragdave/private"
  
  @doc_info [
   name:      "Private",
   source_url: @source_url,
    docs: [
      main:   "Private", # The main page in the docs
      extras: ["README.md"]
    ]
  ]
                                 
  ############################################################
  
  def project do
    in_production = Mix.env == :prod
    [
      app:     @name,
      version: @version,
      elixir:  ">= 1.4.0",
      deps:     @deps,
      package:  package(),
      description:     "Make private functions public if Mix.env is :test",
      build_embedded:  in_production,
      start_permanent: in_production
    ] ++  @doc_info
  end

  def application do
    [
    ]
  end

  defp package do
    [
      name:        @name,
      files:       ["lib", "mix.exs", "README.md", "LICENSE.md"],
      maintainers: ["Dave Thomas <dave@pragdave.me>"],
      licenses:    ["Apache 2.0"],
      links:       %{"GitHub" => @source_url},
    ]
  end  
end
