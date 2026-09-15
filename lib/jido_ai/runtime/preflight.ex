defmodule Jido.AI.Runtime.Preflight do
  @moduledoc false

  def check(profile, batch, context, deadline) do
    with :ok <- each(batch, &Jido.AI.Control.check(profile, :operation, &1, context, deadline)) do
      :ok
    else
      {:error, _} = error ->
        Jido.AI.Orchestration.failure_type(context, :tool_guardrail)
        error
    end
  end

  defp each(batch, check) do
    Enum.reduce_while(batch, :ok, fn call, :ok ->
      case check.(call) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end
end
