defmodule Jido.AI.ReActAgent do
  @moduledoc """
  Compatibility wrapper for defining ReAct agents.

  This module delegates to `Jido.AI.Agent`, defaulting `:runtime_adapter` to
  `true` so agents use the Task-based ReAct runtime by default.
  """

  @doc false
  defmacro __using__(opts) do
    opts = Keyword.put_new(opts, :runtime_adapter, true)

    quote location: :keep do
      use Jido.AI.Agent, unquote(opts)
    end
  end

  @doc false
  defdelegate expand_aliases_in_ast(ast, caller_env), to: Jido.AI.Agent

  @doc false
  defdelegate tools_from_skills(skill_modules), to: Jido.AI.Agent
end
