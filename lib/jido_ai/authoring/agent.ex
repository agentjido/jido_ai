defmodule Jido.AI.Agent do
  @moduledoc """
  Builds a v3 Agent from the existing AI Agent options.

  The option adapter uses `Jido.AI.Authoring` and the same profile, core Flow,
  and session Plugin as the `agent do` AI extension. `ask/3` returns a handle
  after admission commits. `await/2` reads the committed result. `ask_stream/3`
  adds the canonical request event stream.

  The request Plugin owns `state.requests`. The domain has `model`,
  `last_request_id`, `last_query`, `last_answer`, `last_result`, `completed`, and
  `messages`. `last_answer` retains the text view; `last_result` holds the typed
  value. Core `new/1` returns `{:ok, agent}`; use `new!/1` for a direct value.

  This port is in progress. Unsupported authoring options raise an error.
  Skills, lifecycle Signals, standalone execution and v2 checkpoint conversion
  still require their migration slices. Session streams support idle timeouts
  and optional tool keepalives through one event owner.
  Native v3 checkpoints use the core checkpoint and restore functions.
  """

  @doc """
  Builds a v3 instance from application initial state and an optional AI Context.

  `source` is an Agent module or neutral definition. Options are `:id` and
  `:profile`. The selected profile must declare history when the state contains
  `:context`. A saved prompt replaces that profile's prompt; nil keeps its
  configured prompt. Other fields must belong to the Agent's domain schema.

  This imports conversation data before Server startup. It does not resume an
  old worker, convert Plugin state, or decode an old Agent checkpoint. Keep
  native checkpoint restore separate. No model or tool runs during import.
  """
  def from_initial_state(source, state, opts \\ []) do
    Jido.AI.Agent.InitialState.import(source, state, opts)
  end

  @doc false
  def expand_aliases_in_ast(ast, caller_env) do
    Macro.prewalk(ast, fn
      {:__aliases__, _, _} = alias_node ->
        Macro.expand(alias_node, caller_env)

      # Allow literals
      literal when is_atom(literal) or is_binary(literal) or is_number(literal) ->
        literal

      # Allow list syntax
      list when is_list(list) ->
        list

      # Allow map struct syntax: %{...}
      {:%{}, meta, pairs} ->
        {:%{}, meta, pairs}

      # Allow struct syntax: %Module{...}
      {:%, meta, args} ->
        {:%, meta, args}

      # Allow tuple syntax: {...}
      {:{}, meta, elements} ->
        {:{}, meta, elements}

      # Allow 2-tuples (key-value pairs in maps)
      {key, value} when not is_atom(key) or key not in [:__aliases__, :%, :%{}, :{}] ->
        {key, value}

      # Reject module attributes with clear error
      {:@, meta, [{name, _, _}]} ->
        raise CompileError,
          description:
            "Module attributes (@#{name}) are not supported in tool_context, tools, or specialists. " <>
              "Define the value inline or use a compile-time constant.",
          line: Keyword.get(meta, :line, 0)

      # Reject pinned variables
      {:^, meta, _} ->
        raise CompileError,
          description:
            "Pinned variables (^) are not supported in tool_context, tools, or specialists. " <>
              "Use literal values instead.",
          line: Keyword.get(meta, :line, 0)

      # Reject function calls and other unsafe constructs
      {func, meta, args} = node when is_atom(func) and is_list(args) ->
        if func in [:__aliases__, :%, :%{}, :{}] do
          node
        else
          raise CompileError,
            description:
              "Unsafe construct in tool_context or tools: function call #{inspect(func)} is not allowed. " <>
                "Only module aliases, atoms, strings, numbers, lists, and maps are permitted.",
            line: Keyword.get(meta, :line, 0)
        end

      other ->
        other
    end)
  end

  @doc false
  def expand_and_eval_literal_option(value, caller_env) do
    case value do
      nil ->
        nil

      value when is_tuple(value) ->
        value
        |> expand_aliases_in_ast(caller_env)
        |> Code.eval_quoted([], caller_env)
        |> elem(0)

      value when is_map(value) ->
        value

      value when is_list(value) ->
        value
        |> expand_aliases_in_ast(caller_env)
        |> Code.eval_quoted([], caller_env)
        |> elem(0)

      other ->
        other
    end
  end

  @doc false
  def normalize_system_prompt_value(value, file, line) do
    case value do
      nil -> :absent
      false -> :absent
      "" -> :absent
      value when is_binary(value) -> {:resolved, value}
      other -> raise_invalid_system_prompt!(other, file, line)
    end
  end

  defp raise_invalid_system_prompt!(value, file, line) do
    raise CompileError,
      description:
        "system_prompt must be a binary, nil, false, or a compile-time literal/module attribute resolving to one, got: #{inspect(value)}",
      file: file,
      line: line
  end

  defp system_prompt_line({_, meta, _}, default), do: Keyword.get(meta, :line, default)
  defp system_prompt_line(_, default), do: default

  @doc false
  def expand_and_eval_output_option(nil, _caller_env, _file, _line), do: nil

  def expand_and_eval_output_option(value, caller_env, file, line) do
    value =
      case value do
        value when is_map(value) ->
          value

        value when is_list(value) ->
          value
          |> Macro.prewalk(fn
            {:__aliases__, _, _} = alias_node -> Macro.expand(alias_node, caller_env)
            other -> other
          end)
          |> Code.eval_quoted([], caller_env)
          |> elem(0)

        other ->
          other
          |> Macro.expand(caller_env)
          |> Code.eval_quoted([], caller_env)
          |> elem(0)
      end

    Jido.AI.Output.new!(value)
  rescue
    error ->
      raise CompileError,
        description: "invalid output option: #{Exception.message(error)}",
        file: file,
        line: line
  end

  defmacro __using__(opts) do
    if canonical_use?(opts) do
      canonical_using(opts, __CALLER__)
    else
      prompt = Keyword.get(opts, :system_prompt)
      prompt_line = system_prompt_line(prompt, __CALLER__.line)

      prompt_ast =
        case prompt do
          {:@, _, [_]} ->
            prompt

          other ->
            expanded = Macro.expand(other, __CALLER__)

            unless Macro.quoted_literal?(expanded),
              do:
                raise(CompileError,
                  file: __CALLER__.file,
                  line: prompt_line,
                  description: "system_prompt requires text or a bare module attribute"
                )

            expanded
        end

      routes_ast =
        case Keyword.get(opts, :signal_routes, []) do
          {:@, _, [_]} = attribute -> attribute
          value -> value |> expand_and_eval_literal_option(__CALLER__) |> Macro.escape()
        end

      values =
        opts
        |> Keyword.drop([:system_prompt, :signal_routes])
        |> Enum.map(fn
          {:output, value} ->
            {:output, expand_and_eval_output_option(value, __CALLER__, __CALLER__.file, __CALLER__.line)}

          {key, value} ->
            {key, expand_and_eval_literal_option(value, __CALLER__)}
        end)

      defaults = Keyword.get(values, :tool_context, %{})
      unless is_map(defaults), do: raise(ArgumentError, "tool_context must be a map")

      case Jido.Action.validate_static_data(defaults) do
        :ok ->
          :ok

        {:error, reason} ->
          raise ArgumentError, "tool_context must be static data: #{inspect(reason)}"
      end

      quote location: :keep do
        @jido_ai_options Keyword.put(
                           Keyword.put(
                             unquote(Macro.escape(values)),
                             :signal_routes,
                             unquote(routes_ast)
                           ),
                           :system_prompt,
                           case Jido.AI.Agent.normalize_system_prompt_value(
                                  unquote(prompt_ast),
                                  __ENV__.file,
                                  unquote(prompt_line)
                                ) do
                             :absent -> nil
                             {:resolved, prompt} -> prompt
                           end
                         )
        use Jido.Agent, Jido.AI.Agent.Options.lower!(@jido_ai_options)

        @jido_ai_label Jido.AI.Reasoning.label(Keyword.get(@jido_ai_options, :reasoning, :react))
        @jido_ai_query_type "ai.#{@jido_ai_label}.query"
        @jido_ai_cancel_type "ai.#{@jido_ai_label}.cancel"
        @jido_ai_source "/ai/#{@jido_ai_label}/agent"

        import Jido.AI.Agent, only: [tools_from_skills: 1]
        @behaviour Jido.AI.ToolInterceptor
        @before_compile Jido.AI.Agent

        @doc "Admits a request and returns its handle."
        def ask(server, query, opts \\ []) when is_binary(query) or is_list(query) do
          with {:ok, opts} <- Jido.AI.Agent.request_options(opts, %{}) do
            Jido.AI.Request.create_and_send(
              server,
              query,
              Keyword.merge(opts, signal_type: @jido_ai_query_type, source: @jido_ai_source)
            )
          end
        end

        @doc "Admits a request and returns its handle and event stream."
        def ask_stream(server, query, opts \\ []) when is_binary(query) or is_list(query) do
          with {:ok, request} <- ask(server, query, Keyword.put(opts, :stream_to, {:pid, self()})) do
            {:ok, %{request: request, events: Jido.AI.Request.Stream.events(request, opts)}}
          end
        end

        @doc "Waits for one committed result."
        def await(request, opts \\ []), do: Jido.AI.Request.await(request, opts)

        @doc "Admits a request and waits for its result."
        def ask_sync(server, query, opts \\ []) when is_binary(query) or is_list(query) do
          with {:ok, request} <- ask(server, query, opts), do: await(request, opts)
        end

        @doc "Sends an advisory cancellation for the active request or a supplied request ID."
        def cancel(server, opts \\ []) do
          data = %{
            request_id: opts[:request_id],
            reason: Keyword.get(opts, :reason, :user_cancelled)
          }

          signal = Jido.Signal.new!(@jido_ai_cancel_type, data, source: @jido_ai_source)
          Jido.AgentServer.cast(server, signal)
        end

        @doc "Queues input and returns the committed Agent or a tagged rejection."
        def steer(server, content, opts \\ []) when is_binary(content),
          do:
            Jido.AI.Session.control_agent(
              server,
              content,
              :steer,
              Keyword.put_new(opts, :source, @jido_ai_source)
            )

        @doc "Queues peer input with the same result contract as steer/3."
        def inject(server, content, opts \\ []) when is_binary(content),
          do:
            Jido.AI.Session.control_agent(
              server,
              content,
              :inject,
              Keyword.put_new(opts, :source, @jido_ai_source)
            )

        defoverridable ask: 3, ask_stream: 3, await: 2, ask_sync: 3, cancel: 2, steer: 3, inject: 3
      end
    end
  end

  defp canonical_use?(opts) do
    is_list(opts) and Keyword.keyword?(opts) and
      Keyword.keys(opts) -- [:name, :description, :metadata, :max_state_size, :extensions] == []
  end

  defp canonical_using(opts, caller_env) do
    {max_state_size, opts} = Keyword.pop(opts, :max_state_size)
    metadata = Keyword.get(opts, :metadata, {:%{}, [], []})

    metadata =
      if is_nil(max_state_size) do
        metadata
      else
        quote do
          Map.put(
            unquote(metadata),
            Jido.AI.Authoring.state_size_key(),
            unquote(max_state_size)
          )
        end
      end

    extensions_ast = Keyword.get(opts, :extensions, [])

    extensions =
      case extensions_ast do
        {:@, _, _} ->
          raise CompileError,
            file: caller_env.file,
            line: caller_env.line,
            description: "extensions must be an inline compile-time list of modules"

        value ->
          value |> Code.eval_quoted([], caller_env) |> elem(0)
      end

    unless is_list(extensions) and Enum.all?(extensions, &is_atom/1) do
      raise CompileError,
        file: caller_env.file,
        line: caller_env.line,
        description: "extensions must be a compile-time list of modules"
    end

    opts =
      opts
      |> Keyword.put(:metadata, metadata)
      |> Keyword.put(:extensions, Enum.uniq([Jido.AI.DSL | extensions]))

    quote location: :keep do
      use Jido.Agent, unquote(opts)

      import Jido.AI.Agent, only: [tools_from_skills: 1]

      @doc "Runs one request with the selected AI profile."
      def ask(server, query, opts \\ []),
        do: Jido.AI.Agent.ask_request(__MODULE__, server, query, opts)

      @doc "Runs one request and waits for a completed result when needed."
      def ask_sync(server, query, opts \\ []),
        do: Jido.AI.Agent.ask_sync_request(__MODULE__, server, query, opts)

      @doc "Runs one streaming session request."
      def ask_stream(server, query, opts \\ []),
        do: Jido.AI.Agent.ask_stream_request(__MODULE__, server, query, opts)

      @doc "Waits for one admitted session request."
      def await(request, opts \\ []), do: Jido.AI.Request.await(request, opts)

      @doc "Cancels one active session request."
      def cancel(server, opts \\ []), do: Jido.AI.Agent.cancel_request(server, opts)

      @doc "Queues visible input for an active session request."
      def steer(server, content, opts \\ []), do: Jido.AI.steer(server, content, opts)

      defoverridable ask: 3, ask_sync: 3, ask_stream: 3, await: 2, cancel: 2, steer: 3
    end
  end

  @doc "Returns all declared AI profiles from an Agent module or definition."
  def profiles(module) when is_atom(module), do: profiles(module.definition())

  def profiles(%Jido.Agent{} = agent) do
    case Jido.AI.Configuration.options(agent) do
      {:ok, options} -> Keyword.fetch!(options, :profiles)
      {:error, _} -> %{}
    end
  end

  @doc "Returns one declared AI profile or nil."
  def profile(source, id), do: Map.get(profiles(source), id)

  @doc false
  def ask_request(module, server, query, opts) do
    with {:ok, profile, route} <- request_route(module, opts) do
      case profile.requests.mode do
        :session ->
          Jido.AI.Request.create_and_send(
            server,
            query,
            Keyword.merge(opts, signal_type: route.path, source: "/jido/ai/agent")
          )

        :turn ->
          signal = Jido.Signal.new!(route.path, %{query: query}, source: "/jido/ai/agent")

          with {:ok, agent} <- Jido.AgentServer.call(server, signal, timeout: opts[:timeout] || 30_000),
               do: {:ok, Map.fetch!(agent.state, profile.result.into)}
      end
    end
  end

  @doc false
  def ask_sync_request(module, server, query, opts) do
    with {:ok, profile, _route} <- request_route(module, opts),
         {:ok, result} <- ask_request(module, server, query, opts) do
      if profile.requests.mode == :session,
        do: Jido.AI.Request.await(result, opts),
        else: {:ok, result}
    end
  end

  @doc false
  def ask_stream_request(module, server, query, opts) do
    with {:ok, profile, _route} <- request_route(module, opts),
         true <- profile.requests.mode == :session and profile.requests.streaming,
         {:ok, request} <- ask_request(module, server, query, Keyword.put(opts, :stream_to, {:pid, self()})) do
      {:ok, %{request: request, events: Jido.AI.Request.Stream.events(request, opts)}}
    else
      false -> Jido.AI.Profile.error("requests.streaming", "Select a streaming session profile")
      error -> error
    end
  end

  @doc false
  def cancel_request(server, opts) do
    data = %{request_id: opts[:request_id], reason: Keyword.get(opts, :reason, :user_cancelled)}
    signal = Jido.Signal.new!(Jido.AI.Session.cancel_type(), data, source: "/jido/ai/agent")
    Jido.AgentServer.cast(server, signal)
  end

  defp request_route(module, opts) do
    profiles = profiles(module)
    id = opts[:profile]

    profile =
      cond do
        not is_nil(id) -> Map.get(profiles, id)
        map_size(profiles) == 1 -> profiles |> Map.values() |> hd()
        true -> nil
      end

    route =
      if profile do
        Enum.find(module.routes(), fn route ->
          {target, defaults} = Jido.Agent.Authoring.split_target(route.target)

          target in [Jido.AI.Runtime.Run, Jido.AI.Session.Start] and
            is_map(defaults) and defaults[:profile_id] == profile.id
        end)
      end

    if profile && route,
      do: {:ok, profile, route},
      else: Jido.AI.Profile.error("profile", "Select one routed AI profile")
  end

  @doc false
  defmacro __before_compile__(env) do
    pending =
      Enum.filter(
        [on_before_cmd: 2, on_after_cmd: 3],
        &Module.defines?(env.module, &1)
      )

    if pending != [],
      do:
        raise(CompileError,
          file: env.file,
          line: env.line,
          description: "Agent callbacks are not yet ported: #{inspect(pending)}"
        )

    quote(do: :ok)
  end

  @doc false
  def request_options(opts, defaults) do
    case Keyword.get(opts, :tool_context, %{}) do
      context when is_map(context) ->
        {:ok, Keyword.put(opts, :tool_context, Map.merge(defaults, context))}

      _ ->
        {:error, :invalid_tool_context}
    end
  end

  @doc false
  @spec compatibility_overrides_ast() :: Macro.t()
  def compatibility_overrides_ast do
    quote location: :keep do
      @behaviour Jido.AI.ToolInterceptor

      @impl Jido.AI.ToolInterceptor
      def before_tool_call(tool_call, _context), do: {:ok, tool_call}

      @impl Jido.AI.ToolInterceptor
      def after_tool_call(_tool_call, result, _context), do: {:ok, result}

      # Broaden the contract to avoid false positives from upstream plugin-spec typing.
      @spec plugin_specs() :: [map()]
      def plugin_specs, do: @plugin_specs

      @doc """
      Builds a durable checkpoint payload for this agent.

      Removes request stream sinks and ReAct process handles before storage.
      """
      @impl true
      @spec checkpoint(Jido.Agent.t(), map()) :: {:ok, map()} | {:error, term()}
      def checkpoint(agent, ctx) do
        sanitized = %{agent | state: Jido.AI.Checkpoint.sanitize_state(agent.state)}
        super(sanitized, ctx)
      end

      @impl true
      @spec restore(map(), map()) :: {:ok, Jido.Agent.t()} | {:error, term()}
      def restore(data, ctx) when is_map(data) and is_map(ctx) do
        agent = new(id: data[:id])

        base_state =
          (data[:state] || %{})
          |> Jido.AI.Checkpoint.rehydrate_state()
          |> Jido.AI.Context.Operations.migrate_state(agent.id)

        agent = %{agent | state: Map.merge(agent.state, base_state)}
        externalized_keys = data[:externalized_keys] || %{}

        Enum.reduce_while(@plugin_instances, {:ok, agent}, fn instance, {:ok, acc} ->
          config = instance.config || %{}
          restore_ctx = Map.put(ctx, :config, config)

          ext_key =
            Enum.find_value(externalized_keys, fn {k, v} ->
              if v == instance.state_key, do: k
            end)

          pointer = if is_nil(ext_key), do: nil, else: Map.get(data, ext_key)

          if pointer do
            case instance.module.on_restore(pointer, restore_ctx) do
              {:ok, nil} ->
                {:cont, {:ok, acc}}

              {:ok, restored_state} ->
                {:cont, {:ok, %{acc | state: Map.put(acc.state, instance.state_key, restored_state)}}}

              {:error, reason} ->
                {:halt, {:error, reason}}
            end
          else
            {:cont, {:ok, acc}}
          end
        end)
      end

      def restore(_data, _ctx), do: {:error, :invalid_checkpoint_payload}

      defoverridable before_tool_call: 2,
                     after_tool_call: 3,
                     checkpoint: 2
    end
  end

  @doc """
  Extract tool action modules from skills.

  Useful when you want to use skill actions as agent tools.

  ## Example

      @skills [MyApp.WeatherSkill, MyApp.LocationSkill]

      use Jido.AI.Agent,
        name: "weather_agent",
        tools: Jido.AI.Agent.tools_from_skills(@skills),
        skills: Enum.map(@skills, & &1.skill_spec(%{}))
  """
  @spec tools_from_skills([module()]) :: [module()]
  def tools_from_skills(skill_modules) when is_list(skill_modules) do
    skill_modules
    |> Enum.flat_map(& &1.actions())
    |> Enum.uniq()
  end
end
