defmodule Jido.AI.Runtime.CheckControl do
  @moduledoc false
  use Jido.Action, name: "ai_check_control"
  @impl Jido.Action
  def run(params, context), do: Jido.AI.Error.capture(fn -> execute(params, context) end)

  defp execute(%{module: module, stage: stage, value: value}, context) do
    case module.check(value, context) do
      :ok -> {:ok, %{}}
      {:error, _} = error -> error
      {:interrupt, value} when stage == :operation -> {:error, {:interrupt, value}}
      _ -> Jido.AI.Profile.error("controls", "Invalid control result")
    end
  end
end
