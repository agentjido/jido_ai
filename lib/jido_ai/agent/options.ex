defmodule Jido.AI.Agent.Options do
  @moduledoc false
  alias Jido.AI.{Authoring, Output}

  @supported ~w(reasoning reasoning_options temperature request_timeout_ms llm_timeout_ms name description tags tools model system_prompt max_iterations max_tool_calls max_tokens streaming request_policy tool_timeout_ms tool_max_retries tool_retry_backoff_ms tool_context req_http_options llm_opts output signal_routes plugins retrieval quota default_plugins max_state_size runtime_adapter request_transformer observability effect_policy strategy_effect_policy stream_timeout_ms stream_receive_timeout_ms tool_heartbeat_ms agent_skills)a

  def lower!(opts) do
    unknown = Keyword.keys(opts) -- @supported

    if unknown != [],
      do: raise(ArgumentError, "Agent options are not yet ported: #{inspect(unknown)}")

    unless Keyword.get(opts, :default_plugins) in [nil, false],
      do:
        raise(
          ArgumentError,
          "Core default_plugins overrides require explicit v3 Plugin and state conversion; AI defaults are configured through plugins"
        )

    method = Keyword.get(opts, :reasoning, :react)

    unless method in [
             :react,
             :chain_of_thought,
             :chain_of_draft,
             :algorithm_of_thoughts,
             :tree_of_thoughts,
             :graph_of_thoughts,
             :trm,
             :adaptive
           ],
           do: raise(ArgumentError, "Agent reasoning method is not yet ported: #{inspect(method)}")

    linear? = Jido.AI.Reasoning.Linear.linear?(method)
    single_pass? = Jido.AI.Reasoning.single_pass?(method)
    fresh? = single_pass? or method in [:tree_of_thoughts, :graph_of_thoughts, :trm, :adaptive]
    model = Keyword.get(opts, :model, :fast)

    iterations =
      Keyword.get(opts, :max_iterations, if(method == :adaptive, do: :method_default, else: 10))

    output = Output.new!(opts[:output])

    tokens =
      cond do
        Keyword.has_key?(opts, :max_tokens) -> [max_tokens: opts[:max_tokens]]
        linear? or method == :adaptive -> []
        method == :algorithm_of_thoughts -> [max_tokens: 2048]
        method in [:tree_of_thoughts, :graph_of_thoughts, :trm] -> [max_tokens: 1024]
        true -> [max_tokens: 4096]
      end

    tokens =
      if Keyword.has_key?(opts, :temperature),
        do: Keyword.put(tokens, :temperature, opts[:temperature]),
        else: tokens

    llm_timeout = opts[:llm_timeout_ms]

    if llm_timeout != nil and (not is_integer(llm_timeout) or llm_timeout <= 0),
      do: raise(ArgumentError, "llm_timeout_ms must be a positive integer or nil")

    tokens = if llm_timeout, do: Keyword.put(tokens, :receive_timeout, llm_timeout), else: tokens

    generation =
      tokens
      |> Keyword.merge(model_options!(Keyword.get(opts, :llm_opts, [])))
      |> then(fn generation ->
        if Keyword.has_key?(opts, :req_http_options),
          do:
            Keyword.put(
              generation,
              :req_http_options,
              keyword!(opts[:req_http_options], :req_http_options)
            ),
          else: generation
      end)

    repairs = if output && output.on_validation_error == :repair, do: output.retries, else: 0

    tool_input =
      if(fresh?, do: Keyword.get(opts, :tools, []), else: Keyword.fetch!(opts, :tools))

    ensure_tool_modules_compiled!(tool_input)
    tools = tools!(tool_input, tool_defaults(opts))

    profile = %{
      id: :assistant,
      observability: Keyword.get(opts, :observability, %{}),
      effect_policy: Keyword.get(opts, :effect_policy, %{}),
      instructions: instructions(method, opts[:system_prompt]),
      tool_context: Keyword.get(opts, :tool_context, %{}),
      skills: Keyword.get(opts, :agent_skills),
      models: %{answer: %{model: model, generation: generation}},
      reasoning: %{
        method: method,
        model: :answer,
        options: Keyword.get(opts, :reasoning_options, %{}),
        request_transformer: opts[:request_transformer],
        effect_policy: Keyword.get(opts, :strategy_effect_policy, %{})
      },
      requests:
        Jido.AI.Session.RequestScope.stream_options(
          %{
            mode: :session,
            streaming: Keyword.get(opts, :streaming, true),
            steering: not fresh?,
            on_busy: Keyword.get(opts, :request_policy, :reject)
          },
          Map.new(opts)
        ),
      controls: %{
        max_iterations: iterations,
        max_model_calls: if(iterations == :method_default, do: :method_default, else: iterations + repairs),
        max_tool_calls:
          Keyword.get(
            opts,
            :max_tool_calls,
            if(method == :adaptive, do: :method_default, else: 16)
          ),
        timeout: Keyword.get(opts, :request_timeout_ms, 60_000)
      },
      tools: tools,
      result: %{
        into: :last_result,
        schema: if(output, do: output.schema),
        max_repairs: repairs,
        repair_fun: if(output, do: output.repair_fun),
        on_validation_error: if(output, do: output.on_validation_error, else: :repair)
      },
      memory: %{history: if(fresh?, do: nil, else: :messages)}
    }

    plugins = Jido.AI.PluginStack.for_agent(opts)

    Enum.each(plugins, fn {module, _} -> ensure_plugin_compiled!(module) end)

    explicit_routes =
      [
        {"ai.#{Jido.AI.Reasoning.label(method)}.query", Authoring.ai(:assistant)},
        {"ai.#{Jido.AI.Reasoning.label(method)}.cancel", Jido.AI.Session.Cancel}
      ] ++ Keyword.get(opts, :signal_routes, [])

    routes =
      case Jido.AI.PluginStack.routes(plugins, explicit_routes) do
        {:ok, routes} -> routes
        {:error, error} -> raise error
      end

    Enum.each(routes, fn route ->
      target =
        case route.target do
          {target, defaults} when is_map(defaults) -> target
          target -> target
        end

      if is_atom(target), do: Code.ensure_compiled!(target)
    end)

    domain_schema = schema(model, method)

    domain_schema =
      if Enum.any?(plugins, &Jido.AI.PluginStack.capability?(elem(&1, 0))),
        do: %{
          domain_schema
          | fields: Keyword.put(domain_schema.fields, :capability_result, Zoi.any() |> Zoi.default(nil))
        },
        else: domain_schema

    metadata =
      case opts[:max_state_size] do
        nil -> %{tags: Keyword.get(opts, :tags, [])}
        limit -> %{Authoring.state_size_key() => limit, tags: Keyword.get(opts, :tags, [])}
      end

    base = %{
      name: Keyword.fetch!(opts, :name),
      description: Keyword.get(opts, :description, "AI agent #{opts[:name]}"),
      metadata: metadata,
      schema: domain_schema,
      plugins: plugins,
      routes: routes
    }

    case Authoring.lower(base, [profile]) do
      {:ok, definition} ->
        definition
        |> Map.from_struct()
        |> Map.drop([:id, :state, :module, :vsn])
        |> Map.update!(:plugins, fn plugins ->
          Enum.map(plugins, fn
            {Jido.AI.Runtime.Plugin, config} ->
              {Jido.AI.Runtime.Plugin,
               config
               |> Keyword.put(:legacy_agent_profile, :assistant)
               |> Keyword.put(:tool_defaults, tool_defaults(opts))}

            other ->
              other
          end)
        end)
        |> Enum.to_list()

      {:error, error} ->
        raise error
    end
  end

  defp instructions(method, prompt) when prompt in [nil, false, ""] do
    cond do
      Jido.AI.Reasoning.Linear.linear?(method) ->
        Jido.AI.Reasoning.Linear.default_prompt(method)

      method == :react ->
        Jido.AI.Reasoning.react_prompt()

      true ->
        nil
    end
  end

  defp instructions(_method, prompt), do: prompt

  defp ensure_plugin_compiled!(module) do
    Code.ensure_compiled!(module)

    case module.__jido_plugin__() do
      %Jido.Plugin.Manifest{} = manifest ->
        manifest
        |> Map.take([:agent, :agent_server, :persistence, :topology])
        |> Map.values()
        |> Enum.reject(&is_nil/1)
        |> Enum.each(&Code.ensure_compiled!/1)

      _ ->
        :ok
    end
  end

  defp schema(model, method) do
    fields = %{
      model: Zoi.any() |> Zoi.default(model),
      last_request_id: Zoi.string() |> Zoi.nullable() |> Zoi.default(nil),
      last_query: Jido.AI.Query.schema() |> Zoi.default(""),
      last_answer: Zoi.string() |> Zoi.default(""),
      last_result: Zoi.any() |> Zoi.default(nil),
      completed: Zoi.boolean() |> Zoi.default(false),
      messages: Zoi.list(Zoi.map()) |> Zoi.default([])
    }

    fields =
      if Jido.AI.Reasoning.Linear.linear?(method) or
           method in [:graph_of_thoughts, :trm, :adaptive],
         do:
           Map.merge(fields, %{
             last_prompt: Jido.AI.Query.schema() |> Zoi.default(""),
             last_result: Zoi.string() |> Zoi.default("")
           }),
         else: fields

    fields =
      if method in [:algorithm_of_thoughts, :tree_of_thoughts],
        do: Map.put(fields, :last_prompt, Jido.AI.Query.schema() |> Zoi.default("")),
        else: fields

    fields =
      if method == :adaptive,
        do: Map.put(fields, :selected_strategy, Zoi.atom() |> Zoi.nullable() |> Zoi.default(nil)),
        else: fields

    Zoi.object(fields)
  end

  defp tool_defaults(opts) do
    %{
      forward_context: :all,
      timeout: Keyword.get(opts, :tool_timeout_ms, 15_000),
      max_retries: Keyword.get(opts, :tool_max_retries, 1),
      retry_backoff: Keyword.get(opts, :tool_retry_backoff_ms, 200)
    }
  end

  defp tools!(input, defaults) do
    case Jido.AI.ToolCatalog.from_input(input, defaults) do
      {:ok, tools} -> tools
      {:error, error} when is_exception(error) -> raise error
      {:error, error} -> raise ArgumentError, "Invalid Agent tools: #{inspect(error)}"
    end
  end

  defp ensure_tool_modules_compiled!(tools) when is_list(tools) do
    Enum.each(tools, fn
      module when is_atom(module) -> Code.ensure_compiled(module)
      %{target: module} when is_atom(module) -> Code.ensure_compiled(module)
      _other -> :ok
    end)
  end

  defp ensure_tool_modules_compiled!(_tools), do: :ok

  defp model_options!(value) do
    if Keyword.keyword?(value) or (is_map(value) and not is_struct(value)),
      do: Jido.AI.Reasoning.ReAct.Config.normalize_option_names(value),
      else: raise(ArgumentError, "llm_opts must be a keyword list or map")
  end

  defp keyword!(value, key) do
    if Keyword.keyword?(value),
      do: value,
      else: raise(ArgumentError, "#{key} must be a keyword list")
  end
end
