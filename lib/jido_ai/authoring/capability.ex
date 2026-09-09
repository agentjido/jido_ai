defmodule Jido.AI.Capability do
  @moduledoc false

  def bind(%Jido.Agent.Plugin.Preparation{} = preparation, key, binding) do
    {:ok, %{preparation | context: Map.put(preparation.context, key, binding)}}
  end

  def bind(command, key, binding) do
    with :ok <- result_field(command.agent.schema, binding) do
      {:ok, %{command | context: Map.put(command.context, key, binding)}}
    end
  end

  def run(action, params, context, %{key: key, defaults: defaults, into: into}) do
    scoped =
      context
      |> Map.put(:plugin_state, %{key => defaults})
      |> Map.put(:provided_params, Map.keys(params))

    with {:ok, result} <- Jido.Exec.run(action, params, scoped) do
      {:ok, Map.replace!(context.agent_state, into, result)}
    end
  end

  defp result_field(_, nil), do: :ok

  defp result_field(%Zoi.Types.Map{fields: fields}, %{into: into}) do
    if Keyword.has_key?(fields, into), do: :ok, else: invalid_field(into)
  end

  defp result_field(_, %{into: into}), do: invalid_field(into)

  defp invalid_field(into) do
    {:error,
     Jido.Error.validation_error("Capability result must select a declared domain field",
       kind: :config,
       details: %{into: into}
     )}
  end
end
