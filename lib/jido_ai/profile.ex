defmodule Jido.AI.Profile do
  @moduledoc """
  Static AI policy that lowers into a core Agent and Flow.

  Construction does not call a model or tool. Model aliases resolve when a Turn
  starts. Runtime provider options belong in the caller context under
  `ai: %{profile_id => %{options: keyword()}}`; Signal data cannot set them.
  """
  alias Jido.AI.Output

  @schema Zoi.struct(
            __MODULE__,
            %{
              id: Zoi.atom(),
              instructions: Zoi.any() |> Zoi.nullable() |> Zoi.default(nil),
              models: Zoi.map(),
              reasoning: Zoi.map(),
              controls: Zoi.map(),
              tools: Zoi.list(Zoi.map()),
              tool_sources: Zoi.list(Zoi.map()) |> Zoi.default([]),
              tool_context: Zoi.map() |> Zoi.default(%{}),
              skills: Zoi.any() |> Zoi.default(nil),
              effect_policy: Zoi.map() |> Zoi.default(%{}),
              tool_interceptor: Zoi.atom() |> Zoi.nullable() |> Zoi.default(nil),
              observability: Zoi.map() |> Zoi.default(%{}),
              model_router: Zoi.any() |> Zoi.nullable() |> Zoi.default(nil),
              result: Zoi.map(),
              requests:
                Zoi.map()
                |> Zoi.default(%{
                  mode: :turn,
                  on_busy: :reject,
                  max_requests: 100,
                  streaming: false,
                  steering: false
                }),
              memory: Zoi.map() |> Zoi.default(%{history: nil}),
              metadata: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )
  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @fields [
    :id,
    :instructions,
    :models,
    :reasoning,
    :controls,
    :tools,
    :tool_sources,
    :tool_context,
    :skills,
    :observability,
    :effect_policy,
    :tool_interceptor,
    :model_router,
    :result,
    :requests,
    :memory,
    :metadata
  ]
  @limits %{max_iterations: 8, max_model_calls: 12, max_tool_calls: 16, timeout: 60_000}
  @stages [:input, :model, :operation, :output]

  @doc "Validates an inert profile. Unknown fields are errors."
  def new(attrs, opts \\ [])

  def new(%__MODULE__{} = profile, opts), do: new(Map.from_struct(profile), opts)

  def new(attrs, opts) do
    with {:ok, opts} <- options(opts),
         {:ok, attrs} <- input_map(attrs),
         {:ok, attrs} <- fields(attrs, @fields ++ [:model], "profile"),
         {:ok, attrs} <- Jido.AI.Profile.References.resolve(attrs, opts[:registries]),
         {:ok, attrs} <- defaults(attrs),
         {:ok, id} <- role(attrs[:id], "profile.id"),
         attrs = Map.put(attrs, :id, id),
         :ok <- identifier(attrs[:id], "profile.id"),
         :ok <- instructions(attrs[:instructions]),
         :ok <- tool_interceptor(attrs[:tool_interceptor]),
         {:ok, effect_policy} <- effect_policy(Map.get(attrs, :effect_policy, %{})),
         {:ok, models} <- models(Map.get(attrs, :models, %{})),
         {:ok, model_router} <- model_router(attrs[:model_router], models),
         {:ok, reasoning} <- reasoning(Map.get(attrs, :reasoning, %{}), models),
         {:ok, tools} <- Jido.AI.ToolCatalog.new(Map.get(attrs, :tools, [])),
         {:ok, tool_sources} <-
           Jido.AI.ToolSource.new(Map.get(attrs, :tool_sources, []), opts[:registries] || %{}),
         :ok <- Jido.AI.ToolContext.validate(Map.get(attrs, :tool_context, %{})),
         {:ok, skills} <- Jido.AI.Skill.Source.new(Map.get(attrs, :skills)),
         {:ok, result} <- result(attrs[:result]),
         {:ok, controls} <- controls(Map.get(attrs, :controls, %{})),
         {:ok, requests} <- requests(Map.get(attrs, :requests, %{})),
         :ok <- skill_mode(skills, requests, reasoning),
         :ok <- method_features(reasoning.method, tools ++ tool_sources, requests),
         :ok <- method_output(reasoning.method, result),
         {:ok, memory} <- memory(Map.get(attrs, :memory, %{})),
         {:ok, observability} <- observability(Map.get(attrs, :observability, %{})),
         :ok <- Jido.Action.validate_static_data(Map.put(attrs, :result, result)) do
      case Zoi.parse(
             @schema,
             Map.merge(attrs, %{
               models: models,
               reasoning: reasoning,
               controls: controls,
               tools: tools,
               tool_sources: tool_sources,
               skills: skills,
               result: result,
               requests: requests,
               memory: memory,
               observability: observability,
               effect_policy: effect_policy,
               model_router: model_router,
               metadata: portable_data(Map.get(attrs, :metadata, %{}))
             })
           ) do
        {:ok, profile} -> {:ok, profile}
        {:error, issues} -> error("profile", Zoi.prettify_errors(issues))
      end
    else
      {:error, error} when is_exception(error) -> {:error, error}
      {:error, reason} -> error("profile", inspect(reason))
    end
  end

  @doc "Builds one validated inert profile or raises its Splode validation error."
  @spec new!(map() | keyword() | t(), keyword()) :: t() | no_return()
  def new!(attrs, opts \\ []) do
    case new(attrs, opts) do
      {:ok, profile} -> profile
      {:error, error} -> raise error
    end
  end

  @doc "Validates one profile value through the canonical constructor."
  @spec validate(term()) :: {:ok, t()} | {:error, Exception.t()}
  def validate(value), do: new(value)

  defp options(opts) when is_list(opts) do
    if Keyword.keyword?(opts) and Keyword.keys(opts) -- [:registries] == [],
      do: {:ok, opts},
      else: error("profile.options", "Expected only a registries option")
  end

  defp options(_), do: error("profile.options", "Expected a keyword list")

  defp input_map(value) when is_map(value) and not is_struct(value), do: {:ok, value}

  defp input_map(value) when is_list(value) do
    if Keyword.keyword?(value) and length(value) == length(Keyword.keys(value) |> Enum.uniq()),
      do: {:ok, Map.new(value)},
      else: error("profile", "Expected unique keyword fields")
  end

  defp input_map(_), do: error("profile", "Expected a map or keyword list")

  defp defaults(attrs) do
    configured = Application.get_env(:jido_ai, :agent_defaults, %{})
    configured = if is_map(configured), do: configured, else: %{}

    model =
      Map.get(
        attrs,
        :model,
        Map.get(configured, :model, :fast)
      )

    {models, router} =
      case Map.get(attrs, :models) do
        nil ->
          {%{default: model}, nil}

        %{} = value ->
          entries = Map.get(value, :entries, Map.get(value, "entries"))

          if is_nil(entries) do
            {value, nil}
          else
            {entries, Map.get(value, :router, Map.get(value, "router"))}
          end

        value ->
          {value, nil}
      end

    attrs =
      attrs
      |> Map.delete(:model)
      |> Map.put(:models, models)
      |> then(fn attrs ->
        if is_nil(router), do: attrs, else: Map.put_new(attrs, :model_router, router)
      end)
      |> Map.put_new(:instructions, Map.get(configured, :instructions))
      |> Map.put_new(:tools, [])
      |> Map.put_new(:tool_sources, [])
      |> Map.put_new(:controls, %{})
      |> Map.put_new(:requests, %{})
      |> Map.put_new(:memory, %{})
      |> Map.put_new(:observability, %{})
      |> Map.put_new(:metadata, %{})

    reasoning = Map.get(attrs, :reasoning, %{})

    reasoning =
      case reasoning do
        value when is_atom(value) -> %{method: value}
        value when is_binary(value) -> %{method: value}
        value when is_list(value) -> if(Keyword.keyword?(value), do: Map.new(value), else: value)
        value -> value
      end

    result = Map.get(attrs, :result)
    result = if is_list(result) and Keyword.keyword?(result), do: Map.new(result), else: result

    {:ok, attrs |> Map.put(:reasoning, reasoning) |> Map.put(:result, result)}
  end

  @doc false
  def fields(map, allowed, path) when is_map(map) and not is_struct(map) do
    Enum.reduce_while(map, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
      field = Enum.find(allowed, &(key == &1 or key == Atom.to_string(&1)))

      cond do
        is_nil(field) -> {:halt, error(path, "Unknown field #{inspect(key)}")}
        Map.has_key?(acc, field) -> {:halt, error(path, "Conflicting field #{inspect(field)}")}
        true -> {:cont, {:ok, Map.put(acc, field, value)}}
      end
    end)
  end

  def fields(_, _, path), do: error(path, "Expected a map")

  @doc false
  def error(path, message),
    do: {:error, Jido.AI.Error.Validation.Invalid.exception(field: path, message: "#{path}: #{message}")}

  @doc false
  def traverse(values, fun), do: Jido.Agent.Authoring.traverse(values, fun)

  @doc false
  def source(%__MODULE__{} = profile) do
    with {:ok, profile} <- new(profile), do: {:ok, {profile, []}}
  end

  def source(value) do
    with {:ok, value} <- input_map(value),
         {:ok, value} <- fields(value, @fields ++ [:model, :routes], "profile"),
         {routes, value} = Map.pop(value, :routes, []),
         {:ok, profile} <- new(value),
         do: {:ok, {profile, routes}}
  end

  defp skill_mode(nil, _, _), do: :ok
  defp skill_mode(_, %{mode: :session}, %{method: :react}), do: :ok

  defp skill_mode(_, _, _),
    do: error("skills", "Automatic skills require a ReAct Session profile")

  defp identifier(id, _) when is_atom(id) and id not in [nil, true, false], do: :ok
  defp identifier(_, path), do: error(path, "Expected a host-defined atom")

  defp instructions(value) when is_nil(value), do: :ok

  defp instructions(""), do: :ok

  defp instructions(value) when is_binary(value) do
    if String.trim(value) == "",
      do: error("instructions", "Expected non-empty text or an empty override"),
      else: :ok
  end

  defp instructions(module) when is_atom(module) do
    with {:module, _} <- Code.ensure_compiled(module),
         {:ok, %{kind: :action}} <- Jido.Executable.resolve(module),
         :ok <- Jido.Executable.validate(module) do
      :ok
    else
      _ -> error("instructions", "Expected text or an Action module")
    end
  end

  defp instructions(_), do: error("instructions", "Expected text, an Action module, or nil")

  defp model_router(nil, _models), do: {:ok, nil}

  defp model_router(%{module: module} = router, models) when is_atom(module) do
    with true <- match?({:module, _}, Code.ensure_compiled(module)),
         true <- function_exported?(module, :route, 2) or function_exported?(module, :select, 2),
         {:ok, fallback} <- optional_role(Map.get(router, :fallback), models) do
      {:ok, %{module: module, fallback: fallback}}
    else
      _ -> error("models.router", "Expected a router module and a declared fallback role")
    end
  end

  defp model_router(_, _models),
    do: error("models.router", "Expected a router module and an optional fallback role")

  defp optional_role(nil, _models), do: {:ok, nil}
  defp optional_role(value, models), do: reasoning_model(value, models)

  defp tool_interceptor(nil), do: :ok

  defp tool_interceptor(module) when is_atom(module) do
    case Code.ensure_compiled(module) do
      {:module, _} ->
        if function_exported?(module, :before_tool_call, 2) or
             function_exported?(module, :after_tool_call, 3),
           do: :ok,
           else: error("tool_interceptor", "Expected a tool callback export")

      _ ->
        error("tool_interceptor", "Callback module is not available")
    end
  end

  defp tool_interceptor(_), do: error("tool_interceptor", "Expected a callback module or nil")

  defp observability(value) do
    with {:ok, value} <-
           fields(
             value,
             [
               :emit_telemetry?,
               :emit_llm_deltas?,
               :emit_signals?,
               :redact_tool_args?,
               :emit_telemetry,
               :emit_llm_deltas,
               :emit_signals,
               :redact_tool_args
             ],
             "observability"
           ),
         value = normalize_observability(value),
         true <- Enum.all?(value, fn {_, flag} -> is_boolean(flag) end) do
      {:ok, value}
    else
      false -> error("observability", "Expected boolean observation flags")
      error -> error
    end
  end

  defp models(models) when is_map(models) and not is_struct(models) and map_size(models) > 0 do
    models
    |> Enum.to_list()
    |> traverse(fn {role, value} ->
      with {:ok, role} <- role(role, "models.role"),
           {:ok, entry} <- model(value),
           do: {:ok, {role, entry}}
    end)
    |> case do
      {:ok, entries} -> {:ok, Map.new(entries)}
      error -> error
    end
  end

  defp models(_), do: error("models", "At least one named model is required")

  defp model(value)
       when is_map(value) and not is_struct(value) and
              (is_map_key(value, :model) or is_map_key(value, "model")) do
    with {:ok, entry} <-
           fields(
             value,
             [
               :model,
               :generation,
               :temperature,
               :max_tokens,
               :timeout,
               :provider_options,
               :metadata
             ],
             "models.entry"
           ),
         true <- Keyword.keyword?(Map.get(entry, :generation, [])),
         {:ok, model} <- model_input(entry.model),
         {:ok, provider_options} <- provider_options(Map.get(entry, :provider_options, %{})),
         {:ok, generation} <- generation(Map.put(entry, :provider_options, provider_options)) do
      {:ok,
       entry
       |> Map.put(:model, model)
       |> Map.put(:generation, generation)
       |> Map.put(:provider_options, Map.new(provider_options))
       |> Map.update(:metadata, %{}, &portable_data/1)}
    else
      false -> error("models.generation", "Expected a keyword list")
      error -> error
    end
  end

  defp model(value) do
    with {:ok, model} <- model_input(value),
         do: {:ok, %{model: model, generation: [], provider_options: %{}, metadata: %{}}}
  end

  defp model_input(value) when is_atom(value) and value not in [nil, true, false], do: {:ok, value}

  defp model_input(value) when value in [nil, true, false] or is_number(value),
    do: error("models", "Invalid ReqLLM model input")

  defp model_input(value) when is_binary(value) and not is_struct(value) do
    aliases = Jido.AI.Models.aliases()

    case Enum.find(Map.keys(aliases), &(Atom.to_string(&1) == value)) do
      nil -> req_llm_model(value)
      alias_name -> {:ok, alias_name}
    end
  end

  defp model_input(value), do: req_llm_model(value)

  defp req_llm_model(value) do
    case ReqLLM.model(value) do
      {:ok, _} -> {:ok, value}
      {:error, _} -> error("models", "Invalid ReqLLM model input")
    end
  end

  defp effect_policy(value) when value in [nil, [], %{}], do: {:ok, %{}}

  defp effect_policy(value) when is_map(value) or is_list(value) do
    with {:ok, value} <- input_map(value),
         {:ok, value} <- fields(value, [:mode, :allow, :deny, :constraints], "effect_policy"),
         {:ok, mode} <- effect_policy_mode(Map.get(value, :mode, :allow_list)),
         {:ok, allow} <- effect_policy_matchers(Map.get(value, :allow), "effect_policy.allow"),
         {:ok, deny} <- effect_policy_matchers(Map.get(value, :deny), "effect_policy.deny"),
         {:ok, constraints} <- effect_policy_constraints(Map.get(value, :constraints, %{})) do
      policy_input =
        value
        |> Map.put(:mode, mode)
        |> maybe_put(:allow, allow)
        |> maybe_put(:deny, deny)
        |> Map.put(:constraints, constraints)

      policy = Jido.AI.Effects.Policy.new(policy_input)

      {:ok,
       %{
         mode: policy.mode,
         allow: Enum.sort(policy.allow),
         deny: Enum.sort(policy.deny),
         constraints: policy.constraints
       }}
    end
  end

  defp effect_policy(_),
    do: error("effect_policy", "Expected an effect policy map or keyword list")

  defp effect_policy_mode(mode) when mode in [:deny_all, :allow_all, :allow_list], do: {:ok, mode}

  defp effect_policy_mode(mode) when is_binary(mode) do
    case Enum.find([:deny_all, :allow_all, :allow_list], &(Atom.to_string(&1) == mode)) do
      nil -> error("effect_policy.mode", "Expected deny_all, allow_all, or allow_list")
      mode -> {:ok, mode}
    end
  end

  defp effect_policy_mode(_),
    do: error("effect_policy.mode", "Expected deny_all, allow_all, or allow_list")

  defp effect_policy_matchers(nil, _path), do: {:ok, nil}
  defp effect_policy_matchers(%MapSet{} = values, path), do: effect_policy_matchers(MapSet.to_list(values), path)

  defp effect_policy_matchers(values, path) when is_list(values) do
    traverse(values, fn value -> effect_policy_matcher(value, path) end)
  end

  defp effect_policy_matchers(_, path), do: error(path, "Expected a list of effect modules")

  defp effect_policy_matcher(module, path)
       when is_atom(module) and module not in [nil, true, false] do
    if module |> Atom.to_string() |> String.starts_with?("Elixir."),
      do: {:ok, module},
      else: error(path, "Expected a module alias, got #{inspect(module)}")
  end

  defp effect_policy_matcher(module, path) when is_binary(module) do
    try do
      effect_policy_matcher(String.to_existing_atom(module), path)
    rescue
      ArgumentError -> error(path, "Unknown effect module #{inspect(module)}")
    end
  end

  defp effect_policy_matcher(value, path),
    do: error(path, "Expected an effect module, got #{inspect(value)}")

  defp effect_policy_constraints(value) do
    with {:ok, value} <- input_map(value),
         {:ok, value} <- fields(value, [:emit, :schedule], "effect_policy.constraints"),
         {:ok, emit} <- effect_policy_emit_constraints(Map.get(value, :emit)),
         {:ok, schedule} <- effect_policy_schedule_constraints(Map.get(value, :schedule)) do
      {:ok, %{} |> maybe_put(:emit, emit) |> maybe_put(:schedule, schedule)}
    end
  end

  defp effect_policy_emit_constraints(nil), do: {:ok, nil}

  defp effect_policy_emit_constraints(value) do
    with {:ok, value} <- input_map(value),
         {:ok, value} <-
           fields(
             value,
             [:allowed_signal_prefixes, :allowed_signal_types, :allowed_dispatches],
             "effect_policy.constraints.emit"
           ),
         :ok <- effect_policy_string_list(value[:allowed_signal_prefixes], "allowed_signal_prefixes"),
         :ok <- effect_policy_string_list(value[:allowed_signal_types], "allowed_signal_types"),
         :ok <- effect_policy_dispatch_list(value[:allowed_dispatches]) do
      {:ok, value}
    end
  end

  defp effect_policy_schedule_constraints(nil), do: {:ok, nil}

  defp effect_policy_schedule_constraints(value) do
    with {:ok, value} <- input_map(value),
         {:ok, value} <-
           fields(value, [:max_delay_ms], "effect_policy.constraints.schedule") do
      case Map.fetch(value, :max_delay_ms) do
        :error ->
          {:ok, value}

        {:ok, max_delay_ms} when is_integer(max_delay_ms) and max_delay_ms >= 0 ->
          {:ok, value}

        {:ok, _max_delay_ms} ->
          error(
            "effect_policy.constraints.schedule.max_delay_ms",
            "Expected a non-negative integer"
          )
      end
    else
      {:error, _} = error -> error
    end
  end

  defp effect_policy_string_list(nil, _field), do: :ok

  defp effect_policy_string_list(values, _field)
       when is_list(values) and values != [] do
    if Enum.all?(values, &(is_binary(&1) and String.trim(&1) != "")),
      do: :ok,
      else: error("effect_policy.constraints.emit", "Expected non-empty strings")
  end

  defp effect_policy_string_list([], _field), do: :ok

  defp effect_policy_string_list(_, field),
    do: error("effect_policy.constraints.emit.#{field}", "Expected a list")

  defp effect_policy_dispatch_list(nil), do: :ok

  defp effect_policy_dispatch_list(values) when is_list(values) do
    if Enum.all?(values, fn
         value when is_atom(value) -> value not in [nil, true, false]
         value when is_binary(value) -> String.trim(value) != ""
         _value -> false
       end),
       do: :ok,
       else: error("effect_policy.constraints.emit.allowed_dispatches", "Expected atoms or strings")
  end

  defp effect_policy_dispatch_list(_),
    do: error("effect_policy.constraints.emit.allowed_dispatches", "Expected a list")

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp reasoning(value, models) do
    with {:ok, value} <-
           fields(
             value,
             [:method, :model, :tool_concurrency, :request_transformer, :effect_policy, :options],
             "reasoning"
           ),
         {:ok, method} <- reasoning_method(Map.get(value, :method, :react)),
         {:ok, model} <- reasoning_model(Map.get(value, :model), models),
         value = value |> Map.put(:method, method) |> Map.put(:model, model),
         {:ok, _} <-
           Jido.AI.Reasoning.ReAct.RequestTransformer.validate(value[:request_transformer]),
         {:ok, policy} <- effect_policy(Map.get(value, :effect_policy, %{})),
         true <-
           value[:method] in [
             :react,
             :chain_of_thought,
             :chain_of_draft,
             :algorithm_of_thoughts,
             :tree_of_thoughts,
             :graph_of_thoughts,
             :trm,
             :adaptive
           ],
         {:ok, method_options} <-
           portable_reasoning_options(value[:method], Map.get(value, :options, %{})),
         {:ok, options} <-
           Jido.AI.Reasoning.options(value[:method], method_options),
         true <- Map.has_key?(models, value[:model]),
         n = Map.get(value, :tool_concurrency, 4),
         true <- is_integer(n) and n in 1..64 do
      value = value |> Map.put(:tool_concurrency, n) |> Map.put(:effect_policy, policy)
      # Empty method settings do not add a new atom requirement to existing
      # source-profile registries. Only methods with settings retain this key.
      {:ok,
       if(options == %{},
         do: Map.delete(value, :options),
         else: Map.put(value, :options, options)
       )}
    else
      false ->
        error(
          "reasoning",
          "Expected a supported method, a declared model role, and concurrency from 1 to 64"
        )

      error ->
        error
    end
  end

  defp method_output(:tree_of_thoughts, %{schema: schema}) when schema != nil,
    do: error("result", "Typed Tree of Thoughts results are not yet ported")

  defp method_output(:graph_of_thoughts, %{schema: schema}) when schema != nil,
    do: error("result", "Typed Graph of Thoughts results are not yet ported")

  defp method_output(:trm, %{schema: schema}) when schema != nil,
    do: error("result", "Typed TRM results are not yet ported")

  defp method_output(_, _), do: :ok

  defp portable_reasoning_options(method, value) when is_list(value) do
    if Keyword.keyword?(value) and length(value) == length(Keyword.keys(value) |> Enum.uniq()),
      do: portable_reasoning_options(method, Map.new(value)),
      else: {:ok, value}
  end

  defp portable_reasoning_options(:algorithm_of_thoughts, value) do
    with {:ok, value} <-
           fields(
             value,
             [:profile, :search_style, :examples, :require_explicit_answer],
             "reasoning.options"
           ) do
      {:ok,
       value
       |> normalize_known(:profile, [:short, :standard, :long])
       |> normalize_known(:search_style, [:dfs, :bfs])}
    end
  end

  defp portable_reasoning_options(:tree_of_thoughts, value) do
    with {:ok, value} <-
           fields(
             value,
             [
               :branching_factor,
               :max_depth,
               :traversal_strategy,
               :top_k,
               :min_depth,
               :max_nodes,
               :max_duration_ms,
               :beam_width,
               :early_success_threshold,
               :convergence_window,
               :min_score_improvement,
               :max_parse_retries,
               :max_tool_round_trips,
               :generation_prompt,
               :evaluation_prompt
             ],
             "reasoning.options"
           ) do
      {:ok, normalize_known(value, :traversal_strategy, [:bfs, :dfs, :best_first])}
    end
  end

  defp portable_reasoning_options(:graph_of_thoughts, value) do
    with {:ok, value} <-
           fields(
             value,
             [
               :max_nodes,
               :max_depth,
               :aggregation_strategy,
               :min_nodes_for_aggregation,
               :generation_prompt,
               :connection_prompt,
               :aggregation_prompt
             ],
             "reasoning.options"
           ) do
      {:ok, normalize_known(value, :aggregation_strategy, [:synthesis, :voting, :weighted])}
    end
  end

  defp portable_reasoning_options(:trm, value),
    do: fields(value, [:max_supervision_steps, :act_threshold], "reasoning.options")

  defp portable_reasoning_options(:adaptive, value) do
    strategies = [:cod, :cot, :react, :aot, :tot, :got, :trm]

    with {:ok, value} <-
           fields(
             value,
             [:available_strategies, :complexity_thresholds, :strategy_override, :method_options],
             "reasoning.options"
           ),
         {:ok, method_options} <-
           portable_adaptive_method_options(Map.get(value, :method_options, %{})) do
      available =
        value
        |> Map.get(:available_strategies, [])
        |> Enum.map(&known_value(&1, strategies))

      {:ok,
       value
       |> Map.put(:method_options, method_options)
       |> then(fn options ->
         if Map.has_key?(options, :available_strategies),
           do: Map.put(options, :available_strategies, available),
           else: options
       end)
       |> normalize_known(:strategy_override, strategies)}
    end
  end

  defp portable_reasoning_options(_method, value), do: {:ok, value}

  defp portable_adaptive_method_options(value) do
    methods = %{
      cod: :chain_of_draft,
      cot: :chain_of_thought,
      react: :react,
      aot: :algorithm_of_thoughts,
      tot: :tree_of_thoughts,
      got: :graph_of_thoughts,
      trm: :trm
    }

    with {:ok, value} <- fields(value, Map.keys(methods), "reasoning.options.method_options") do
      traverse(Enum.to_list(value), fn {strategy, options} ->
        with {:ok, options} <- portable_reasoning_options(methods[strategy], options),
             do: {:ok, {strategy, options}}
      end)
      |> case do
        {:ok, pairs} -> {:ok, Map.new(pairs)}
        error -> error
      end
    end
  end

  defp known_value(value, allowed) when is_binary(value),
    do: Enum.find(allowed, value, &(Atom.to_string(&1) == value))

  defp known_value(value, _allowed), do: value

  defp method_features(:adaptive, _, %{steering: false}), do: :ok
  defp method_features(:tree_of_thoughts, _, %{steering: false}), do: :ok
  defp method_features(:react, _, _), do: :ok
  defp method_features(_, [], %{steering: false}), do: :ok

  defp method_features(_, _, _),
    do: error("reasoning", "This method does not execute tools or accept steering")

  defp requests(value) do
    with {:ok, value} <-
           fields(
             value,
             [
               :mode,
               :on_busy,
               :max_requests,
               :streaming,
               :steering,
               :idle_timeout,
               :tool_heartbeat
             ],
             "requests"
           ),
         value =
           value
           |> normalize_known(:mode, [:turn, :session])
           |> normalize_known(:on_busy, [:reject]),
         value =
           Map.merge(
             %{
               mode: :turn,
               on_busy: :reject,
               max_requests: 100,
               streaming: false,
               steering: false
             },
             value
           ),
         true <-
           value.mode in [:turn, :session] and value.on_busy == :reject and
             is_boolean(value.streaming),
         true <- is_boolean(value.steering) and (not value.steering or value.mode == :session),
         true <- is_integer(value.max_requests) and value.max_requests > 0,
         :ok <- activity_options(value) do
      {:ok, value}
    else
      false ->
        error(
          "requests",
          "Expected turn or session mode, reject on busy, and a positive retention limit"
        )

      error ->
        error
    end
  end

  defp activity_options(value) do
    options = Map.take(value, [:idle_timeout, :tool_heartbeat])

    if options == %{} or
         (value.mode == :session and Enum.all?(options, fn {_, n} -> is_integer(n) and n >= 0 end)),
       do: :ok,
       else:
         error(
           "requests",
           "Idle and heartbeat intervals require session mode and non-negative milliseconds"
         )
  end

  defp memory(value) do
    with {:ok, value} <- fields(value, [:history], "memory"),
         history = value[:history],
         {:ok, history} <- optional_field(history, "memory.history") do
      {:ok, %{history: history}}
    else
      error -> error
    end
  end

  defp controls(value) do
    with {:ok, value} <- fields(value, Map.keys(@limits) ++ @stages, "controls"),
         value = normalize_method_defaults(value),
         limits = Map.merge(@limits, Map.take(value, Map.keys(@limits))),
         true <- Enum.all?(limits, &valid_limit?/1),
         {:ok, stages} <-
           traverse(@stages, fn stage ->
             with {:ok, checks} <- traverse(Map.get(value, stage, []), &control/1),
                  do: {:ok, {stage, checks}}
           end) do
      {:ok, Map.merge(limits, Map.new(stages))}
    else
      false ->
        error(
          "controls",
          "Limits must be positive; count limits can use :method_default; max_iterations cannot exceed 10000"
        )

      error ->
        error
    end
  end

  defp normalize_method_defaults(value) do
    Enum.reduce([:max_iterations, :max_model_calls, :max_tool_calls], value, fn key, acc ->
      if Map.get(acc, key) == "method_default", do: Map.put(acc, key, :method_default), else: acc
    end)
  end

  defp valid_limit?({key, :method_default}), do: key != :timeout
  defp valid_limit?({:max_iterations, n}), do: is_integer(n) and n > 0 and n <= 10_000
  defp valid_limit?({_, n}), do: is_integer(n) and n > 0

  @doc false
  def resolve_controls(%__MODULE__{reasoning: %{method: :adaptive}}),
    do: error("controls", "Select an Adaptive method before resolving its limits")

  def resolve_controls(%__MODULE__{} = profile) do
    limits = resolve_limits(profile.controls, profile.reasoning, profile.result)
    new(%{profile | controls: limits})
  end

  defp resolve_limits(limits, reasoning, result) do
    iterations =
      if limits.max_iterations == :method_default,
        do: Jido.AI.Reasoning.model_call_limit(reasoning.method, Map.get(reasoning, :options, %{})),
        else: limits.max_iterations

    calls =
      if limits.max_model_calls == :method_default,
        do: iterations + result.max_repairs,
        else: limits.max_model_calls

    tools =
      if limits.max_tool_calls == :method_default,
        do: if(reasoning.method == :tree_of_thoughts, do: 10_000, else: 16),
        else: limits.max_tool_calls

    %{limits | max_iterations: iterations, max_model_calls: calls, max_tool_calls: tools}
  end

  defp control(module) when is_atom(module) do
    if match?({:module, _}, Code.ensure_compiled(module)) and
         function_exported?(module, :check, 2),
       do: {:ok, module},
       else: error("controls", "#{inspect(module)} must export check/2")
  end

  defp control(value) when is_map(value) or is_list(value) do
    with {:ok, value} <- input_map(value),
         {:ok, value} <- fields(value, [:module, :when], "controls"),
         {:ok, module} <- control(value[:module]),
         {:ok, match} <- control_match(value[:when]) do
      {:ok, %{module: module, when: match}}
    end
  end

  defp control(value), do: error("controls", "#{inspect(value)} must export check/2")

  defp control_match(value) when is_list(value) do
    if Keyword.keyword?(value),
      do: control_match(Map.new(value)),
      else: error("controls.when", "Expected static match data")
  end

  defp control_match(value) when is_map(value) and not is_struct(value) do
    if Jido.Action.validate_static_data(value) == :ok,
      do: {:ok, portable_data(value)},
      else: error("controls.when", "Expected static match data")
  end

  defp control_match(_), do: error("controls.when", "Expected static match data")

  @doc false
  def portable_data(value) when is_map(value) do
    Map.new(value, fn {key, item} -> {portable_data_key(key), portable_data(item)} end)
  end

  def portable_data(value) when is_list(value), do: Enum.map(value, &portable_data/1)
  def portable_data(value) when is_atom(value) and value not in [nil, true, false], do: Atom.to_string(value)
  def portable_data(value), do: value

  defp portable_data_key(key) when is_atom(key), do: Atom.to_string(key)
  defp portable_data_key(key), do: key

  defp result(nil), do: error("result", "Declare an output field with into")

  defp result(value) do
    with {:ok, value} <-
           fields(
             value,
             [:schema, :into, :max_repairs, :repair_fun, :repair_action, :on_validation_error],
             "result"
           ),
         {:ok, into} <- role(value[:into], "result.into"),
         value =
           value
           |> Map.put(:into, into)
           |> normalize_known(:on_validation_error, [:repair, :error]),
         :ok <- identifier(value[:into], "result.into"),
         :ok <- repair_action(value[:repair_action]),
         n = Map.get(value, :max_repairs, 0),
         true <- is_integer(n) and n in 0..3,
         {:ok, contract} <- output_contract(value) do
      value =
        if contract && Map.has_key?(value, :repair_fun),
          do: Map.put(value, :repair_fun, contract.repair_fun),
          else: value

      {:ok, Map.merge(%{schema: nil, max_repairs: n}, value)}
    else
      false ->
        error("result.max_repairs", "Expected an integer from 0 to 3")

      {:error, reason} ->
        error(
          "result",
          if(is_exception(reason), do: Exception.message(reason), else: inspect(reason))
        )
    end
  end

  @doc false
  def output_contract(%{schema: nil}), do: {:ok, nil}
  def output_contract(value) when not is_map_key(value, :schema), do: {:ok, nil}

  def output_contract(value),
    do:
      Output.new(
        schema: value.schema,
        retries: Map.get(value, :max_repairs, 0),
        repair_fun: value[:repair_fun],
        on_validation_error: Map.get(value, :on_validation_error, :repair)
      )

  defp repair_action(nil), do: :ok

  defp repair_action(module) when is_atom(module) do
    case Jido.Executable.resolve(module) do
      {:ok, %{kind: :action}} -> Jido.Executable.validate(module)
      _ -> error("result.repair_action", "Expected an Action module")
    end
  end

  defp repair_action(_), do: error("result.repair_action", "Expected an Action module")

  defp generation(entry) do
    with true <- valid_optional_number?(entry[:temperature]),
         true <- valid_optional_positive?(entry[:max_tokens]),
         true <- valid_optional_positive?(entry[:timeout]),
         {:ok, provider} <- provider_options(Map.get(entry, :provider_options, %{})),
         metadata = Map.get(entry, :metadata, %{}),
         true <- is_map(metadata) and not is_struct(metadata) do
      direct =
        []
        |> put_generation(:temperature, entry[:temperature])
        |> put_generation(:max_tokens, entry[:max_tokens])
        |> put_generation(:receive_timeout, entry[:timeout])

      {:ok, Map.get(entry, :generation, []) |> Keyword.merge(provider) |> Keyword.merge(direct)}
    else
      false -> error("models.entry", "Invalid model options")
      error -> error
    end
  end

  defp provider_options(value) when is_map(value) and not is_struct(value) do
    value
    |> Enum.to_list()
    |> traverse(&provider_option/1)
  end

  defp provider_options(value) when is_list(value) do
    if Keyword.keyword?(value),
      do: {:ok, value},
      else: error("models.provider_options", "Expected a map or keyword list")
  end

  defp provider_options(_), do: error("models.provider_options", "Expected a map or keyword list")

  defp provider_option({key, value}) when is_atom(key), do: {:ok, {key, value}}

  defp provider_option({key, value}) when is_binary(key) do
    try do
      {:ok, {String.to_existing_atom(key), value}}
    rescue
      ArgumentError -> error("models.provider_options", "Expected registered option names")
    end
  end

  defp put_generation(options, _key, nil), do: options
  defp put_generation(options, key, value), do: Keyword.put(options, key, value)
  defp valid_optional_number?(nil), do: true
  defp valid_optional_number?(value), do: is_number(value)
  defp valid_optional_positive?(nil), do: true
  defp valid_optional_positive?(value), do: is_integer(value) and value > 0

  defp reasoning_method(value) when is_atom(value) do
    if value in [
         :react,
         :chain_of_thought,
         :chain_of_draft,
         :algorithm_of_thoughts,
         :tree_of_thoughts,
         :graph_of_thoughts,
         :trm,
         :adaptive
       ],
       do: {:ok, value},
       else: error("reasoning.method", "Expected a supported reasoning method")
  end

  defp reasoning_method(value) when is_binary(value) do
    case Enum.find(
           [
             :react,
             :chain_of_thought,
             :chain_of_draft,
             :algorithm_of_thoughts,
             :tree_of_thoughts,
             :graph_of_thoughts,
             :trm,
             :adaptive
           ],
           &(Atom.to_string(&1) == value)
         ) do
      nil -> error("reasoning.method", "Expected a supported reasoning method")
      method -> {:ok, method}
    end
  end

  defp reasoning_method(_), do: error("reasoning.method", "Expected a supported reasoning method")

  defp reasoning_model(nil, models) do
    cond do
      Map.has_key?(models, :default) -> {:ok, :default}
      map_size(models) == 1 -> {:ok, models |> Map.keys() |> hd()}
      true -> error("reasoning.model", "Select one declared model role")
    end
  end

  defp reasoning_model(value, models) when is_binary(value) do
    case Enum.find(Map.keys(models), &(Atom.to_string(&1) == value)) do
      nil -> error("reasoning.model", "Select one declared model role")
      role -> {:ok, role}
    end
  end

  defp reasoning_model(value, models) do
    if Map.has_key?(models, value),
      do: {:ok, value},
      else: error("reasoning.model", "Select one declared model role")
  end

  defp role(value, _) when is_atom(value) and value not in [nil, true, false], do: {:ok, value}

  defp role(value, path) when is_binary(value) do
    try do
      value |> String.to_existing_atom() |> role(path)
    rescue
      ArgumentError -> error(path, "Expected a host-defined atom")
    end
  end

  defp role(_, path), do: error(path, "Expected a host-defined atom")

  defp optional_field(nil, _path), do: {:ok, nil}
  defp optional_field(value, path), do: role(value, path)

  defp normalize_known(value, key, allowed) do
    case Map.get(value, key) do
      text when is_binary(text) ->
        case Enum.find(allowed, &(Atom.to_string(&1) == text)) do
          nil -> value
          atom -> Map.put(value, key, atom)
        end

      _ ->
        value
    end
  end

  defp normalize_observability(value) do
    Enum.reduce(
      [
        emit_telemetry: :emit_telemetry?,
        emit_llm_deltas: :emit_llm_deltas?,
        emit_signals: :emit_signals?,
        redact_tool_args: :redact_tool_args?
      ],
      value,
      fn {public, runtime}, acc ->
        if Map.has_key?(acc, public) do
          acc |> Map.put(runtime, acc[public]) |> Map.delete(public)
        else
          acc
        end
      end
    )
  end
end
