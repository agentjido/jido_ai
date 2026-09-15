defmodule Jido.AI.Runtime.ToolHook do
  @moduledoc false
  use Jido.Action, name: "ai_tool_hook"
  def run(params, context), do: Jido.AI.Error.capture(fn -> execute(params, context) end)

  defp execute(%{stage: :before, module: module, call: call}, context) do
    case Jido.AI.ToolInterceptor.before_tool_call(module, call, context) do
      {:ok, call} -> {:ok, %{call: call}}
      {:interrupt, value} -> {:error, {:interrupt, value}}
      error -> error
    end
  end

  defp execute(%{stage: :after, module: module, call: call, result: result}, context) do
    with {:ok, result, stats} <-
           Jido.AI.ToolInterceptor.after_tool_call_with_stats(module, call, result, context),
         do: {:ok, %{result: result, stats: stats}}
  end
end
