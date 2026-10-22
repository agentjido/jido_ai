defmodule Jido.AI do
  @moduledoc """
  AI extensions for Jido.

  Use `Jido.AI.Agent` to define an Agent with the AI Plugin included.
  """

  alias Jido.AI.{Controls, Models, Plugin, ToolAdapter}

  @type generate_error ::
          Models.error_reason()
          | :empty_input
          | :invalid_reply_contract
          | :missing_ai_config
          | :missing_output
          | :output_control_requires_buffered_response
          | {:invalid_input, term()}
          | {:invalid_model_response, :mixed_structured_output_and_tool_calls}
          | {:invalid_options, term()}
          | {:limit_exceeded, :max_iterations | :max_model_calls | :max_tool_calls}
          | {:request_timeout, pos_integer()}
          | term()

  @doc "Generates one response from an AI Agent definition or instance."
  @spec generate(module() | Jido.Agent.t(), String.t(), keyword()) ::
          {:ok, term()} | {:error, generate_error()}
  def generate(agent, input, opts \\ [])

  def generate(agent, input, opts) when is_binary(input) and byte_size(input) > 0 do
    with {:ok, ai_config} <- ai_config(agent) do
      generate_with(ai_config, input, opts)
    end
  end

  def generate(_agent, "", _opts), do: {:error, :empty_input}
  def generate(_agent, input, _opts) when not is_binary(input), do: {:error, {:invalid_input, input}}
  def generate(_agent, _input, opts), do: {:error, {:invalid_options, opts}}

  @doc """
  Generates reply data inside a routed Jido Action.

  The required `:reply` option is a `Jido.SignalAction` with an output Signal.
  Its output schema shapes the model result. This function returns the reply
  data. The route Action stays responsible for calling `reply/3` and emitting
  the resulting Signal.
  """
  @spec respond(map(), String.t(), keyword()) ::
          {:ok, map()} | {:error, generate_error()}
  def respond(context, input, opts \\ [])

  def respond(context, input, opts)
      when is_map(context) and is_binary(input) and byte_size(input) > 0 and is_list(opts) do
    if Keyword.keyword?(opts) do
      {reply, request_opts} = Keyword.pop(opts, :reply)

      with {:ok, ai_config} <- prepared_ai_config(context),
           {:ok, output} <- reply_output(reply) do
        request_opts =
          request_opts
          |> Keyword.put(:jido_context, context)
          |> Keyword.put(:output, output)

        generate_with(ai_config, input, request_opts)
      end
    else
      {:error, {:invalid_options, opts}}
    end
  end

  def respond(_context, "", _opts), do: {:error, :empty_input}
  def respond(_context, input, _opts) when not is_binary(input), do: {:error, {:invalid_input, input}}
  def respond(_context, _input, opts), do: {:error, {:invalid_options, opts}}

  defp generate_with(ai_config, input, opts) do
    with {:ok, runtime} <- runtime_options(opts),
         {:ok, model} <- Models.resolve(ai_config.model),
         controls = Map.get(ai_config, :controls, Plugin.default_controls()),
         deadline = deadline(controls.timeout),
         :ok <-
           run_controls(controls.input, :input, input, runtime.jido_context, deadline),
         {:ok, tools} <-
           ToolAdapter.from_specs(
             Map.get(ai_config, :tools, []),
             runtime.jido_context,
             deadline: deadline
           ),
         context = context(ai_config.instructions, input),
         output = Keyword.get(runtime.request_options, :output),
         request_opts = request_options(tools, runtime.request_options),
         state = request_state(controls, deadline),
         {:ok, response} <- generate_response(model, context, tools, request_opts, state),
         {:ok, output} <- response_output(response, output),
         :ok <-
           run_controls(controls.output, :output, output, runtime.jido_context, deadline) do
      {:ok, output}
    end
  end

  @doc "Starts one streaming response from an AI Agent definition or instance."
  @spec stream(module() | Jido.Agent.t(), String.t(), keyword()) ::
          {:ok, ReqLLM.StreamResponse.t()} | {:error, generate_error()}
  def stream(agent, input, opts \\ [])

  def stream(agent, input, opts) when is_binary(input) and byte_size(input) > 0 do
    with {:ok, runtime} <- runtime_options(opts),
         {:ok, ai_config} <- ai_config(agent),
         controls = Map.get(ai_config, :controls, Plugin.default_controls()),
         :ok <- validate_stream_controls(controls),
         {:ok, model} <- Models.resolve(ai_config.model),
         deadline = deadline(controls.timeout),
         :ok <-
           run_controls(controls.input, :input, input, runtime.jido_context, deadline),
         {:ok, tools} <-
           ToolAdapter.from_specs(
             Map.get(ai_config, :tools, []),
             runtime.jido_context,
             deadline: deadline
           ),
         context = context(ai_config.instructions, input),
         {:ok, timeout} <- remaining_timeout(deadline, controls.timeout),
         request_opts =
           request_options(tools, runtime.request_options)
           |> put_receive_timeout(timeout) do
      ReqLLM.stream_text(model, context, request_opts)
    end
  end

  def stream(_agent, "", _opts), do: {:error, :empty_input}
  def stream(_agent, input, _opts) when not is_binary(input), do: {:error, {:invalid_input, input}}
  def stream(_agent, _input, opts), do: {:error, {:invalid_options, opts}}

  defp ai_config(agent) do
    case Plugin.config(agent) do
      nil -> {:error, :missing_ai_config}
      config -> {:ok, config}
    end
  end

  defp prepared_ai_config(context) do
    case get_in(context, [:plugin_inputs, Plugin]) do
      %Jido.Plugin.Input{prepared: config} when is_map(config) -> {:ok, config}
      _other -> {:error, :missing_ai_config}
    end
  end

  defp reply_output(module) when is_atom(module) and module not in [nil, true, false] do
    if Jido.SignalAction.defined?(module) do
      case module.__signal_action__().output do
        %{schema: schema} -> {:ok, ReqLLM.Output.object(schema)}
        _other -> {:error, :invalid_reply_contract}
      end
    else
      {:error, :invalid_reply_contract}
    end
  end

  defp reply_output(_module), do: {:error, :invalid_reply_contract}

  defp context("", input), do: ReqLLM.Context.new([ReqLLM.Context.user(input)])

  defp context(instructions, input) do
    ReqLLM.Context.new([
      ReqLLM.Context.system(instructions),
      ReqLLM.Context.user(input)
    ])
  end

  defp request_options(tools, opts), do: maybe_put_option(opts, :tools, tools)

  defp request_state(controls, deadline) do
    %{
      controls: controls,
      deadline: deadline,
      model_calls: 0,
      tool_calls: 0,
      iterations: 0
    }
  end

  defp generate_response(model, context, tools, opts, state) do
    with :ok <- model_call_allowed(state),
         {:ok, timeout} <- remaining_timeout(state.deadline, state.controls.timeout),
         request_opts = put_receive_timeout(opts, timeout),
         {:ok, response} <- ReqLLM.generate_text(model, context, request_opts) do
      state = %{state | model_calls: state.model_calls + 1}
      continue_tool_calls(model, response, tools, opts, state)
    end
  end

  defp continue_tool_calls(_model, response, _tools, _opts, _state)
       when not is_struct(response, ReqLLM.Response),
       do: {:ok, response}

  defp continue_tool_calls(model, response, tools, opts, state) do
    with {:ok, calls} <- actionable_tool_calls(response, opts) do
      case calls do
        [] ->
          {:ok, response}

        calls ->
          with :ok <- tool_calls_allowed(state, length(calls)),
               {:ok, continued_context} <- continue_context(response, calls, tools) do
            next_state = %{
              state
              | tool_calls: state.tool_calls + length(calls),
                iterations: state.iterations + 1
            }

            generate_response(model, continued_context, tools, opts, next_state)
          end
      end
    end
  end

  defp actionable_tool_calls(response, opts) do
    calls = ReqLLM.Response.tool_calls(response)

    if match?(%ReqLLM.Output{}, Keyword.get(opts, :output)) do
      {output_calls, tool_calls} =
        Enum.split_with(calls, &ReqLLM.ToolCall.matches_name?(&1, "structured_output"))

      case {output_calls, tool_calls} do
        {[], calls} ->
          {:ok, calls}

        {[_output_call], []} ->
          {:ok, []}

        {_output_calls, _tool_calls} ->
          {:error, {:invalid_model_response, :mixed_structured_output_and_tool_calls}}
      end
    else
      {:ok, calls}
    end
  end

  defp continue_context(response, calls, tools) do
    case ToolAdapter.preflight(calls, tools) do
      :ok ->
        {:ok, ReqLLM.Context.execute_and_append_tools(response.context, calls, tools)}

      {:error, resolutions} ->
        results = ToolAdapter.rejection_messages(resolutions)
        ReqLLM.Context.append_tool_exchange(response.context, response, results)
    end
  end

  defp model_call_allowed(state) do
    if state.model_calls < state.controls.max_model_calls,
      do: :ok,
      else: {:error, {:limit_exceeded, :max_model_calls}}
  end

  defp tool_calls_allowed(state, call_count) do
    cond do
      state.iterations >= state.controls.max_iterations ->
        {:error, {:limit_exceeded, :max_iterations}}

      state.tool_calls + call_count > state.controls.max_tool_calls ->
        {:error, {:limit_exceeded, :max_tool_calls}}

      true ->
        :ok
    end
  end

  defp response_output(%ReqLLM.Response{} = response, nil) do
    case ReqLLM.Response.text(response) do
      text when is_binary(text) -> {:ok, text}
      _other -> {:error, :missing_output}
    end
  end

  defp response_output(%ReqLLM.Response{} = response, %ReqLLM.Output{} = descriptor) do
    case ReqLLM.Response.output(response, descriptor) do
      nil -> {:error, :missing_output}
      output -> normalize_output(output, descriptor)
    end
  end

  defp response_output(_response, _descriptor), do: {:error, :missing_output}

  defp normalize_output(output, %ReqLLM.Output{type: :object, schema: %_{} = schema}) do
    Zoi.parse(schema, output, coerce: true)
  end

  defp normalize_output(output, %ReqLLM.Output{type: :array, element: %_{} = schema}) do
    schema
    |> Zoi.list()
    |> Zoi.parse(output, coerce: true)
  end

  defp normalize_output(output, _descriptor), do: {:ok, output}

  defp run_controls(actions, stage, value, context, deadline) do
    with {:ok, timeout} <- remaining_timeout(deadline, deadline.timeout) do
      Controls.run(actions, stage, value, context, timeout: timeout)
    end
  end

  defp validate_stream_controls(%{output: []}), do: :ok

  defp validate_stream_controls(_controls),
    do: {:error, :output_control_requires_buffered_response}

  defp runtime_options(opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      {jido_context, request_options} = Keyword.pop(opts, :jido_context, %{})

      if is_map(jido_context) do
        {:ok, %{jido_context: jido_context, request_options: request_options}}
      else
        {:error, {:invalid_options, opts}}
      end
    else
      {:error, {:invalid_options, opts}}
    end
  end

  defp runtime_options(opts), do: {:error, {:invalid_options, opts}}

  defp deadline(timeout) do
    %{at: System.monotonic_time(:millisecond) + timeout, timeout: timeout}
  end

  defp remaining_timeout(deadline, configured_timeout) do
    remaining = deadline.at - System.monotonic_time(:millisecond)

    if remaining > 0,
      do: {:ok, remaining},
      else: {:error, {:request_timeout, configured_timeout}}
  end

  defp put_receive_timeout(opts, timeout) do
    case Keyword.get(opts, :receive_timeout) do
      configured when is_integer(configured) and configured > 0 ->
        Keyword.put(opts, :receive_timeout, min(configured, timeout))

      _other ->
        Keyword.put(opts, :receive_timeout, timeout)
    end
  end

  defp maybe_put_option(opts, _key, nil), do: opts
  defp maybe_put_option(opts, _key, []), do: opts
  defp maybe_put_option(opts, key, value), do: Keyword.put(opts, key, value)
end
