defmodule Jido.AI.Actions.InvokeCallback do
  @moduledoc false
  use Jido.Action, name: "ai_invoke_callback"

  def run(%{callback: callback, value: value}, _), do: {:ok, %{value: callback.(value)}}
end
