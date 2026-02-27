defmodule Jido.AI.Effects.Policy do
  @moduledoc """
  Effect policy definition and filtering for tool-emitted effects.
  """

  alias Jido.Agent.Directive
  alias Jido.Agent.StateOp

  @type mode :: :deny_all | :allow_all | :allow_list
  @type matcher :: module()
  @type matcher_set :: term()
  @type constraints :: map()

  @type t :: %__MODULE__{
          mode: mode(),
          allow: matcher_set(),
          deny: matcher_set(),
          constraints: constraints()
        }

  @default_allowed [
    StateOp.SetState,
    StateOp.ReplaceState,
    StateOp.DeleteKeys,
    StateOp.SetPath,
    StateOp.DeletePath,
    Directive.Emit,
    Directive.Schedule
  ]

  @default_denied [
    Directive.Spawn,
    Directive.SpawnAgent,
    Directive.Stop,
    Directive.StopChild,
    Directive.RunInstruction,
    Directive.Cron,
    Directive.CronCancel
  ]

  defstruct mode: :allow_list,
            allow: MapSet.new(@default_allowed),
            deny: MapSet.new(@default_denied),
            constraints: %{}

  @doc "Returns the default policy."
  @spec default() :: t()
  def default, do: %__MODULE__{}

  @doc """
  Builds a policy from map/keyword input.
  """
  @spec new(t() | map() | keyword() | nil) :: t()
  def new(%__MODULE__{} = policy), do: policy
  def new(nil), do: default()

  def new(input) when is_list(input) do
    input
    |> Map.new()
    |> new()
  end

  def new(input) when is_map(input) do
    mode = normalize_mode(fetch(input, :mode, :allow_list))

    allow =
      input
      |> fetch(:allow, @default_allowed)
      |> normalize_matchers()

    deny =
      input
      |> fetch(:deny, @default_denied)
      |> normalize_matchers()

    constraints = input |> fetch(:constraints, %{}) |> normalize_constraints()

    %__MODULE__{mode: mode, allow: allow, deny: deny, constraints: constraints}
  end

  def new(_), do: default()

  @doc """
  Narrows an agent policy by a strategy policy.
  """
  @spec intersect(t() | map() | keyword() | nil, t() | map() | keyword() | nil) :: t()
  def intersect(agent_policy, strategy_policy) do
    agent = new(agent_policy)
    strategy = new(strategy_policy)

    mode = intersect_mode(agent.mode, strategy.mode)
    deny = MapSet.union(agent.deny, strategy.deny)
    allow = intersect_allow(agent, strategy)
    constraints = merge_constraints(agent.constraints, strategy.constraints)

    %__MODULE__{mode: mode, allow: allow, deny: deny, constraints: constraints}
  end

  @doc """
  Filters effects according to the policy.

  Returns `{allowed, dropped}`.
  """
  @spec filter(t() | map() | keyword() | nil, [term()]) :: {[term()], [term()]}
  def filter(policy, effects) when is_list(effects) do
    policy = new(policy)

    Enum.reduce(effects, {[], []}, fn effect, {allowed, dropped} ->
      if allowed?(policy, effect) do
        {[effect | allowed], dropped}
      else
        {allowed, [effect | dropped]}
      end
    end)
    |> then(fn {allowed, dropped} -> {Enum.reverse(allowed), Enum.reverse(dropped)} end)
  end

  def filter(policy, effect), do: filter(policy, List.wrap(effect))

  @doc "Returns true when an effect is permitted by the policy."
  @spec allowed?(t(), term()) :: boolean()
  def allowed?(%__MODULE__{} = policy, %struct{} = effect) when is_atom(struct) do
    if MapSet.member?(policy.deny, struct) do
      false
    else
      base_allowed? =
        case policy.mode do
          :deny_all -> false
          :allow_all -> true
          :allow_list -> MapSet.member?(policy.allow, struct)
        end

      base_allowed? and constrained_allowed?(policy.constraints, effect)
    end
  end

  def allowed?(_policy, _effect), do: false

  defp fetch(map, key, default) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  defp normalize_mode(:deny_all), do: :deny_all
  defp normalize_mode(:allow_all), do: :allow_all
  defp normalize_mode(:allow_list), do: :allow_list
  defp normalize_mode("deny_all"), do: :deny_all
  defp normalize_mode("allow_all"), do: :allow_all
  defp normalize_mode("allow_list"), do: :allow_list
  defp normalize_mode(_), do: :allow_list

  defp normalize_matchers(values) when is_list(values) do
    values
    |> Enum.map(&normalize_matcher/1)
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  defp normalize_matchers(%MapSet{} = set), do: set
  defp normalize_matchers(value), do: normalize_matchers(List.wrap(value))

  defp normalize_matcher(module) when is_atom(module), do: module

  defp normalize_matcher(module) when is_binary(module) do
    try do
      String.to_existing_atom(module)
    rescue
      ArgumentError -> nil
    end
  end

  defp normalize_matcher(_), do: nil

  defp normalize_constraints(constraints) when is_list(constraints) do
    constraints
    |> Enum.into(%{})
    |> normalize_constraints()
  end

  defp normalize_constraints(%{} = constraints) do
    %{}
    |> maybe_put_constraint(:emit, normalize_emit_constraints(fetch(constraints, :emit, nil)))
    |> maybe_put_constraint(:schedule, normalize_schedule_constraints(fetch(constraints, :schedule, nil)))
  end

  defp normalize_constraints(_), do: %{}

  defp normalize_emit_constraints(nil), do: nil

  defp normalize_emit_constraints(constraints) when is_list(constraints) do
    constraints
    |> Enum.into(%{})
    |> normalize_emit_constraints()
  end

  defp normalize_emit_constraints(%{} = constraints) do
    %{}
    |> maybe_put_constraint(:allowed_signal_prefixes, normalize_list(fetch(constraints, :allowed_signal_prefixes, nil)))
    |> maybe_put_constraint(:allowed_signal_types, normalize_list(fetch(constraints, :allowed_signal_types, nil)))
    |> maybe_put_constraint(:allowed_dispatches, normalize_list(fetch(constraints, :allowed_dispatches, nil)))
  end

  defp normalize_emit_constraints(_), do: nil

  defp normalize_schedule_constraints(nil), do: nil

  defp normalize_schedule_constraints(constraints) when is_list(constraints) do
    constraints
    |> Enum.into(%{})
    |> normalize_schedule_constraints()
  end

  defp normalize_schedule_constraints(%{} = constraints) do
    case fetch(constraints, :max_delay_ms, nil) do
      max_delay_ms when is_integer(max_delay_ms) and max_delay_ms >= 0 ->
        %{max_delay_ms: max_delay_ms}

      _ ->
        %{}
    end
  end

  defp normalize_schedule_constraints(_), do: nil

  defp intersect_mode(:deny_all, _), do: :deny_all
  defp intersect_mode(_, :deny_all), do: :deny_all
  defp intersect_mode(:allow_all, :allow_all), do: :allow_all
  defp intersect_mode(:allow_all, :allow_list), do: :allow_list
  defp intersect_mode(:allow_list, :allow_all), do: :allow_list
  defp intersect_mode(:allow_list, :allow_list), do: :allow_list

  defp intersect_allow(%__MODULE__{mode: :deny_all}, _), do: MapSet.new()
  defp intersect_allow(_, %__MODULE__{mode: :deny_all}), do: MapSet.new()

  defp intersect_allow(%__MODULE__{mode: :allow_all}, %__MODULE__{mode: :allow_all}),
    do: MapSet.new()

  defp intersect_allow(%__MODULE__{mode: :allow_all}, %__MODULE__{allow: allow}),
    do: allow

  defp intersect_allow(%__MODULE__{allow: allow}, %__MODULE__{mode: :allow_all}),
    do: allow

  defp intersect_allow(%__MODULE__{allow: left}, %__MODULE__{allow: right}),
    do: MapSet.intersection(left, right)

  defp merge_constraints(%{} = agent, %{} = strategy) do
    emit = merge_emit_constraints(fetch(agent, :emit, nil), fetch(strategy, :emit, nil))
    schedule = merge_schedule_constraints(fetch(agent, :schedule, nil), fetch(strategy, :schedule, nil))

    agent
    |> Map.merge(strategy)
    |> maybe_put_constraint(:emit, emit)
    |> maybe_put_constraint(:schedule, schedule)
  end

  defp maybe_put_constraint(map, _key, nil), do: map
  defp maybe_put_constraint(map, key, value), do: Map.put(map, key, value)

  defp merge_emit_constraints(nil, nil), do: nil
  defp merge_emit_constraints(nil, right) when is_map(right), do: right
  defp merge_emit_constraints(left, nil) when is_map(left), do: left

  defp merge_emit_constraints(left, right) when is_map(left) and is_map(right) do
    %{}
    |> put_intersection(:allowed_signal_prefixes, left, right)
    |> put_intersection(:allowed_signal_types, left, right)
    |> put_intersection(:allowed_dispatches, left, right)
  end

  defp put_intersection(acc, key, left, right) do
    l = normalize_list(fetch(left, key, nil))
    r = normalize_list(fetch(right, key, nil))

    value =
      cond do
        l == nil and r == nil -> nil
        l == nil -> r
        r == nil -> l
        true -> Enum.filter(l, &(&1 in r))
      end

    if value == nil, do: acc, else: Map.put(acc, key, value)
  end

  defp merge_schedule_constraints(nil, nil), do: nil
  defp merge_schedule_constraints(nil, right) when is_map(right), do: right
  defp merge_schedule_constraints(left, nil) when is_map(left), do: left

  defp merge_schedule_constraints(left, right) when is_map(left) and is_map(right) do
    left_max = fetch(left, :max_delay_ms, nil)
    right_max = fetch(right, :max_delay_ms, nil)

    max_delay_ms =
      cond do
        is_integer(left_max) and is_integer(right_max) -> min(left_max, right_max)
        is_integer(left_max) -> left_max
        is_integer(right_max) -> right_max
        true -> nil
      end

    if is_integer(max_delay_ms), do: %{max_delay_ms: max_delay_ms}, else: %{}
  end

  defp normalize_list(nil), do: nil
  defp normalize_list(value) when is_list(value), do: value
  defp normalize_list(value), do: List.wrap(value)

  defp constrained_allowed?(constraints, %Directive.Emit{} = emit) when is_map(constraints) do
    emit_constraints = fetch(constraints, :emit, %{})
    emit_type_allowed?(emit, emit_constraints) and emit_dispatch_allowed?(emit, emit_constraints)
  end

  defp constrained_allowed?(constraints, %Directive.Schedule{} = schedule) when is_map(constraints) do
    schedule_constraints = fetch(constraints, :schedule, %{})
    schedule_delay_allowed?(schedule, schedule_constraints)
  end

  defp constrained_allowed?(_constraints, _effect), do: true

  defp emit_type_allowed?(%Directive.Emit{signal: signal}, constraints) do
    allowed_types = normalize_list(fetch(constraints, :allowed_signal_types, nil))
    allowed_prefixes = normalize_list(fetch(constraints, :allowed_signal_prefixes, nil))
    signal_type = extract_signal_type(signal)

    type_allowed? =
      case allowed_types do
        nil -> true
        [] -> false
        allowed -> is_binary(signal_type) and signal_type in allowed
      end

    prefix_allowed? =
      case allowed_prefixes do
        nil -> true
        [] -> false
        prefixes -> is_binary(signal_type) and Enum.any?(prefixes, &String.starts_with?(signal_type, &1))
      end

    type_allowed? and prefix_allowed?
  end

  defp emit_dispatch_allowed?(%Directive.Emit{dispatch: dispatch}, constraints) do
    allowed_dispatches = normalize_dispatches(fetch(constraints, :allowed_dispatches, nil))

    case allowed_dispatches do
      nil ->
        true

      [] ->
        false

      allowed ->
        dispatch
        |> dispatch_adapters()
        |> Enum.map(&normalize_dispatch/1)
        |> Enum.all?(fn adapter -> not is_nil(adapter) and adapter in allowed end)
    end
  end

  defp normalize_dispatches(nil), do: nil

  defp normalize_dispatches(dispatches) when is_list(dispatches) do
    dispatches
    |> Enum.map(&normalize_dispatch/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp normalize_dispatches(dispatch), do: normalize_dispatches([dispatch])

  defp normalize_dispatch(dispatch) when is_atom(dispatch), do: Atom.to_string(dispatch)

  defp normalize_dispatch(dispatch) when is_binary(dispatch) do
    dispatch
    |> String.trim()
    |> case do
      "" -> nil
      value -> value
    end
  end

  defp normalize_dispatch(_), do: nil

  defp dispatch_adapters(nil), do: [:default]
  defp dispatch_adapters({adapter, _opts}) when is_atom(adapter), do: [adapter]
  defp dispatch_adapters(adapter) when is_atom(adapter), do: [adapter]
  defp dispatch_adapters(list) when is_list(list), do: Enum.flat_map(list, &dispatch_adapters/1)
  defp dispatch_adapters(_), do: [:unknown]

  defp schedule_delay_allowed?(%Directive.Schedule{delay_ms: delay_ms}, constraints) do
    case fetch(constraints, :max_delay_ms, nil) do
      max when is_integer(max) and max >= 0 ->
        is_integer(delay_ms) and delay_ms >= 0 and delay_ms <= max

      _ ->
        true
    end
  end

  defp extract_signal_type(%{type: type}) when is_binary(type), do: type
  defp extract_signal_type(%{"type" => type}) when is_binary(type), do: type
  defp extract_signal_type(_), do: nil
end
