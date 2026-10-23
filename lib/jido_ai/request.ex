defmodule Jido.AI.Request do
  @moduledoc false

  alias Jido.AI.{Controls, Deadline, Models, Plugin, ToolAdapter}
  alias Jido.AI.Reasoning.State

  @type runtime_options :: %{
          conversation: ReqLLM.Context.t() | nil,
          jido_context: map(),
          request_options: keyword()
        }

  @doc false
  @spec prepare(map(), String.t(), runtime_options(), module() | nil) ::
          {:ok, State.t()} | {:error, term()}
  def prepare(ai_config, input, runtime, reply) do
    controls = Map.get(ai_config, :controls, Plugin.default_controls())

    with {:ok, model} <- Models.resolve(ai_config.model),
         deadline = Deadline.new(controls.timeout),
         {:ok, tools} <- tool_definitions(ai_config),
         {:ok, output_descriptor} <- output_descriptor(reply, runtime.request_options) do
      request_options =
        runtime.request_options
        |> Keyword.delete(:output)
        |> put_tools(tools)
        |> maybe_put_output(output_descriptor)

      reasoning = Map.get(ai_config, :reasoning, Plugin.default_reasoning())

      state =
        State.new(%{
          input: input,
          reasoning: reasoning,
          controls: controls,
          private: %{
            model: model,
            conversation: context(ai_config.instructions, runtime.conversation, input),
            tools: tools,
            tool_specs: Map.get(ai_config, :tools, []),
            request_options: request_options,
            output_descriptor: output_descriptor,
            deadline: deadline,
            response: nil
          }
        })

      {:ok,
       State.trace(state, %{
         type: :request_started,
         model: model,
         reasoning: inspect(reasoning),
         tool_count: length(tools)
       })}
    end
  end

  @spec stream(map(), String.t(), runtime_options()) ::
          {:ok, ReqLLM.StreamResponse.t()} | {:error, term()}
  def stream(ai_config, input, runtime) do
    controls = Map.get(ai_config, :controls, Plugin.default_controls())

    with :ok <- validate_stream_controls(controls),
         {:ok, model} <- Models.resolve(ai_config.model),
         deadline = Deadline.new(controls.timeout),
         :ok <- run_controls(controls.input, :input, input, runtime.jido_context, deadline),
         {:ok, tools} <- executable_tools(ai_config, runtime.jido_context, deadline),
         context = context(ai_config.instructions, runtime.conversation, input),
         {:ok, request_opts} <-
           request_options(tools, runtime.request_options, deadline) do
      ReqLLM.stream_text(model, context, request_opts)
    end
  end

  @doc false
  @spec options(term()) :: {:ok, runtime_options()} | {:error, {:invalid_options, term()}}
  def options(opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      {jido_context, request_options} = Keyword.pop(opts, :jido_context, %{})
      {conversation, request_options} = Keyword.pop(request_options, :conversation)

      if is_map(jido_context) and valid_conversation?(conversation) do
        {:ok,
         %{
           conversation: conversation,
           jido_context: jido_context,
           request_options: request_options
         }}
      else
        {:error, {:invalid_options, opts}}
      end
    else
      {:error, {:invalid_options, opts}}
    end
  end

  def options(opts), do: {:error, {:invalid_options, opts}}

  defp tool_definitions(ai_config) do
    ToolAdapter.definitions_from_specs(Map.get(ai_config, :tools, []))
  end

  defp executable_tools(ai_config, jido_context, deadline) do
    ToolAdapter.from_specs(
      Map.get(ai_config, :tools, []),
      jido_context,
      deadline: deadline
    )
  end

  defp context(instructions, conversation, input) do
    messages =
      case conversation do
        %ReqLLM.Context{} -> ReqLLM.Context.to_list(conversation)
        nil -> []
      end

    messages =
      case instructions do
        "" -> messages
        instructions -> [ReqLLM.Context.system(instructions) | messages]
      end

    ReqLLM.Context.new(messages ++ [ReqLLM.Context.user(input)])
  end

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

  defp validate_stream_controls(%{output: []}), do: :ok

  defp validate_stream_controls(_controls),
    do: {:error, :output_control_requires_buffered_response}

  defp run_controls(actions, stage, value, context, deadline) do
    with {:ok, timeout} <- Deadline.remaining(deadline) do
      Controls.run(actions, stage, value, context, timeout: timeout)
    end
  end

  defp request_options(tools, opts, deadline) do
    opts = put_tools(opts, tools)

    configured_timeout =
      case Keyword.get(opts, :receive_timeout) do
        timeout when is_integer(timeout) and timeout > 0 -> timeout
        _other -> deadline.timeout
      end

    with {:ok, timeout} <- Deadline.cap(deadline, configured_timeout) do
      {:ok, Keyword.put(opts, :receive_timeout, timeout)}
    end
  end

  defp put_tools(opts, []), do: opts
  defp put_tools(opts, tools), do: Keyword.put(opts, :tools, tools)

  defp maybe_put_output(opts, nil), do: opts
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

  defp valid_conversation?(nil), do: true

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
