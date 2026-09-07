defmodule Jido.AI.Directive.Execution do
  @moduledoc """
  Explicit compatibility entry point for the old AI Directive records.

  The caller supplies its task supervisor and result recipient. These records
  are not core v3 Directives and must not be returned from an Agent turn. New
  Agent work uses AI Actions, Flow and the Session runtime. This adapter keeps
  the old standalone result Signals available during caller migration.
  """

  @executions %{
    Jido.AI.Directive.LLMGenerate => Jido.AI.Directive.LLMGenerate.Execution,
    Jido.AI.Directive.LLMStream => Jido.AI.Directive.LLMStream.Execution,
    Jido.AI.Directive.LLMEmbed => Jido.AI.Directive.LLMEmbed.Execution,
    Jido.AI.Directive.ToolExec => Jido.AI.Directive.ToolExec.Execution,
    Jido.AI.Directive.EmitToolError => Jido.AI.Directive.EmitToolError.Execution,
    Jido.AI.Directive.EmitRequestError => Jido.AI.Directive.EmitRequestError.Execution
  }

  def exec(%{__struct__: module} = directive, input_signal, context) when is_map(context) do
    case Map.fetch(@executions, module) do
      {:ok, execution} ->
        case execution.exec(directive, input_signal, Map.put_new(context, :agent_server, self())) do
          {:ok, _} -> {:ok, context}
          {:async, handle, _} -> {:async, handle, context}
        end

      :error ->
        {:error, {:unsupported_ai_directive, module}}
    end
  end
end
