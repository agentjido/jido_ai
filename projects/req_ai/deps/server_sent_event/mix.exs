defmodule ServerSentEvent.Mixfile do
  use Mix.Project

  def project do
    [
      app: :server_sent_event,
      version: "1.0.0",
      elixir: "~> 1.7",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_options: [
        warnings_as_errors: true
      ],
      description: description(),
      docs: [extras: ["README.md"], main: "ServerSentEvent"],
      package: package(),
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  def application do
    [extra_applications: [:logger, :ssl]]
  end

  defp deps do
    [
      {:raxx, "~> 1.0"},
      {:dialyxir, ">= 0.5.0", only: [:dev, :test], runtime: false, optional: true},
      {:ex_doc, ">= 0.0.0", only: :dev},
      {:stream_data, "~> 0.4.2", only: :test},
      {:mix_test_watch, ">= 0.9.0", only: [:dev, :test], runtime: false, optional: true},
      {:benchee, ">= 0.13.2", only: [:dev, :test], optional: true}
    ]
  end

  defp description do
    """
    Push updates to web clients over HTTP, using dedicated server-push protocol.
    """
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README*"],
      maintainers: ["Peter Saxton"],
      licenses: ["Apache 2.0"],
      links: %{"GitHub" => "https://github.com/CrowdHailer/server_sent_event.ex"}
    ]
  end

  # Specifies which paths to compile per environment
  defp elixirc_paths(:test), do: ["lib", "test/support"]

  defp elixirc_paths(_), do: ["lib"]
end
