defmodule Jido.AI.Request do
  @moduledoc """
  A prepared AI request that can be inspected before execution.

  Preparation resolves the model, context, visible tools, output contract, and
  limits. It does not run controls, tools, or a model. Execution uses this same
  value and adds only the active deadline and executable tool callbacks.
  """

  alias Jido.AI.{Context, Controls, Deadline, Models, Plugin, ToolAdapter}
  alias Jido.AI.Reasoning.State
  alias Jido.{Session, Signal, Thread}

  @enforce_keys [
    :request_id,
    :run_id,
    :input,
    :model,
    :reasoning,
    :controls,
    :context,
    :tools,
    :tool_specs,
    :request_options
  ]
  defstruct [
    :request_id,
    :run_id,
    :input,
    :model,
    :reasoning,
    :controls,
    :context,
    :output_descriptor,
    tools: [],
    tool_specs: [],
    request_options: []
  ]

  @type t :: %__MODULE__{
          request_id: String.t(),
          run_id: String.t(),
          input: String.t(),
          model: String.t(),
          reasoning: module(),
          controls: map(),
          context: ReqLLM.Context.t(),
          output_descriptor: ReqLLM.Output.t() | nil,
          tools: [ReqLLM.Tool.t()],
          tool_specs: [ToolAdapter.tool_spec()],
          request_options: keyword()
        }

  @type runtime_options :: %{
          context: ReqLLM.Context.t() | Session.t() | Thread.t() | nil,
          projection: keyword() | nil,
          visible_tools: [atom() | String.t()] | nil,
          request_id: String.t() | nil,
          run_id: String.t() | nil,
          jido_context: map(),
          request_options: keyword()
        }

  @doc false
  @spec prepare(map(), String.t(), runtime_options(), module() | nil) ::
          {:ok, t()} | {:error, term()}
  def prepare(ai_config, input, runtime, reply) do
    controls = Map.get(ai_config, :controls, Plugin.default_controls())
    declared_specs = Map.get(ai_config, :tools, [])

    with {:ok, model} <- Models.resolve(ai_config.model),
         {:ok, tool_specs} <- visible_tool_specs(declared_specs, runtime.visible_tools),
         {:ok, tools} <- ToolAdapter.definitions_from_specs(tool_specs),
         {:ok, output_descriptor} <- output_descriptor(reply, runtime.request_options),
         {:ok, projected} <- project_context(runtime.context, runtime.projection) do
      context = context(ai_config.instructions, projected, input)
      request_options = prepared_options(runtime.request_options, tools, output_descriptor)

      {:ok,
       %__MODULE__{
         request_id: runtime.request_id || Signal.ID.generate!(),
         run_id: runtime.run_id || Signal.ID.generate!(),
         input: input,
         model: model,
         reasoning: Map.get(ai_config, :reasoning, Plugin.default_reasoning()),
         controls: controls,
         context: context,
         tools: tools,
         tool_specs: tool_specs,
         request_options: request_options,
         output_descriptor: output_descriptor
       }}
    end
  end

  @doc false
  @spec start(t()) :: State.t()
  def start(%__MODULE__{} = request) do
    deadline = Deadline.new(request.controls.timeout)

    state =
      State.new(%{
        request_id: request.request_id,
        run_id: request.run_id,
        input: request.input,
        reasoning: request.reasoning,
        controls: request.controls,
        private: %{
          model: request.model,
          conversation: request.context,
          tools: request.tools,
          tool_specs: request.tool_specs,
          request_options: request.request_options,
          output_descriptor: request.output_descriptor,
          deadline: deadline,
          response: nil
        }
      })

    State.trace(state, :request_started, started_event_data(request))
  end

  @doc false
  @spec started_event_data(t()) :: map()
  def started_event_data(%__MODULE__{} = request) do
    %{
      model: request.model,
      reasoning: inspect(request.reasoning),
      visible_tools: visible_tool_names(request),
      tool_count: length(request.tools)
    }
  end

  @doc "Returns the names of tools visible to this request."
  @spec visible_tool_names(t()) :: [String.t()]
  def visible_tool_names(%__MODULE__{tool_specs: specs}), do: Enum.map(specs, & &1.name)

  @doc "Returns the prepared model messages."
  @spec messages(t()) :: [ReqLLM.Message.t()]
  def messages(%__MODULE__{context: context}), do: ReqLLM.Context.to_list(context)

  @spec stream(map(), String.t(), runtime_options()) ::
          {:ok, ReqLLM.StreamResponse.t()} | {:error, term()}
  def stream(ai_config, input, runtime) do
    with {:ok, request} <- prepare(ai_config, input, runtime, nil),
         :ok <- validate_stream_controls(request.controls),
         deadline = Deadline.new(request.controls.timeout),
         :ok <-
           run_controls(
             request.controls.input,
             :input,
             input,
             runtime.jido_context,
             deadline
           ),
         {:ok, tools} <-
           ToolAdapter.from_specs(request.tool_specs, runtime.jido_context, deadline: deadline),
         {:ok, request_opts} <-
           request_options(tools, request.request_options, deadline) do
      ReqLLM.stream_text(request.model, request.context, request_opts)
    end
  end

  @doc false
  @spec options(term()) :: {:ok, runtime_options()} | {:error, {:invalid_options, term()}}
  def options(opts) when is_list(opts) do
    original = opts

    if Keyword.keyword?(opts) and not Keyword.has_key?(opts, :tools) do
      {jido_context, opts} = Keyword.pop(opts, :jido_context, %{})
      {legacy_context, opts} = Keyword.pop(opts, :conversation)
      {context, opts} = Keyword.pop(opts, :context)
      {projection, opts} = Keyword.pop(opts, :projection)
      {visible_tools, opts} = Keyword.pop(opts, :visible_tools)
      {request_id, opts} = Keyword.pop(opts, :request_id)
      {run_id, request_options} = Keyword.pop(opts, :run_id)
      duplicate_context? = not is_nil(context) and not is_nil(legacy_context)
      context = context || legacy_context

      if is_map(jido_context) and not duplicate_context? and valid_context_source?(context) and
           valid_projection?(context, projection) and valid_visible_tools?(visible_tools) and
           valid_id?(request_id) and valid_id?(run_id) do
        {:ok,
         %{
           context: context,
           projection: projection,
           visible_tools: visible_tools,
           request_id: request_id,
           run_id: run_id,
           jido_context: jido_context,
           request_options: request_options
         }}
      else
        {:error, {:invalid_options, original}}
      end
    else
      {:error, {:invalid_options, original}}
    end
  end

  def options(opts), do: {:error, {:invalid_options, opts}}

  @doc false
  def response_output(%ReqLLM.Response{} = response, nil) do
    case ReqLLM.Response.text(response) do
      text when is_binary(text) -> {:ok, text}
      _other -> {:error, :missing_output}
    end
  end

  def response_output(%ReqLLM.Response{} = response, %ReqLLM.Output{} = descriptor) do
    case ReqLLM.Response.output(response, descriptor) do
      nil -> {:error, :missing_output}
      output -> normalize_output(output, descriptor)
    end
  end

  def response_output(_response, _descriptor), do: {:error, :missing_output}

  defp normalize_output(output, %ReqLLM.Output{type: :object, schema: %_{} = schema}) do
    Zoi.parse(schema, output, coerce: true)
  end

  defp normalize_output(output, %ReqLLM.Output{type: :array, element: %_{} = schema}) do
    schema
    |> Zoi.list()
    |> Zoi.parse(output, coerce: true)
  end

  defp normalize_output(output, _descriptor), do: {:ok, output}

  defp visible_tool_specs(specs, nil), do: {:ok, specs}

  defp visible_tool_specs(specs, requested) when is_list(requested) do
    names = Enum.map(requested, &tool_name/1)
    declared = MapSet.new(specs, & &1.name)
    unknown = Enum.reject(names, &MapSet.member?(declared, &1))

    if unknown == [] do
      selected = MapSet.new(names)
      {:ok, Enum.filter(specs, &MapSet.member?(selected, &1.name))}
    else
      {:error, {:unknown_tools, unknown}}
    end
  end

  defp tool_name(name) when is_atom(name), do: Atom.to_string(name)
  defp tool_name(name), do: name

  defp project_context(nil, nil), do: {:ok, nil}
  defp project_context(%ReqLLM.Context{} = context, nil), do: {:ok, context}

  defp project_context(source, projection) when is_list(projection) do
    with {:ok, signal_action, fields} <- projection_options(projection),
         do: Context.project(source, signal_action, fields)
  end

  defp project_context(_source, _projection), do: {:error, :invalid_context_projection}

  defp projection_options(projection) do
    expected = [:input, :output, :signal_action]

    if Keyword.keyword?(projection) and Enum.sort(Keyword.keys(projection)) == expected do
      signal_action = Keyword.fetch!(projection, :signal_action)
      fields = Keyword.take(projection, [:input, :output])
      {:ok, signal_action, fields}
    else
      {:error, :invalid_context_projection}
    end
  end

  defp context(instructions, projected, input) do
    messages =
      case projected do
        %ReqLLM.Context{} -> ReqLLM.Context.to_list(projected)
        nil -> []
      end

    messages =
      case instructions do
        "" -> messages
        instructions -> [ReqLLM.Context.system(instructions) | messages]
      end

    ReqLLM.Context.new(messages ++ [ReqLLM.Context.user(input)])
  end

  defp prepared_options(opts, tools, output_descriptor) do
    opts
    |> Keyword.delete(:output)
    |> Keyword.delete(:tools)
    |> put_tools(tools)
    |> maybe_put_output(output_descriptor)
  end

  defp validate_stream_controls(%{output: nil}), do: :ok

  defp validate_stream_controls(_controls),
    do: {:error, :output_control_requires_buffered_response}

  defp run_controls(action, stage, value, context, deadline) do
    with {:ok, timeout} <- Deadline.remaining(deadline) do
      Controls.run(action, stage, value, context, timeout: timeout)
    end
  end

  defp request_options(tools, opts, deadline) do
    opts = opts |> Keyword.delete(:tools) |> put_tools(tools)

    configured_timeout =
      case Keyword.get(opts, :receive_timeout) do
        timeout when is_integer(timeout) and timeout > 0 -> timeout
        _other -> deadline.timeout
      end

    with {:ok, timeout} <- Deadline.cap(deadline, configured_timeout) do
      {:ok, Keyword.put(opts, :receive_timeout, timeout)}
    end
  end

  defp put_tools(opts, []), do: Keyword.delete(opts, :tools)
  defp put_tools(opts, tools), do: Keyword.put(opts, :tools, tools)

  defp maybe_put_output(opts, nil), do: Keyword.delete(opts, :output)
  defp maybe_put_output(opts, output), do: Keyword.put(opts, :output, output)

  defp output_descriptor(nil, opts), do: {:ok, Keyword.get(opts, :output)}

  defp output_descriptor(module, _opts)
       when is_atom(module) and module not in [nil, true, false] do
    if Jido.SignalAction.defined?(module) do
      case module.__signal_action__().output do
        %{schema: schema} -> {:ok, ReqLLM.Output.object(schema)}
        _other -> {:error, :invalid_reply_contract}
      end
    else
      {:error, :invalid_reply_contract}
    end
  end

  defp output_descriptor(_reply, _opts), do: {:error, :invalid_reply_contract}

  defp valid_context_source?(nil), do: true
  defp valid_context_source?(%ReqLLM.Context{} = context), do: valid_conversation?(context)
  defp valid_context_source?(%Session{} = session), do: Session.validate(session) == :ok
  defp valid_context_source?(%Thread{} = thread), do: Thread.validate(thread) == :ok
  defp valid_context_source?(_context), do: false

  defp valid_projection?(%ReqLLM.Context{}, nil), do: true
  defp valid_projection?(nil, nil), do: true

  defp valid_projection?(source, projection)
       when is_struct(source, Session) or is_struct(source, Thread),
       do: is_list(projection) and Keyword.keyword?(projection)

  defp valid_projection?(_source, _projection), do: false

  defp valid_visible_tools?(nil), do: true

  defp valid_visible_tools?(tools) when is_list(tools) do
    names = Enum.map(tools, &tool_name/1)

    Enum.all?(names, &(is_binary(&1) and byte_size(&1) > 0)) and
      length(names) == length(Enum.uniq(names))
  end

  defp valid_visible_tools?(_tools), do: false

  defp valid_id?(nil), do: true
  defp valid_id?(id), do: is_binary(id) and byte_size(id) > 0

  defp valid_conversation?(%ReqLLM.Context{tools: []} = conversation) do
    with {:ok, _conversation} <- ReqLLM.Context.validate(conversation) do
      Enum.all?(conversation.messages, &conversation_message?/1)
    else
      {:error, _reason} -> false
    end
  end

  defp valid_conversation?(_conversation), do: false

  defp conversation_message?(%ReqLLM.Message{
         role: role,
         tool_calls: tool_calls,
         reasoning_details: reasoning_details,
         metadata: metadata
       }) do
    role in [:user, :assistant] and
      tool_calls in [nil, []] and
      reasoning_details in [nil, []] and
      metadata == %{}
  end

  defp conversation_message?(_message), do: false
end
