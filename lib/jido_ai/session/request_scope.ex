defmodule Jido.AI.Session.RequestScope do
  @moduledoc false
  alias Jido.AI.{Output, Profile, ToolCatalog}
  alias Jido.AI.Reasoning.ReAct.ToolSelection

  def profile(profile, resources, context) do
    with {:ok, tools} <- tools(profile.tools, resources, context),
         {:ok, result} <- result(profile.result, resources[:output]) do
      controls = limits(profile.controls, result, resources[:max_iterations], context)

      reasoning =
        if resources[:request_transformer],
          do: Map.put(profile.reasoning, :request_transformer, resources.request_transformer),
          else: profile.reasoning

      Profile.new(%{
        profile
        | tools: tools,
          controls: controls,
          result: result,
          reasoning: reasoning,
          requests: stream_options(profile.requests, resources)
      })
    end
  end

  def stream_options(requests, resources) do
    idle = Map.get(resources, :stream_timeout_ms, resources[:stream_receive_timeout_ms])

    Enum.reduce([idle_timeout: idle, tool_heartbeat: resources[:tool_heartbeat_ms]], requests, fn
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

  defp limits(base, result, value, context) when is_integer(value) and value > 0 do
    controls = %{base | max_iterations: value}

    if context[:jido_ai_legacy_agent_profile],
      do: %{controls | max_model_calls: value + result.max_repairs},
      else: controls
  end

  defp limits(base, result, _, context) do
    if context[:jido_ai_legacy_agent_profile],
      do: %{
        base
        | max_model_calls:
            if(base.max_iterations == :method_default,
              do: :method_default,
              else: base.max_iterations + result.max_repairs
            )
      },
      else: base
  end
end
