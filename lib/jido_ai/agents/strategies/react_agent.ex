defmodule Jido.AI.ReActAgent do
  @moduledoc """
  Compatibility wrapper for defining ReAct agents.

  This module delegates to `Jido.AI.Agent`.

  Delegated ReAct runtime orchestration is default-on in `Jido.AI.Agent`, so this
  wrapper preserves the public API without additional runtime toggles.
  """

  @doc false
  defmacro __using__(opts) do
    quote location: :keep do
      use Jido.AI.Agent, unquote(opts)
    end
  end

  @doc false
  defdelegate expand_aliases_in_ast(ast, caller_env), to: Jido.AI.Agent

  @doc false
  defdelegate tools_from_skills(skill_modules), to: Jido.AI.Agent
end
