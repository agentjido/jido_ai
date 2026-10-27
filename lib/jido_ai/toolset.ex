defmodule Jido.AI.Toolset do
  @moduledoc """
  The Actions selected for one AI Agent.

  Discovery can resolve available Actions for authoring. A Toolset is narrower:
  it is the capability allowlist owned by one Agent definition.
  """

  use Jido.Plugin,
    id: "jido.ai/toolset",
    vsn: 1,
    option_keys: [agent: [:reasoning, :defaults, :tools]]

  @doc false
  @impl Jido.Agent.Extension
  def normalize(%{actions: actions}) do
    with :ok <- validate(actions), do: {:ok, %{actions: actions}}
  end

  def normalize(%{"actions" => actions}), do: normalize(%{actions: actions})
  def normalize(_data), do: {:error, :invalid_toolset}

  @doc false
  @impl Jido.Agent.Extension
  def verify(%{actions: actions}, _definition), do: validate(actions)

  @doc false
  @impl Jido.Plugin
  def prepare(_preparation, options) do
    actions = Keyword.get(options, :tools, [])
    with :ok <- validate(actions), do: {:ok, actions}
  end

  @doc "Returns the Actions from the protected Agent plugin input."
  @spec from_context(map()) :: [module()]
  def from_context(context) when is_map(context) do
    case get_in(context, [:plugin_inputs, __MODULE__]) do
      %Jido.Plugin.Input{prepared: actions} when is_list(actions) -> actions
      _other -> []
    end
  end

  @doc "Validates an ordered Agent Toolset."
  @spec validate(term()) :: :ok | {:error, term()}
  def validate(actions) when is_list(actions) do
    with :ok <- validate_actions(actions),
         :ok <- unique(actions, & &1) do
      unique(actions, & &1.name())
    end
  end

  def validate(_actions), do: {:error, :invalid_toolset}

  @doc "Returns the model tool names in declaration order."
  @spec names([module()]) :: [String.t()]
  def names(actions) when is_list(actions), do: Enum.map(actions, & &1.name())

  @doc "Selects a request tool subset below the protected Agent allowlist."
  @spec select([module()], map()) :: {:ok, map()} | {:error, term()}
  def select(actions, policy \\ %{})

  def select(actions, policy) when is_list(actions) and is_map(policy) do
    visible = field(policy, :visible) || []
    hidden = field(policy, :hidden) || []
    review = field(policy, :review) || []
    requirement = field(policy, :requirement) || :optional
    reason = field(policy, :reason)
    allowed = names(actions)

    with :ok <- validate_name_list(:visible, visible),
         :ok <- validate_name_list(:hidden, hidden),
         :ok <- validate_name_list(:review, review),
         :ok <- known_names(visible ++ hidden ++ review, allowed),
         :ok <- validate_requirement(requirement) do
      selected = select_actions(actions, visible, hidden, requirement)
      selected_names = names(selected)

      cond do
        requirement in [:required, :per_turn] and selected == [] ->
          {:error, {:tool_requirement_without_visible_tools, requirement}}

        Enum.any?(review, &(&1 not in selected_names)) ->
          {:error, {:review_tool_not_visible, Enum.find(review, &(&1 not in selected_names))}}

        true ->
          {:ok,
           %{
             actions: selected,
             visible: selected_names,
             hidden: allowed -- selected_names,
             review: review,
             requirement: requirement,
             reason: reason
           }}
      end
    end
  end

  def select(_actions, _policy), do: {:error, :invalid_tool_policy}

  @doc "Lowers semantic tool-use policy to one provider tool-choice value."
  @spec provider_tool_choice(atom(), non_neg_integer(), [module()]) :: atom() | nil
  def provider_tool_choice(:disabled, _tool_rounds, _actions), do: :none
  def provider_tool_choice(_requirement, _tool_rounds, []), do: nil
  def provider_tool_choice(:optional, _tool_rounds, _actions), do: nil
  def provider_tool_choice(:required, 0, _actions), do: :required
  def provider_tool_choice(:required, _tool_rounds, _actions), do: :auto
  def provider_tool_choice(:per_turn, _tool_rounds, _actions), do: :required

  @doc "Checks whether one final answer satisfies semantic tool-use policy."
  @spec requirement_satisfied?(atom(), non_neg_integer(), [module()]) :: boolean()
  def requirement_satisfied?(:required, 0, [_ | _]), do: false
  def requirement_satisfied?(:per_turn, _tool_rounds, [_ | _]), do: false
  def requirement_satisfied?(_requirement, _tool_rounds, _actions), do: true

  @doc "Builds ReqLLM definitions for an Agent Toolset."
  @spec definitions([module()]) :: {:ok, [ReqLLM.Tool.t()]} | {:error, term()}
  def definitions(actions) when is_list(actions) do
    case validate(actions) do
      :ok -> build_definitions(actions)
      error -> error
    end
  end

  @doc "Validates one portable model tool call against an Agent Toolset."
  @spec validate_call([module()], map()) :: :ok | {:error, term()}
  def validate_call(actions, call) do
    with {:ok, _resolved} <- resolve_call(actions, call), do: :ok
  end

  @doc "Resolves one portable model tool call against an Agent Toolset."
  @spec resolve_call([module()], map()) ::
          {:ok, %{id: String.t(), name: String.t(), action: module(), params: map()}}
          | {:error, term()}
  def resolve_call(actions, %{id: id, name: name, arguments: arguments})
      when is_list(actions) and is_binary(id) and id != "" and is_binary(name) and
             is_map(arguments) do
    with {:ok, action} <- fetch(actions, name),
         {:ok, params} <- decode_arguments(action, arguments) do
      {:ok, %{id: id, name: name, action: action, params: params}}
    end
  end

  def resolve_call(_actions, %{name: name}) when is_binary(name),
    do: {:error, {:unknown_tool, name}}

  def resolve_call(_actions, _call), do: {:error, :invalid_tool_call}

  @doc false
  @spec execution_boundary(map()) :: {:error, atom()}
  def execution_boundary(_arguments), do: {:error, :tool_must_run_in_agent_graph}

  defp validate_actions(actions) do
    case Enum.find(actions, &(not action?(&1))) do
      nil -> :ok
      action -> {:error, {:invalid_tool_action, action}}
    end
  end

  defp action?(action) when is_atom(action) and action not in [nil, true, false] do
    match?({:ok, %{kind: :action, target: ^action}}, Jido.Instruction.resolve(action))
  end

  defp action?(_action), do: false

  defp unique(actions, key) do
    values = Enum.map(actions, key)
    if values == Enum.uniq(values), do: :ok, else: {:error, :duplicate_tools}
  end

  defp definition(action) do
    ReqLLM.Tool.new(
      name: action.name(),
      description: action.description() || "",
      parameter_schema: action.schema(),
      callback: {__MODULE__, :execution_boundary},
      strict: true
    )
  end

  defp build_definitions(actions) do
    Enum.reduce_while(actions, {:ok, []}, fn action, {:ok, definitions} ->
      case definition(action) do
        {:ok, definition} -> {:cont, {:ok, [definition | definitions]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, definitions} -> {:ok, Enum.reverse(definitions)}
      error -> error
    end
  end

  defp fetch(actions, name) do
    case Enum.find(actions, &(&1.name() == name)) do
      nil -> {:error, {:unknown_tool, name}}
      action -> {:ok, action}
    end
  end

  defp decode_arguments(action, arguments) do
    case Zoi.parse(action.schema(), arguments, coerce: true) do
      {:ok, params} -> action.validate_params(params)
      {:error, _reason} -> {:error, {:invalid_tool_arguments, action.name()}}
    end
  end

  defp select_actions(_actions, _visible, _hidden, :disabled), do: []

  defp select_actions(actions, visible, hidden, _requirement) do
    actions
    |> Enum.filter(fn action -> visible == [] or action.name() in visible end)
    |> Enum.reject(&(&1.name() in hidden))
  end

  defp validate_name_list(_field, values) when is_list(values) do
    if List.improper?(values) do
      {:error, :invalid_tool_policy}
    else
      cond do
        Enum.any?(values, &(not is_binary(&1) or &1 == "")) -> {:error, :invalid_tool_policy}
        values != Enum.uniq(values) -> {:error, :duplicate_tool_policy_names}
        true -> :ok
      end
    end
  end

  defp validate_name_list(_field, _values), do: {:error, :invalid_tool_policy}

  defp known_names(requested, allowed) do
    case Enum.find(requested, &(&1 not in allowed)) do
      nil -> :ok
      name -> {:error, {:unknown_tool, name}}
    end
  end

  defp validate_requirement(requirement)
       when requirement in [:optional, :required, :per_turn, :disabled],
       do: :ok

  defp validate_requirement(requirement), do: {:error, {:invalid_tool_requirement, requirement}}

  defp field(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
