defmodule Jido.AI.Orchestration.RequestScope do
  @moduledoc false
  alias Jido.AI.Output
  alias Jido.AI.Profile
  alias Jido.AI.ToolCatalog
  alias Jido.AI.Reasoning.ReAct.ToolSelection

  def profile(profile, resources, context) do
    with {:ok, tools} <- tools(profile.tools, resources, context),
         {:ok, result} <- result(profile.result, resources[:output]) do
      controls = profile.controls |> limits(resources[:max_iterations]) |> activity_options(resources)

      reasoning =
        if resources[:request_transformer],
          do: Map.put(profile.reasoning, :request_transformer, resources.request_transformer),
          else: profile.reasoning

      Profile.new(%{
        profile
        | tools: tools,
          controls: controls,
          result: result,
          reasoning: reasoning
      })
    end
  end

  defp activity_options(controls, resources) do
    idle = Map.get(resources, :stream_timeout_ms)

    Enum.reduce([idle_timeout: idle, tool_heartbeat: resources[:tool_heartbeat_ms]], controls, fn
      {key, n}, acc when is_integer(n) and n >= 0 -> Map.put(acc, key, n)
      _, acc -> acc
    end)
  end

  defp tools(base, resources, context) do
    selected =
      if is_nil(resources[:tools]),
        do: {:ok, base},
        else: ToolCatalog.from_input(resources.tools, Map.get(context, :jido_ai_tool_defaults, %{}))

    with {:ok, selected} <- selected,
         index = Map.new(selected, &{&1.name, &1}),
         {:ok, filtered} <- ToolSelection.filter_allowed(index, resources[:allowed_tools]),
         do: {:ok, Enum.filter(selected, &Map.has_key?(filtered, &1.name))}
  end

  defp result(base, nil), do: {:ok, base}
  defp result(base, :raw), do: {:ok, %{base | schema: nil, max_repairs: 0}}

  defp result(base, value) do
    with {:ok, output} <- Output.new(value) do
      repairs = if output.on_validation_error == :repair, do: output.retries, else: 0

      {:ok,
       Map.merge(base, %{
         schema: output.schema,
         max_repairs: repairs,
         repair_fun: output.repair_fun,
         on_validation_error: output.on_validation_error
       })}
    end
  end

  defp limits(base, value) when is_integer(value) and value > 0,
    do: %{base | max_iterations: value}

  defp limits(base, _), do: base
end
