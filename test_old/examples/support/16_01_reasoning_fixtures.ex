defmodule JidoAI.Examples.ReasoningCapabilities do
  @moduledoc "One domain Agent with explicit reasoning capability routes."

  def definition(plugins, opts \\ []) do
    Jido.Agent.new(%{
      name: "reasoning_capabilities",
      schema:
        Zoi.object(%{
          result: Zoi.any() |> Zoi.default(nil),
          review: Zoi.any() |> Zoi.default(nil),
          case_id: Zoi.string() |> Zoi.default("case-17")
        }),
      plugins: plugins,
      routes:
        Keyword.get_lazy(opts, :routes, fn ->
          Enum.flat_map(plugins, fn {module, config} -> module.signal_routes(config) end)
        end)
    })
  end
end
