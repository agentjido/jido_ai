defmodule Jido.AI.Control do
  @moduledoc "A pure policy check at an AI input, model, operation, or output boundary."
  @callback check(value :: term(), context :: map()) ::
              :ok | {:error, term()} | {:interrupt, term()}

  @doc false
  def check(profile, stage, value, context, deadline) do
    Enum.reduce_while(profile.controls[stage], :ok, fn control, :ok ->
      {module, match} = control_spec(control)

      if matches?(value, match) do
        remaining = deadline - System.monotonic_time(:millisecond)

        result =
          if remaining > 0,
            do:
              Jido.Exec.run(
                Jido.AI.Runtime.CheckControl,
                %{module: module, stage: stage, value: value},
                context,
                timeout: remaining
              ),
            else: Jido.AI.Profile.error("controls.#{stage}", "AI request deadline reached")

        case result do
          {:ok, _} -> {:cont, :ok}
          {:error, _} = error -> {:halt, error}
          _ -> {:halt, Jido.AI.Profile.error("controls.#{stage}", "Invalid control result")}
        end
      else
        {:cont, :ok}
      end
    end)
  end

  defp control_spec(%{module: module, when: match}), do: {module, match}
  defp control_spec(module), do: {module, nil}

  defp matches?(_value, nil), do: true

  defp matches?(value, match) do
    metadata = stable_metadata(value)

    Enum.all?(match, fn {key, expected} ->
      actual =
        Enum.find_value(metadata, fn {actual_key, value} ->
          if comparable(actual_key) == comparable(key), do: value
        end)

      comparable(actual) == comparable(expected)
    end)
  end

  defp stable_metadata(%{tool: tool} = value) do
    kind =
      case Jido.Executable.resolve(tool.target) do
        {:ok, %{kind: kind}} -> kind
        _ -> nil
      end

    Map.merge(Map.get(tool, :metadata, %{}), %{kind: kind, name: value.name})
  end

  defp stable_metadata(value) when is_map(value), do: value
  defp stable_metadata(_value), do: %{}

  defp comparable(value) when is_atom(value), do: Atom.to_string(value)
  defp comparable(value), do: value
end
