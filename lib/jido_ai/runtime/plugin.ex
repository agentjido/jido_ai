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
  def context(context) do
    case get_in(context, [:plugin_inputs, __MODULE__]) do
      %Jido.Plugin.Input{runtime: %{options: opts, agent_module: module}} ->
        agent =
          case live_agent(context) || module_definition(module) do
            %Jido.Agent{} = current ->
              %{current | id: context.agent_id, state: context.agent_state}

            nil ->
              fallback_agent(context, module, opts)
          end

        command = %Jido.Agent.Command{agent: agent, signal: context.signal, context: context}

        case prepare_command(command, opts) do
          {:ok, prepared} -> {:ok, quota_context(prepared.context)}
          {:error, _} = error -> error
        end

      %Jido.Plugin.Input{} ->
        Jido.AI.Profile.error("runtime", "Native AI routes require AgentServer admission; use Jido.AgentServer.call/3")

      _ ->
        {:ok, context}
    end
  end

  defp live_agent(%{jido: jido, agent_id: id} = context)
       when is_atom(jido) and not is_nil(jido) and is_binary(id) do
    case Jido.whereis_agent(jido, id, partition: context[:partition]) do
      pid when is_pid(pid) -> Jido.AgentServer.agent(pid)
      nil -> nil
    end
  catch
    :exit, _ -> nil
  end

  defp live_agent(_), do: nil

  defp quota_context(context) do
    case get_in(context, [:plugin_inputs, Jido.AI.Plugins.Quota]) do
      %Jido.Plugin.Input{runtime: %{binding: binding}} -> Map.put(context, :jido_ai_quota, binding)
      _ -> context
    end
  end

  @doc false
  def native_binding(admission) do
    context = Map.put(admission.caller_context, :agent_id, admission.agent_id)
    agent = live_agent(context) || module_definition(admission.agent_module)
    if agent, do: Jido.AI.Runtime.Binding.request(agent, admission.signal)
  end

  @doc false
  def native_request?(admission), do: not is_nil(native_binding(admission))

  defp module_definition(module) when is_atom(module) do
    if function_exported?(module, :definition, 0), do: module.definition()
  end

  defp fallback_agent(context, module, opts) do
    profiles = Keyword.fetch!(opts, :profiles)

    routes =
      case Map.to_list(profiles) do
        [{id, profile}] ->
          if String.ends_with?(context.signal.type, ".query") or
               context.signal.type == "reasoning.run" do
            target =
              if profile.requests.mode == :session,
                do: Jido.AI.Session.Start,
                else: Jido.AI.Runtime.Run

            [{context.signal.type, {target, %{profile_id: id}}}]
          else
            []
          end

        _ ->
          []
      end

    domain_state =
      Map.drop(context.agent_state, [
        Jido.AI.Configuration.key(),
        :requests,
        Jido.AI.Conversation.Control.key()
      ])

    schema = Zoi.object(Map.new(domain_state, fn {key, _} -> {key, Zoi.any()} end))

    plugins = [{__MODULE__, opts}]

    plugins =
      if Map.has_key?(context.agent_state, :requests),
        do: plugins ++ [{Jido.AI.Session.Plugin, []}],
        else: plugins

    histories =
      profiles
      |> Enum.filter(fn {_, profile} -> not is_nil(profile.memory.history) end)
      |> Map.new(fn {id, profile} -> {id, profile.memory.history} end)

    plugins =
      if Map.has_key?(context.agent_state, Jido.AI.Conversation.Control.key()),
        do: plugins ++ [{Jido.AI.Conversation.Control.Plugin, [profiles: histories]}],
        else: plugins

    struct(Jido.Agent, %{
      id: context.agent_id,
      module: module,
      name: "jido_ai",
      schema: schema,
      routes: routes,
      state: context.agent_state,
      plugins: plugins
    })
  end

  @doc false
  def prepare_command(command, opts) do
    binding = Jido.AI.Runtime.Binding.request(command.agent, command.signal)
    resources = Map.get(command.context, :jido_ai_request, %{})

    routed_model =
      Jido.AI.Capability.prepared(command.context, Jido.AI.Plugins.ModelRouting) ||
        Jido.AI.Plugins.ModelRouting.selected_for_agent(command.agent, command.signal)

    with :ok <- supported_tool_sources(binding, Keyword.fetch!(opts, :profiles)),
         {:ok, effective} <-
           Jido.AI.Configuration.profiles(
             Keyword.fetch!(opts, :profiles),
             Map.get(command.agent.state, Jido.AI.Configuration.key(), %{})
           ),
         {:ok, profiles} <- request_models(effective, binding, resources, routed_model) do
      context =
        command.context
        |> Jido.AI.ToolContext.bind(binding, profiles)
        |> Map.put(:jido_ai_agent, command.agent)
        |> Map.put(
          :jido_ai_checkpoint,
          if(opts[:standalone_checkpoints?], do: command.context[:jido_ai_checkpoint])
        )
        |> Map.put(:jido_ai_agent_id, command.agent.id)
        |> Map.delete(:jido_ai_session)
        |> Map.put(:jido_ai_profiles, profiles)
        |> Map.put(
          :jido_ai_iteration_limit_result,
          opts[:iteration_limit_result?] == true
        )
        |> Map.put(:jido_ai_tool_defaults, Keyword.get(opts, :tool_defaults, %{}))

      profile_id = if match?(%{mode: :turn}, binding), do: binding.id
      {:ok, %{command | context: Map.put(context, :jido_ai_turn_profile, profile_id)}}
    end
  end

  defp supported_tool_sources(nil, _profiles), do: :ok

  defp supported_tool_sources(%{id: id}, profiles) do
    case profiles[id] do
      %{tool_sources: [_ | _]} ->
        Jido.AI.Profile.error(
          "tool_sources",
          "Native AI routes do not resolve dynamic tool sources; supply resolved static tools"
        )

      _ ->
        :ok
    end
  end

  defp request_models(profiles, nil, _resources, _routed_model), do: {:ok, profiles}

  defp request_models(profiles, %{id: id, input: input}, resources, routed_model) do
    model =
      case resources[:model] do
        value when value in [nil, ""] ->
          selected = Map.get(input, :model, Map.get(input, "model"))
          if selected in [nil, ""], do: routed_model, else: selected

        value ->
          value
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
