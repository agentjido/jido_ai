defmodule Jido.AI.Runtime.Plugin do
  @moduledoc "Binds host AI profiles and owns portable tool and prompt overrides."

  use Jido.Plugin,
    agent: Jido.AI.Runtime.Plugin.Agent,
    agent_server: Jido.AI.Runtime.Plugin.AgentServer

  @doc false
  def agent_state_spec(opts) do
    {Jido.AI.Configuration.key(),
     Zoi.map()
     |> Zoi.refine({Jido.AI.Configuration, :validate_state, [opts[:profiles]]})
     |> Zoi.default(%{})}
  end

  @doc false
  def prepare_command(command, opts) do
    binding = Jido.AI.Runtime.Binding.request(command.agent, command.signal)
    resources = Map.get(command.context, :jido_ai_request, %{})
    catalogs = Map.get(command.context, :jido_ai_skill_catalogs, %{})

    with {:ok, declared} <-
           Jido.AI.Skill.Source.profiles(
             Keyword.fetch!(opts, :profiles),
             catalogs,
             Keyword.get(opts, :tool_defaults, %{})
           ),
         {:ok, effective} <-
           Jido.AI.Configuration.profiles(
             declared,
             Map.get(command.agent.state, Jido.AI.Configuration.key(), %{})
           ),
         {:ok, profiles} <- request_models(effective, binding, resources) do
      context =
        command.context
        |> Jido.AI.ToolContext.bind(binding, profiles)
        |> Jido.AI.Skill.Source.context(binding, catalogs)
        |> Map.put(:jido_ai_agent, command.agent)
        |> Map.put(
          :jido_ai_checkpoint,
          if(opts[:standalone_checkpoints?], do: command.context[:jido_ai_checkpoint])
        )
        |> Map.put(:jido_ai_agent_id, command.agent.id)
        |> Map.delete(:jido_ai_session)
        |> Map.put(:jido_ai_profiles, profiles)
        |> Map.put(:jido_ai_legacy_agent_profile, opts[:legacy_agent_profile])
        |> Map.put(
          :jido_ai_legacy_iteration_result,
          opts[:legacy_iteration_result?] || opts[:legacy_agent_profile]
        )
        |> Map.put(:jido_ai_tool_defaults, Keyword.get(opts, :tool_defaults, %{}))

      profile_id = if match?(%{mode: :turn}, binding), do: binding.id
      {:ok, %{command | context: Map.put(context, :jido_ai_turn_profile, profile_id)}}
    end
  end

  defp request_models(profiles, nil, _resources), do: {:ok, profiles}

  defp request_models(profiles, %{id: id, input: input}, resources) do
    model =
      case resources[:model] do
        value when value in [nil, ""] -> Map.get(input, :model, Map.get(input, "model"))
        value -> value
      end

    if model in [nil, ""] do
      {:ok, profiles}
    else
      with %Jido.AI.Profile{} = profile <- Map.get(profiles, id) do
        model = Jido.AI.Models.resolve(model)
        models = Map.update!(profile.models, profile.reasoning.model, &Map.put(&1, :model, model))
        {:ok, Map.put(profiles, id, %{profile | models: models})}
      else
        _other -> Jido.AI.Profile.error("profile", "No trusted profile binding")
      end
    end
  rescue
    error in ArgumentError -> Jido.AI.Profile.error("model", Exception.message(error))
  end
end
