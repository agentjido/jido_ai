defmodule Jido.AI.Runtime.Plugin do
  @moduledoc "Binds host AI profiles and owns portable tool and prompt overrides."
  use Jido.Plugin

  @impl Jido.Plugin
  def state_spec(opts) do
    {Jido.AI.Configuration.key(),
     Zoi.map()
     |> Zoi.refine({Jido.AI.Configuration, :validate_state, [opts[:profiles]]})
     |> Zoi.default(%{})}
  end

  @impl Jido.Plugin
  def directives(_), do: [Jido.AI.Configuration.Change]
  @impl Jido.Plugin
  def validate_directive(change, opts), do: Jido.AI.Configuration.validate(change, opts)
  @impl Jido.Plugin
  def update_state(state, directives, opts),
    do: Jido.AI.Configuration.reduce(state, directives, opts)

  @impl Jido.Plugin
  def prepare(command, opts) do
    binding = Jido.AI.Authoring.request_binding(command.agent, command.signal)

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

  defp request_models(profiles, nil, _), do: {:ok, profiles}

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
        model = Jido.AI.Models.resolve_model(model)
        models = Map.update!(profile.models, profile.reasoning.model, &Map.put(&1, :model, model))
        {:ok, Map.put(profiles, id, %{profile | models: models})}
      else
        _ -> Jido.AI.Profile.error("profile", "No trusted profile binding")
      end
    end
  rescue
    error in ArgumentError -> Jido.AI.Profile.error("model", Exception.message(error))
  end
end

defmodule Jido.AI.Control do
  @moduledoc "A pure policy check at an AI input, model, operation, or output boundary."
  @callback check(value :: term(), context :: map()) ::
              :ok | {:error, term()} | {:interrupt, term()}

  @doc false
  def check(profile, stage, value, context, deadline) do
    Enum.reduce_while(profile.controls[stage], :ok, fn control, :ok ->
      {module, match} = control_spec(control)

      if matches?(value, match) do
        remaining = deadline - System.monotonic_time(:millisecond)

        result =
          if remaining > 0,
            do:
              Jido.Exec.run(
                Jido.AI.Runtime.CheckControl,
                %{module: module, stage: stage, value: value},
                context,
                timeout: remaining
              ),
            else: Jido.AI.Profile.error("controls.#{stage}", "AI request deadline reached")

        case result do
          {:ok, _} -> {:cont, :ok}
          {:error, _} = error -> {:halt, error}
          _ -> {:halt, Jido.AI.Profile.error("controls.#{stage}", "Invalid control result")}
        end
      else
        {:cont, :ok}
      end
    end)
  end

  defp control_spec(%{module: module, when: match}), do: {module, match}
  defp control_spec(module), do: {module, nil}

  defp matches?(_value, nil), do: true

  defp matches?(value, match) do
    metadata = stable_metadata(value)

    Enum.all?(match, fn {key, expected} ->
      actual =
        Enum.find_value(metadata, fn {actual_key, value} ->
          if comparable(actual_key) == comparable(key), do: value
        end)

      comparable(actual) == comparable(expected)
    end)
  end

  defp stable_metadata(%{tool: tool} = value) do
    kind =
      case Jido.Executable.resolve(tool.target) do
        {:ok, %{kind: kind}} -> kind
        _ -> nil
      end

    Map.merge(Map.get(tool, :metadata, %{}), %{kind: kind, name: value.name})
  end

  defp stable_metadata(value) when is_map(value), do: value
  defp stable_metadata(_value), do: %{}

  defp comparable(value) when is_atom(value), do: Atom.to_string(value)
  defp comparable(value), do: value
end

defmodule Jido.AI.Runtime.CheckControl do
  @moduledoc false
  use Jido.Action, name: "ai_check_control"
  @impl Jido.Action
  def run(params, context), do: Jido.AI.Error.capture(fn -> execute(params, context) end)

  defp execute(%{module: module, stage: stage, value: value}, context) do
    case module.check(value, context) do
      :ok -> {:ok, %{}}
      {:error, _} = error -> error
      {:interrupt, value} when stage == :operation -> {:error, {:interrupt, value}}
      _ -> Jido.AI.Profile.error("controls", "Invalid control result")
    end
  end
end

defmodule Jido.AI.Operations.Generate do
  @moduledoc "One provider request through ReqLLM. Core Exec owns its work lifetime."
  use Jido.Action, name: "ai_generate"

  @impl Jido.Action
  def run(params, context),
    do:
      Jido.AI.Error.capture(fn ->
        original = params.messages
        provider = Jido.AI.History.provider_context(original)

        Jido.AI.Quota.track(context, fn progress ->
          with {:ok, result} <- execute(%{params | messages: provider}, context, progress) do
            response = Jido.AI.History.restore_response_context(result.response, provider, original)
            {:ok, %{result | response: response}}
          end
        end)
      end)

  defp execute(
         %{stream: true, model: model, messages: messages, options: opts, schema: schema},
         context,
         progress
       ) do
    kind = if is_nil(schema), do: :stream, else: :stream_object

    with {:ok, stream} <- Jido.AI.Models.request(kind, model, messages, opts, schema) do
      try do
        callbacks = [
          on_chunk: fn chunk ->
            progress.(Map.get(chunk.metadata, :usage, %{}))
            Jido.AI.Session.activity(context)

            case Jido.AI.Turn.stream_content_part(chunk) do
              {:ok, part} -> delta(context, model, :content_part, part)
              :error -> :ok
            end
          end,
          on_result: fn text -> delta(context, model, :content, text) end,
          on_thinking: fn text -> delta(context, model, :thinking, text) end,
          on_tool_call: fn chunk -> delta(context, model, :tool_call, chunk.name) end
        ]

        with {:ok, response} <- Jido.AI.Usage.Stream.process(stream, callbacks),
             do: {:ok, %{response: Jido.AI.Runtime.Response.align_context(response)}}
      after
        ReqLLM.StreamResponse.close(stream)
      end
    end
  end

  defp execute(%{model: model, messages: messages, options: opts, schema: schema}, _, _progress) do
    kind = if is_nil(schema), do: :text, else: :object

    with {:ok, response} <- Jido.AI.Models.request(kind, model, messages, opts, schema),
         do: {:ok, %{response: Jido.AI.Runtime.Response.align_context(response)}}
  end

  defp delta(_, _, _, text) when text in [nil, ""], do: :ok

  defp delta(context, model, kind, text),
    do:
      Jido.AI.Session.emit(context, :llm_delta, %{
        chunk_type: kind,
        delta: text,
        model: Jido.AI.Models.model_label(model)
      })
end

defmodule Jido.AI.Runtime.Prepare do
  @moduledoc false
  use Jido.Action, name: "ai_prepare"
  alias Jido.AI.{Control, Models, Profile}

  @impl Jido.Action
  def run(params, context), do: Jido.AI.Error.capture(fn -> execute(params, context) end)

  defp execute(%{profile_id: id, query: query}, context) do
    with %Profile{} = profile <- get_in(context, [:jido_ai_profiles, id]),
         deadline = System.monotonic_time(:millisecond) + profile.controls.timeout,
         :ok <- Control.check(profile, :input, %{query: query}, context, deadline),
         {:ok, profile} <-
           Jido.AI.Instructions.resolve(profile, %{query: query}, context, deadline),
         {:ok, profile} <- Jido.AI.ModelRouter.select(profile, %{query: query}, context),
         {:ok, profile, adaptive} <- Jido.AI.Reasoning.select(profile, query),
         {:ok, output} <- Profile.output_contract(profile.result),
         {:ok, history} <- Jido.AI.History.read(context.agent_state, profile),
         {:ok, history_messages} <- Jido.AI.History.messages(history) do
      entry = profile.models[profile.reasoning.model]
      model = Models.resolve_model(entry.model)
      runtime_options = get_in(context, [:ai, id, :options]) || []

      options =
        Jido.AI.Reasoning.generation(profile, entry.generation)
        |> Jido.AI.Reasoning.ReAct.Config.merge_http_options(runtime_options[:req_http_options])
        |> Keyword.merge(Keyword.delete(runtime_options, :req_http_options))
        |> then(&Jido.AI.Reasoning.ReAct.Config.merge_model_opts([], &1, model))

      instructions =
        Jido.AI.Reasoning.instructions(profile, output)
        |> Enum.reject(&(&1 in [nil, ""]))
        |> Enum.join("\n\n")

      messages = if instructions == "", do: [], else: [ReqLLM.Context.system(instructions)]

      messages =
        messages ++
          history_messages ++
          [Jido.AI.History.bind_message(ReqLLM.Context.user(Jido.AI.Reasoning.query(profile, query)), context)]

      refs =
        case context[:jido_ai_request_record] do
          nil -> %{}
          record -> Jido.AI.History.refs(record, context.jido_ai_input_source)
        end

      state = %{
        profile: profile,
        effect_plan: Jido.AI.Effects.Candidate.new(context.agent_state),
        request_id: Jido.Signal.ID.generate!(),
        run_id: Jido.Signal.ID.generate!(),
        started_at_ms: System.system_time(:millisecond),
        model: model,
        options: options,
        messages: ReqLLM.Context.new(messages),
        output: output,
        iterations: 0,
        model_calls: 0,
        tool_calls: 0,
        repairs: 0,
        usage: %{},
        deadline: deadline,
        history_delta: Jido.AI.History.query(query, refs)
      }

      state = if adaptive, do: Map.put(state, :adaptive, adaptive), else: state

      with {:ok, state} <- Jido.AI.Reasoning.ReAct.Checkpoint.restore(state, context),
           {:ok, state} <- Jido.AI.Reasoning.prepare(state, query),
           :ok <- Jido.AI.Session.publish_selection(context, adaptive, deadline),
           do: {:ok, state}
    else
      {:error, _} = error -> error
      _ -> Profile.error("profile", "No trusted profile binding")
    end
  end
end

defmodule Jido.AI.Runtime.CallModel do
  @moduledoc false
  use Jido.Action, name: "ai_call_model"
  alias Jido.AI.{Control, Profile, ToolCatalog, Usage}

  @impl Jido.Action
  def run(params, context) do
    Jido.AI.Error.capture(fn ->
      position = Jido.AI.Reasoning.ReAct.Checkpoint.model_iteration(params)

      with :ok <- Jido.AI.Session.reasoning_iteration(context, position),
           :ok <- Jido.AI.Session.inspect_reasoning(context, Jido.AI.Reasoning.inspection(params)),
           do: execute(params, context)
    end)
  end

  defp execute(%{checkpoint_phase: :after_llm} = state, _),
    do: {:ok, Map.delete(state, :checkpoint_phase)}

  defp execute(%{checkpoint_phase: phase} = state, context)
       when phase in [:before_llm, :after_tools],
       do: execute(Map.delete(state, :checkpoint_phase), context)

  defp execute(state, context) do
    if state.profile.reasoning.method == :react && context[:jido_ai_legacy_iteration_result] &&
         state.repairs == 0 &&
         state.iterations >= state.profile.controls.max_iterations do
      {:ok,
       Map.merge(state, %{
         limit_result: "Maximum iterations reached without a final answer.",
         termination_reason: :max_iterations
       })}
    else
      case call(state, context) do
        {:error, reason} -> Jido.AI.Runtime.OutputState.fail(state, reason, context)
        result -> result
      end
    end
  end

  defp call(state, context) do
    remaining = state.deadline - System.monotonic_time(:millisecond)
    callback? = state.repairs > 0 && state.output.repair_fun != nil

    with true <- remaining > 0,
         true <- callback? or state.model_calls < state.profile.controls.max_model_calls,
         true <- state.repairs > 0 or state.iterations < state.profile.controls.max_iterations,
         {:ok, state} <- Jido.AI.Runtime.PendingInput.drain(state, context),
         state = Map.put(state, :llm_call_id, Jido.Signal.ID.generate!()),
         request = request(state, remaining),
         {:ok, request, active_tools} <-
           Jido.AI.Runtime.RequestTransform.prepare(state, request, context),
         :ok <- Control.check(state.profile, :model, request, context, state.deadline),
         remaining = state.deadline - System.monotonic_time(:millisecond),
         true <- remaining > 0,
         options = Keyword.update!(request.options, :receive_timeout, &min(&1, remaining)) do
      if callback?,
        do: repair_callback(state, %{request | options: options}, context),
        else: generate(state, %{request | options: options}, active_tools, context, remaining)
    else
      false -> Profile.error("controls", "AI request limit reached")
      error -> error
    end
  end

  defp generate(state, request, active_tools, context, remaining) do
    with :ok <-
           Jido.AI.Session.emit(
             context,
             :llm_started,
             Map.merge(
               %{
                 model_call: state.model_calls + 1,
                 call_id: state.llm_call_id,
                 model: Jido.AI.Models.model_label(request.model)
               },
               Jido.AI.Reasoning.event(state)
             )
           ),
         {:model_result, {:ok, %{response: response}}} <-
           {:model_result,
            Jido.Exec.run(
              Jido.AI.Operations.Generate,
              request,
              context
              |> Map.take([:jido_ai_events, :jido_ai_quota])
              |> Map.put(:jido_ai_quota_call_id, state.llm_call_id),
              timeout: remaining
            )},
         :ok <- Control.check(state.profile, :model, response, context, state.deadline),
         response = Jido.AI.History.bind_response(response, context),
         :ok <- Jido.AI.Session.account(context, response.usage),
         :ok <- terminal_response(response, request, state, context),
         {:ok, state} <-
           Jido.AI.History.record(state, Jido.AI.History.entries([response.message]), context),
         true <- System.monotonic_time(:millisecond) < state.deadline do
      event = Jido.AI.Runtime.Response.event(response, state, request)
      :ok = Jido.AI.Session.emit(context, :llm_completed, event)

      response_meta =
        Jido.AI.Request.Metadata.record_turn(Map.get(state, :response_meta, %{}), event)

      next =
        Map.merge(state, %{
          active_tools: active_tools,
          object_request: request.schema != nil,
          response: response,
          response_meta: response_meta,
          model_calls: state.model_calls + 1,
          iterations: state.iterations + if(state.repairs == 0, do: 1, else: 0),
          usage: Usage.merge(state.usage, response.usage)
        })

      Jido.AI.Reasoning.ReAct.Checkpoint.pause(next, :after_llm, context)
    else
      {:model_result, {:error, reason}} when state.repairs > 0 ->
        {:ok,
         state
         |> Map.put(:repair_result, {:error, Jido.AI.Error.for_storage(reason)})
         |> Map.update!(:model_calls, &(&1 + 1))}

      {:model_result, {:error, reason}} ->
        {:error, reason}

      false ->
        Profile.error("controls", "AI request deadline reached")

      error ->
        error
    end
  end

  defp repair_callback(state, request, context) do
    data = state.repair_data
    record = context[:jido_ai_request_record]

    callback_context =
      Map.merge(context, %{
        model: request.model,
        messages: Map.get(request, :public_messages, request.messages.messages),
        llm_opts: Keyword.drop(request.options, [:tools, :tool_choice]),
        user_message: data.user_message,
        request_id: if(record, do: record.id, else: state.request_id),
        run_id: if(record, do: record.run_id, else: state.run_id)
      })

    result = Jido.AI.Output.repair(state.output, data.raw, data.reason, callback_context)
    {:ok, Map.put(state, :repair_result, result)}
  end

  defp terminal_response(response, request, state, context) do
    visible = response |> Jido.AI.Turn.from_response() |> Jido.AI.Turn.result()

    result =
      cond do
        ReqLLM.Response.tool_calls(response) != [] or visible != "" or
            not is_nil(response.object) ->
          :ok

        request.schema == nil and response.finish_reason in [:tool_calls, "tool_calls"] ->
          # A provider can discard an incomplete or unnamed tool call during
          # assembly. An empty declared tool round is not a final answer.
          {:error, {:incomplete_response, :tool_calls}}

        response.finish_reason in [nil, :stop, :tool_calls, "stop", "tool_calls", "completed"] ->
          :ok

        true ->
          {:error, {:incomplete_response, response.finish_reason}}
      end

    case result do
      {:error, reason} ->
        :ok = Jido.AI.Session.failure_type(context, :llm_response)

        received =
          state
          |> Map.put(:response, response)
          |> Map.put(:usage, Usage.merge(state.usage, response.usage))

        {:error, Jido.AI.Reasoning.failure(received, reason)}

      other ->
        other
    end
  end

  defp request(state, remaining) do
    tools = Jido.AI.Reasoning.tools(state)

    options =
      state.options
      |> Keyword.put(
        :receive_timeout,
        min(remaining, Keyword.get(state.options, :receive_timeout, remaining))
      )

    options =
      if tools == [],
        do: Keyword.delete(options, :tools),
        else: Keyword.put(options, :tools, ToolCatalog.definitions(tools))

    options =
      if Jido.AI.Reasoning.tools_disabled?(state),
        do: Keyword.delete(options, :tool_choice),
        else: options

    # Tool-capable rounds request JSON by instruction. A repair has no tools and
    # uses the provider's object contract. Both paths use the same validator.
    schema =
      if tools == [],
        do: Jido.AI.Reasoning.provider_schema(state.profile, state.output),
        else: nil

    options =
      if state.repairs > 0,
        do: options |> Keyword.drop([:tools, :tool_choice]) |> Keyword.put(:stream, false),
        else: options

    request = %{
      model: state.model,
      messages: state.messages,
      options: options,
      schema: schema,
      stream: state.repairs == 0 and state.profile.requests.streaming
    }

    if state.repairs > 0,
      do: Map.put(request, :public_messages, state.repair_data.messages),
      else: request
  end
end

defmodule Jido.AI.Runtime.Decide do
  @moduledoc false
  use Jido.Action, name: "ai_decide"
  alias Jido.AI.{Control, Output, Profile, ToolCatalog}

  @impl Jido.Action
  def run(params, context), do: Jido.AI.Error.capture(fn -> execute(params, context) end)

  defp execute(%{repair_result: {:ok, answer}} = state, context),
    do: finish_output(Map.delete(state, :repair_result), context, answer)

  defp execute(%{repair_result: {:error, reason}} = state, context),
    do: repair(Map.delete(state, :repair_result), reason, context)

  defp execute(%{limit_result: text} = state, context) do
    with :ok <- Jido.AI.Runtime.PendingInput.seal(context),
         do: finish_output(state, context, text)
  end

  defp execute(state, context) do
    calls = ReqLLM.Response.tool_calls(state.response)

    cond do
      calls == [] or Map.get(state, :object_request, false) ->
        case Jido.AI.Reasoning.advance(state) do
          {:continue, next} ->
            {:continue, next, Jido.AI.Runtime.ReasonFlow}

          {:done, next} ->
            with :ok <- Jido.AI.Session.inspect_reasoning(context, Jido.AI.Reasoning.inspection(next)),
                 do: finish(next, context)

          {:error, reason} ->
            Jido.AI.Runtime.OutputState.fail(state, reason, context)
        end

      Jido.AI.Reasoning.single_pass?(state.profile.reasoning.method) ->
        Jido.AI.Runtime.OutputState.fail(
          state,
          {:unexpected_tool_calls, state.profile.reasoning.method},
          context
        )

      true ->
        tools(state, calls, context)
    end
  end

  defp tools(state, calls, context) do
    with true <- state.repairs == 0,
         {:ok, state} <- Jido.AI.Reasoning.tool_round(state),
         true <- state.tool_calls + length(calls) <= state.profile.controls.max_tool_calls,
         {:ok, batch} <-
           ToolCatalog.admit(
             Map.get(state, :active_tools, state.profile.tools),
             calls,
             &Jido.AI.Runtime.ToolInterception.before(&1, state, context)
           ),
         :ok <-
           Jido.AI.Runtime.Preflight.check(
             state.profile,
             batch,
             Jido.AI.Runtime.ToolInterception.context(state, context),
             state.deadline
           ),
         true <- System.monotonic_time(:millisecond) < state.deadline do
      batch =
        Enum.with_index(batch, state.tool_calls)
        |> Enum.map(fn {call, index} ->
          Map.merge(call, %{
            deadline: state.deadline,
            position: index,
            agent_state: state.effect_plan.state,
            profile: state.profile,
            interceptor: Jido.AI.Runtime.ToolInterception.module(state.profile, context),
            runtime_identity: Jido.AI.Runtime.ToolInterception.identity(state, context),
            effect_policy: Jido.AI.Runtime.ToolInterception.policy(state.profile)
          })
        end)

      [first | pending] = Enum.chunk_every(batch, state.profile.reasoning.tool_concurrency)

      {:continue,
       Map.merge(state, %{
         batch: first,
         pending_batches: pending,
         tool_results: [],
         tool_calls: state.tool_calls + length(batch)
       }), Jido.AI.Runtime.ToolsFlow}
    else
      false ->
        {:error, reason} = Profile.error("controls", "AI tool limit reached")
        {:error, Jido.AI.Reasoning.failure(state, reason)}

      {:error, reason} ->
        {:error, Jido.AI.Reasoning.failure(state, reason)}
    end
  end

  defp finish(state, context) do
    case Jido.AI.Runtime.PendingInput.seal_if_empty(context) do
      :sealed ->
        finish_output(state, context)

      :pending ->
        with {:ok, state} <-
               Jido.AI.Runtime.PendingInput.drain(
                 %{state | messages: state.response.context},
                 context
               ),
             do: {:continue, state, Jido.AI.Runtime.ReasonFlow}

      {:error, reason} ->
        {:error, {:pending_input_server, reason}}
    end
  end

  defp finish_output(state, context) do
    finish_output(state, context, state.response)
  end

  defp finish_output(state, context, value) do
    state = Jido.AI.Runtime.OutputState.start(state, value, context)

    case Jido.AI.Reasoning.parse(state, value) do
      {:ok, answer, method_meta} ->
        state = Jido.AI.Runtime.OutputState.validated(state, answer, context)

        with :ok <- Control.check(state.profile, :output, answer, context, state.deadline),
             true <- System.monotonic_time(:millisecond) < state.deadline do
          meta =
            Map.merge(
              Map.get(state, :response_meta, %{}),
              Map.take(state, [:usage, :model_calls, :tool_calls, :termination_reason])
            )
            |> Map.merge(Map.get(state, :tool_meta, %{}))
            |> Map.merge(method_meta)
            |> Map.put_new(:termination_reason, :final_answer)
            |> Map.put(
              :reasoning_iteration,
              Jido.AI.Reasoning.ReAct.Checkpoint.iteration(%{runtime: state, phase: :terminal})
            )

          meta = if state.output, do: Map.put(meta, :output, state.output_meta), else: meta

          with {:ok, meta} <- Jido.AI.Reasoning.ReAct.Checkpoint.terminal(state, meta, context) do
            content = Jido.AI.Runtime.OutputState.content(value)

            {:ok,
             %{
               result: answer,
               content: content,
               value: if(state.output, do: answer, else: nil),
               meta: meta,
               effect_plan: state.effect_plan,
               history_delta: state.history_delta
             }}
          end
        else
          false ->
            {:error, reason} = Profile.error("controls", "AI request deadline reached")
            Jido.AI.Runtime.OutputState.fail(state, reason, context)

          {:error, reason} ->
            Jido.AI.Runtime.OutputState.fail(state, reason, context)
        end

      {:method_error, reason} ->
        Jido.AI.Runtime.OutputState.fail(state, reason, context)

      {:error, reason} ->
        repair(state, reason, context)
    end
  end

  defp repair(state, reason, context) do
    if state.output.on_validation_error == :repair &&
         state.repairs < state.profile.result.max_repairs do
      state = Jido.AI.Runtime.OutputState.repair(state, reason, context)
      raw = state.output_raw

      view = Jido.AI.Runtime.RequestTransform.state_view(state, context)

      user_message =
        Map.get(state, :repair_data, %{})[:user_message] ||
          Jido.AI.Runtime.RequestTransform.latest_query(view.context)

      conversation =
        Map.get(state, :repair_data, %{})[:conversation] ||
          if(Map.has_key?(state, :limit_result), do: state.messages, else: state.response.context)

      original =
        Map.get(state, :repair_data, %{})[:original] ||
          Map.take(state, [:llm_call_id, :response, :active_tools])

      request =
        Output.repair_request(raw, reason, %{
          model: state.model,
          llm_opts: state.options,
          user_message: user_message
        })

      {:ok, messages} = ReqLLM.Context.normalize(request.messages)

      next =
        state
        |> Map.delete(:limit_result)
        |> Map.put(:messages, messages)
        |> Map.put(:repairs, state.repairs + 1)
        |> Map.put(:repair_data, %{
          raw: raw,
          reason: reason,
          user_message: user_message,
          messages: request.messages,
          conversation: conversation,
          original: original
        })

      {:continue, next, Jido.AI.Runtime.ReasonFlow}
    else
      Jido.AI.Runtime.OutputState.fail(state, reason, context)
    end
  end
end

defmodule Jido.AI.Runtime.ExecuteTool do
  @moduledoc false
  use Jido.Action, name: "ai_execute_tool"

  @impl Jido.Action
  def run(call, context) do
    :ok =
      Jido.AI.Session.emit(context, :tool_started, %{
        tool_call_id: call.id,
        tool_name: call.name,
        arguments: call.prepared_arguments
      })

    remaining = max(call.deadline - System.monotonic_time(:millisecond), 0)

    try do
      Jido.Exec.run(
        Jido.AI.Runtime.ToolAttempt,
        Map.merge(call, %{attempt: 1, started_at: System.monotonic_time(:millisecond)}),
        context,
        timeout: remaining
      )
    after
      Jido.AI.Session.activity(context, {:tool_finished, call.id})
    end
  end
end

defmodule Jido.AI.Runtime.ToolAttempt do
  @moduledoc false
  use Jido.Action, name: "ai_tool_attempt"

  @impl Jido.Action
  def run(call, context) do
    remaining = call.deadline - System.monotonic_time(:millisecond)

    if remaining > 0 do
      context =
        context
        |> Map.merge(call.runtime_identity)
        |> Map.put(:agent_state, call.agent_state)
        |> Map.put(:state, call.agent_state)

      tool_context = forward_context(context, call.tool.forward_context)

      tool_context = Map.merge(tool_context, Map.take(context, [:jido_ai_quota]))

      result =
        Jido.Exec.run(call.tool.target, call.arguments, tool_context, timeout: min(remaining, call.tool.timeout))
        |> Jido.AI.ToolResult.normalize(call)

      with :ok <-
             Jido.AI.Control.check(
               call.profile,
               :operation,
               Map.put(call, :result, result),
               context,
               call.deadline
             ) do
        delay = Map.get(call.tool, :retry_backoff, 0)

        if Jido.AI.Error.retryable?(result) and elem(result, 2) == [] and
             call.attempt <= Map.get(call.tool, :max_retries, 0) and
             System.monotonic_time(:millisecond) + delay < call.deadline do
          Process.sleep(delay)
          {:continue, %{call | attempt: call.attempt + 1}, __MODULE__}
        else
          duration = System.monotonic_time(:millisecond) - call.started_at

          if call.interceptor,
            do: {:ok, %{call: call, raw: result, attempts: call.attempt, duration: duration}},
            else: Jido.AI.Runtime.ToolInterception.finish(call, result, call.attempt, duration, context)
        end
      end
    else
      Jido.AI.Profile.error("controls", "AI request deadline reached")
    end
  end

  defp forward_context(context, :all), do: context
  defp forward_context(_context, :none), do: %{}
  defp forward_context(context, :public), do: Jido.AI.ToolContext.runtime(context)

  defp forward_context(context, {:only, fields}),
    do: context |> Jido.AI.ToolContext.runtime() |> Map.take(fields)

  defp forward_context(context, {:except, fields}),
    do: context |> Jido.AI.ToolContext.runtime() |> Map.drop(fields)

  defp forward_context(context, fields) when is_list(fields), do: Map.take(context, fields)
end

defmodule Jido.AI.Runtime.Continue do
  @moduledoc false
  use Jido.Action, name: "ai_continue"

  @impl Jido.Action
  def run(params, context), do: Jido.AI.Error.capture(fn -> execute(params, context) end)

  defp execute(%{state: state, results: [%{call: _} | _] = results}, _),
    do: {:ok, %{state | tool_results: state.tool_results ++ results}}

  defp execute(%{state: state, results: results}, context),
    do: apply_results(state, results, context)

  @doc false
  def apply_results(state, results, context) do
    with {:ok, plan} <-
           Enum.reduce_while(results, {:ok, state.effect_plan}, fn result, {:ok, plan} ->
             case Jido.AI.Effects.Candidate.stage(
                    plan,
                    result.agent_state,
                    elem(result.result, 2),
                    context.jido_ai_agent
                  ) do
               {:ok, next} -> {:cont, {:ok, next}}
               error -> {:halt, error}
             end
           end) do
      meta =
        Enum.reduce(
          results,
          Map.get(state, :tool_meta, %{}),
          &Jido.AI.ToolResult.record(&2, &1.completed)
        )

      {:ok,
       state
       |> Map.put(:tool_results, state.tool_results ++ results)
       |> Map.put(:tool_meta, meta)
       |> Map.put(:effect_plan, plan)}
    end
  end
end

defmodule Jido.AI.Runtime.NextBatch do
  @moduledoc false
  use Jido.Action, name: "ai_next_batch"

  @impl Jido.Action
  def run(state, context), do: Jido.AI.Error.capture(fn -> execute(state, context) end)

  defp execute(%{pending_batches: [batch | rest]} = state, _) do
    {:continue, %{state | batch: batch, pending_batches: rest}, Jido.AI.Runtime.ToolsFlow}
  end

  defp execute(state, context) do
    with {:ok, state} <- Jido.AI.Runtime.ToolInterception.finish_all(state, context),
         results =
           Enum.map(state.tool_results, fn result ->
             ReqLLM.Context.tool_result(result.id, result.name, result.content)
             |> Jido.AI.History.bind_message(context, Map.get(result, :refs, %{}))
           end),
         {:ok, messages} <-
           ReqLLM.Context.append_tool_exchange(state.response.context, state.response, results),
         entries =
           Enum.zip_with(Jido.AI.History.entries(results), state.tool_results, fn entry, result ->
             Map.put(entry, :refs, Map.get(result, :refs, %{}))
           end),
         {:ok, state} <- Jido.AI.History.record(state, entries, context),
         {:ok, state} <- Jido.AI.Runtime.ToolCycle.record(%{state | messages: messages}, context),
         {:ok, state} <- Jido.AI.Reasoning.ReAct.Checkpoint.consume_queries(state, context),
         {:ok, state} <-
           Jido.AI.Reasoning.ReAct.Checkpoint.pause(
             state,
             :after_tools,
             context
           ) do
      {:continue, state, Jido.AI.Runtime.ReasonFlow}
    else
      {:error, reason} -> Jido.AI.Runtime.OutputState.fail(state, reason, context)
    end
  end
end

defmodule Jido.AI.Runtime.ToolsFlow do
  @moduledoc false
  use Jido.Flow, name: "ai_tools"

  flow do
    map("tools", collection: input(:batch), action: Jido.AI.Runtime.ExecuteTool, params: item())

    dispatch("continue",
      decision: Jido.AI.Runtime.Continue,
      expander: Jido.AI.Runtime.NextBatch,
      params: %{state: input(), results: result("tools")}
    )

    output(result("continue"))
  end
end

defmodule Jido.AI.Runtime.ReasonFlow do
  @moduledoc false
  use Jido.Flow, name: "ai_reason"

  flow do
    dispatch("reason",
      decision: Jido.AI.Runtime.CallModel,
      expander: Jido.AI.Runtime.Decide,
      params: input()
    )

    output(result("reason"))
  end
end
