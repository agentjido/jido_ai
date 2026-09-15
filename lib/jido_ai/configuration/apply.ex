defmodule Jido.AI.Configuration.Apply do
  @moduledoc "Returns a configuration directive with the unchanged domain state."
  use Jido.Action, name: "ai_configure"
  alias Jido.AI.Configuration

  def run(params, context) do
    with {:ok, context} <- Jido.AI.Session.Plugin.context(context),
         do: apply_change(params, context)
  end

  defp apply_change(params, context) do
    agent = context.jido_ai_agent

    value =
      Map.get(params, :value) || params[:tool_module] || params[:tool_name] ||
        params[:system_prompt] || params[:tool_context]

    with {:ok, opts} <- Configuration.options(agent),
         {:ok, id} <- Configuration.select_id(opts, params[:profile_id]),
         {:ok, change} <-
           Configuration.validate(
             %Configuration.Change{profile_id: id, operation: params[:operation], value: value},
             opts
           ) do
      defaults =
        if context.jido_ai_profiles[id].skills != nil and
             change.operation in [:register, :unregister],
           do: [
             %Configuration.Change{
               profile_id: id,
               operation: :tools,
               value: context.jido_ai_profiles[id].tools
             }
           ],
           else: []

      {:ok, context.agent_state, defaults ++ [change]}
    end
  end
end
