defmodule Jido.AI.Plugin.DSL.ReasoningMacros do
  @moduledoc false

  @reasoning_entity Jido.AI.Plugin.Ai.Reasoning

  defmacro reasoning(do: body) do
    caller = __CALLER__

    path = [
      host: Jido.AI.Plugin,
      declaration: :reasoning,
      role: :flow
    ]

    options = [
      name: inline_name(caller.module),
      description: "Run the Agent's inline AI reasoning Flow"
    ]

    compiled =
      Jido.Flow.Inline.compile!(
        Macro.escape(path),
        Macro.escape(options),
        body,
        caller
      )

    reasoning_call = reasoning_call(compiled.target_ast, caller.line)

    quote generated: true do
      unquote(compiled.declaration_ast)
      unquote(reasoning_call)
    end
  end

  defmacro reasoning(target) do
    reasoning_call(target, __CALLER__.line)
  end

  defp reasoning_call(target, line) do
    quote generated: true, line: line do
      require unquote(@reasoning_entity)
      unquote(@reasoning_entity).__reasoning__(unquote(target))
    end
  end

  defp inline_name(module) do
    module
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
    |> Kernel.<>("_reasoning")
  end
end
