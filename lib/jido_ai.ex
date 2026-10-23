defmodule Jido.AI do
  @moduledoc """
  AI extensions for Jido.

  Use `Jido.AI.Agent` to define an Agent with the AI Plugin included.
  """

  alias Jido.AI.{Models, Plugin, Request}
  alias Jido.AI.Flow.Reason

  @type request_error ::
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

  @typedoc "Use `request_error/0` for new code."
  @type generate_error :: request_error()

  @type reasoning_result :: %{
          required(:output) => term(),
          required(:usage) => map(),
          required(:trace) => [map()]
        }

  @doc "Generates one response from an AI Agent definition or instance."
  @spec generate(module() | Jido.Agent.t(), String.t(), keyword()) ::
          {:ok, term()} | {:error, request_error()}
  def generate(agent, input, opts \\ []) do
    agent
    |> reason(input, opts)
    |> output_result()
  end

  @doc "Runs one reasoning Flow and returns its output, usage, and sanitized trace."
  @spec reason(module() | Jido.Agent.t(), String.t(), keyword()) ::
          {:ok, reasoning_result()}
          | {:ok, reasoning_result(), Jido.Action.effects()}
          | {:error, request_error()}
  def reason(agent, input, opts \\ [])

  def reason(agent, input, opts) when is_binary(input) and byte_size(input) > 0 do
    with {:ok, runtime} <- Request.options(opts),
         {:ok, ai_config} <- ai_config(agent) do
      run_reason(ai_config, input, runtime, nil)
    end
  end

  def reason(_agent, "", _opts), do: {:error, :empty_input}
  def reason(_agent, input, _opts) when not is_binary(input), do: {:error, {:invalid_input, input}}
  def reason(_agent, _input, opts), do: {:error, {:invalid_options, opts}}

  @doc """
  Generates reply data for a standalone Signal Action.

  The required `:reply` option is a `Jido.SignalAction` with an output Signal.
  Its output schema shapes the model result. This function starts the configured
  reasoning Flow and returns the reply data.

  Do not call this function from an Action inside another Flow. Add
  `Jido.AI.Flow.Extension` to the parent Flow and use `reason/2` so all work
  remains in one execution graph.
  """
  @spec respond(map(), String.t(), keyword()) ::
          {:ok, map()} | {:error, request_error()}
  def respond(context, input, opts \\ [])

  def respond(context, input, opts)
      when is_map(context) and is_binary(input) and byte_size(input) > 0 and is_list(opts) do
    if Keyword.keyword?(opts) do
      {reply, request_opts} = Keyword.pop(opts, :reply)

      with {:ok, ai_config} <- prepared_ai_config(context),
           {:ok, runtime} <- Request.options(Keyword.put(request_opts, :jido_context, context)) do
        ai_config
        |> run_reason(input, runtime, reply)
        |> output_result()
      end
    else
      {:error, {:invalid_options, opts}}
    end
  end

  def respond(_context, "", _opts), do: {:error, :empty_input}
  def respond(_context, input, _opts) when not is_binary(input), do: {:error, {:invalid_input, input}}
  def respond(_context, _input, opts), do: {:error, {:invalid_options, opts}}

  @doc "Starts one streaming response from an AI Agent definition or instance."
  @spec stream(module() | Jido.Agent.t(), String.t(), keyword()) ::
          {:ok, ReqLLM.StreamResponse.t()} | {:error, request_error()}
  def stream(agent, input, opts \\ [])

  def stream(agent, input, opts) when is_binary(input) and byte_size(input) > 0 do
    with {:ok, runtime} <- Request.options(opts),
         {:ok, ai_config} <- ai_config(agent) do
      Request.stream(ai_config, input, runtime)
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

  defp run_reason(config, input, runtime, reply) do
    params = %{
      input: input,
      reply: reply,
      conversation: runtime.conversation,
      request_options: runtime.request_options
    }

    context = put_plugin_input(runtime.jido_context, config)

    case Jido.Exec.run(Reason, params, context, timeout: config.controls.timeout) do
      {:ok, %{output: _output, usage: usage, trace: trace} = result}
      when is_map(usage) and is_list(trace) ->
        {:ok, result}

      {:ok, %{output: _output, usage: usage, trace: trace} = result, effects}
      when is_map(usage) and is_list(trace) and is_list(effects) ->
        {:ok, result, effects}

      {:error, error} ->
        {:error, direct_error(error)}
    end
  end

  defp output_result({:ok, %{output: output}}), do: {:ok, output}
  defp output_result({:ok, %{output: output}, effects}), do: {:ok, output, effects}
  defp output_result(error), do: error

  defp put_plugin_input(context, config) do
    plugin_inputs = Map.get(context, :plugin_inputs, %{})
    input = %Jido.Plugin.Input{prepared: config}
    Map.put(context, :plugin_inputs, Map.put(plugin_inputs, Plugin, input))
  end

  defp direct_error(%Jido.Action.Error.ExecutionFailureError{
         details: %{action: action, reason: reason}
       })
       when action in [Jido.AI.Flow.Reason.Prepare, Jido.AI.Actions.CallModel],
       do: reason

  defp direct_error(error), do: error
end
