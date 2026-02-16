defmodule Jido.AI.ReActAgent do
  @moduledoc """
  Deprecated compatibility alias for `Jido.AI.Agent`.

  New code should `use Jido.AI.Agent` directly.
  """

  @doc false
  @deprecated "Use `Jido.AI.Agent` instead."
  defmacro __using__(opts) do
    quote location: :keep do
      use Jido.AI.Agent, unquote(opts)
    end
  end

  @doc false
  @deprecated "Use `Jido.AI.Agent.expand_aliases_in_ast/2` instead."
  defdelegate expand_aliases_in_ast(ast, caller_env), to: Jido.AI.Agent

  @doc false
  @deprecated "Use `Jido.AI.Agent.tools_from_skills/1` instead."
  defdelegate tools_from_skills(skill_modules), to: Jido.AI.Agent
end
