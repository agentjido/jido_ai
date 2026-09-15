defmodule Jido.AI.Instructions do
  @moduledoc false

  alias Jido.Action.Output
  alias Jido.AI.Profile

  @doc false
  def resolve(%Profile{instructions: instructions} = profile, request, context, deadline)
      when is_map(request) and is_map(context) do
    case instructions do
      nil ->
        {:ok, profile}

      text when is_binary(text) ->
        {:ok, profile}

      action when is_atom(action) ->
        remaining = deadline - System.monotonic_time(:millisecond)

        if remaining > 0 do
          with {:ok, result} <- Jido.Exec.run(action, request, context, timeout: remaining),
               {:ok, text} <- text(result) do
            {:ok, %{profile | instructions: text}}
          end
        else
          Profile.error("instructions", "AI request deadline reached")
        end
    end
  end

  defp text(%{instructions: text}), do: valid_text(text)
  defp text(%{"instructions" => text}), do: valid_text(text)
  defp text(%Output{kind: :raw, value: text}), do: valid_text(text)

  defp text(_),
    do: Profile.error("instructions", "Action must return a non-empty instructions string")

  defp valid_text(text) when is_binary(text) do
    if String.trim(text) == "",
      do: Profile.error("instructions", "Action must return a non-empty instructions string"),
      else: {:ok, text}
  end

  defp valid_text(_),
    do: Profile.error("instructions", "Action must return a non-empty instructions string")
end
