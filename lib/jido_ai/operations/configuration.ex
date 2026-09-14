defmodule Jido.AI.Configuration.Change do
  @moduledoc "A validated tool, prompt or base context change for one declared AI profile."
  use Jido.Agent.Directive
  defstruct [:profile_id, :operation, :value]

  @impl Jido.Agent.Directive
  def validate(%__MODULE__{profile_id: id, operation: operation, value: value} = change) do
    valid =
      is_atom(id) and not is_nil(id) and
        case operation do
          :register -> is_atom(value) and not is_nil(value)
          :tools -> is_list(value)
          :tool_context -> is_map(value) and not is_struct(value)
          op when op in [:unregister, :prompt] -> is_binary(value)
          _ -> false
        end

    if valid do
      case Jido.Action.validate_static_data(change) do
        :ok -> {:ok, change}
        error -> error
      end
    else
      Jido.AI.Profile.error("configuration", "Invalid configuration change")
    end
  end

  def validate(_), do: Jido.AI.Profile.error("configuration", "Expected a configuration directive")
end

defmodule Jido.AI.Configuration do
  @moduledoc "Portable profile overrides. Active requests keep their admission snapshot."
  alias Jido.AI.{Profile, ToolCatalog}
  alias Jido.AI.Configuration.Change
  @key :jido_ai_config
  @type_name "jido.ai.configure"

  def key, do: @key
  def type, do: @type_name

  def routes do
    [{@type_name, Jido.AI.Configuration.Apply}]
  end

  def options(agent) do
    case Enum.find(agent.plugins, &(elem(&1, 0) == Jido.AI.Runtime.Plugin)) do
      {_, opts} -> {:ok, opts}
      _ -> Profile.error("profile", "Agent has no AI profiles")
    end
  end

  def profile(agent, id \\ nil) do
    with {:ok, opts} <- options(agent),
         {:ok, id} <- select_id(opts, id),
         {:ok, profiles} <- profiles(opts[:profiles], Map.get(agent.state || %{}, @key, %{})) do
      {:ok, profiles[id]}
    end
  end

  def select_id(opts, nil) do
    profiles = Keyword.fetch!(opts, :profiles)

    cond do
      Map.has_key?(profiles, :assistant) -> {:ok, :assistant}
      map_size(profiles) == 1 -> {:ok, hd(Map.keys(profiles))}
      true -> Profile.error("profile", "Select a profile for this Agent")
    end
  end

  def select_id(opts, id) do
    if Map.has_key?(opts[:profiles], id),
      do: {:ok, id},
      else: Profile.error("profile", "Unknown AI profile")
  end

  def profiles(declared, overrides) when is_map(overrides) do
    Enum.reduce_while(overrides, {:ok, declared}, fn {id, changes}, {:ok, acc} ->
      with %Profile{} = profile <- declared[id],
           {:ok, changes} <- Profile.fields(changes, [:tools, :instructions, :tool_context], "configuration"),
           {:ok, profile} <- Profile.new(Map.merge(profile, changes)) do
        {:cont, {:ok, Map.put(acc, id, profile)}}
      else
        {:error, _} = error -> {:halt, error}
        _ -> {:halt, Profile.error("configuration", "Unknown AI profile")}
      end
    end)
  end

  def profiles(_, _), do: Profile.error("configuration", "Expected profile overrides")

  def validate(%Change{profile_id: id, operation: operation, value: value} = change, opts) do
    with {:ok, change} <- Change.validate(change),
         {:ok, _} <- select_id(opts, id),
         :ok <- tool_list(operation, value),
         :ok <- context_value(operation, value) do
      {:ok, change}
    end
  end

  def validate(_, _), do: Profile.error("configuration", "Expected a configuration directive")

  defp tool_list(:tools, tools) do
    with {:ok, _} <- ToolCatalog.new(tools), do: :ok
  end

  defp tool_list(_, _), do: :ok

  defp context_value(:tool_context, value), do: Jido.AI.ToolContext.validate(value)
  defp context_value(_, _), do: :ok

  def validate_state(value, declared, _) do
    with {:ok, _} <- profiles(declared, value),
         :ok <- Jido.Action.validate_static_data(value) do
      :ok
    else
      _ -> {:error, "Invalid portable AI configuration"}
    end
  end

  def reduce(overrides, changes, opts) do
    Enum.reduce_while(changes, {:ok, overrides}, fn change, {:ok, current} ->
      with {:ok, change} <- validate(change, opts),
           {:ok, effective} <- profiles(opts[:profiles], current),
           {:ok, update} <- change(effective[change.profile_id], change, opts),
           next = Map.update(current, change.profile_id, update, &Map.merge(&1, update)),
           {:ok, _} <- profiles(opts[:profiles], next),
           :ok <- Jido.Action.validate_static_data(next) do
        {:cont, {:ok, next}}
      else
        error -> {:halt, error}
      end
    end)
  end

  defp change(profile, %Change{operation: :register, value: module}, opts) do
    with :ok <- validate_tool(module),
         {:ok, [entry]} <-
           ToolCatalog.from_input([module], Keyword.get(opts, :tool_defaults, %{})) do
      cond do
        Enum.any?(profile.tools, &(&1.target == module)) ->
          {:ok, %{tools: profile.tools}}

        Enum.any?(profile.tools, &(&1.name == entry.name)) ->
          Profile.error("tools", "Duplicate public tool name")

        true ->
          {:ok, %{tools: [entry | profile.tools]}}
      end
    end
  end

  defp change(profile, %Change{operation: :unregister, value: name}, _),
    do: {:ok, %{tools: Enum.reject(profile.tools, &(&1.name == name))}}

  defp change(_, %Change{operation: :prompt, value: text}, _), do: {:ok, %{instructions: text}}
  defp change(_, %Change{operation: :tools, value: tools}, _), do: {:ok, %{tools: tools}}
  defp change(_, %Change{operation: :tool_context, value: value}, _), do: {:ok, %{tool_context: value}}

  def validate_tool(module) do
    cond do
      not Code.ensure_loaded?(module) ->
        {:error, {:not_loaded, module}}

      not (function_exported?(module, :name, 0) and function_exported?(module, :schema, 0) and
               function_exported?(module, :run, 2)) ->
        {:error, :not_a_tool}

      true ->
        :ok
    end
  end

  def direct(agent, operation, value, opts \\ []) do
    with {:ok, config} <- options(agent),
         {:ok, id} <- select_id(config, opts[:profile]),
         {:ok, overrides} <-
           reduce(
             Map.get(agent.state, @key, %{}),
             [%Change{profile_id: id, operation: operation, value: value}],
             config
           ),
         do: Jido.Agent.transition(agent, Map.put(agent.state, @key, overrides))
  end

  def live(server, operation, value, opts \\ []) do
    signal =
      Jido.Signal.new!(
        @type_name,
        %{profile_id: opts[:profile], operation: operation, value: value},
        source: "/jido/ai"
      )

    Jido.AgentServer.call(server, signal, timeout: Keyword.get(opts, :timeout, 5_000))
  end
end

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
