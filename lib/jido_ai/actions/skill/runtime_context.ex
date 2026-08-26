defmodule Jido.AI.Actions.Skill.RuntimeContext do
  @moduledoc """
  Resolves the shared session key for skill actions.
  """

  @doc """
  Gets the first available session, agent, or request identifier.

  The caller process is the fallback when the context has no stable ID.
  """
  @spec session_id(map()) :: term()
  def session_id(context) when is_map(context) do
    context[:session_id] || context["session_id"] ||
      context[:agent_id] || context["agent_id"] ||
      context[:request_id] || context["request_id"] || self()
  end
end
