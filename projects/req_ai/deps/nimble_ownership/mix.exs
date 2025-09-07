defmodule NimbleOwnership.MixProject do
  use Mix.Project

  @version "1.0.1"
  @repo "https://github.com/dashbitco/nimble_ownership"

  def project do
    [
      app: :nimble_ownership,
      version: @version,
      elixir: "~> 1.11",
      start_permanent: Mix.env() == :prod,
      deps: deps(),

      # Tests
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.json": :test
      ],

      # Hex package
      description: "Track ownership of resources across processes.",
      package: package(),

      # Docs
      name: "NimbleOwnership",
      source_url: @repo,
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: []
    ]
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      maintainers: ["José Valim", "Andrea Leopardi"],
      links: %{"GitHub" => @repo}
    ]
  end

  defp docs do
    [
      main: "NimbleOwnership",
      source_ref: "v#{@version}",
      authors: ["Andrea Leopardi"],
      before_closing_body_tag: fn
        :html ->
          """
          <script src="https://cdn.jsdelivr.net/npm/mermaid@10.2.3/dist/mermaid.min.js"></script>
          <script>
            document.addEventListener("DOMContentLoaded", function () {
              mermaid.initialize({
                startOnLoad: false,
                theme: document.body.className.includes("dark") ? "dark" : "default"
              });
              let id = 0;
              for (const codeEl of document.querySelectorAll("pre code.mermaid")) {
                const preEl = codeEl.parentElement;
                const graphDefinition = codeEl.textContent;
                const graphEl = document.createElement("div");
                const graphId = "mermaid-graph-" + id++;
                mermaid.render(graphId, graphDefinition).then(({svg, bindFunctions}) => {
                  graphEl.innerHTML = svg;
                  bindFunctions?.(graphEl);
                  preEl.insertAdjacentElement("afterend", graphEl);
                  preEl.remove();
                });
              }
            });
          </script>
          """

        :epub ->
          ""
      end
    ]
  end

  defp deps do
    [
      {:castore, "~> 1.0", only: :test},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.31", only: :dev},
      {:excoveralls, "~> 0.18", only: :test}
    ]
  end
end
