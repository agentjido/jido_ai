defmodule Jido.AI do
  @moduledoc """
  AI extensions for Jido.

  Use `Jido.AI.Agent` to define an Agent with the AI Plugin included.

  `preflight/3` prepares an inspectable request without execution.
  `generate/3` returns only accepted output. `reason/3` returns a completed
  result with usage and events. `run/3` also returns an explicit failed result
  for execution failures.
  """

  alias Jido.AI.{Event, Models, Plugin, Request, Result}
  alias Jido.AI.Flow.Reason
  alias Jido.AI.Reasoning.State

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
          | {:unknown_tools, [String.t()]}
          | {:request_timeout, pos_integer()}
          | term()

  @typedoc "Use `request_error/0` for new code."
  @type generate_error :: request_error()

  @type reasoning_result :: Result.t()

  @doc "Prepares one request without running controls, tools, or a model."
  @spec preflight(module() | Jido.Agent.t(), String.t(), keyword()) ::
          {:ok, Request.t()} | {:error, request_error()}
  def preflight(agent, input, opts \\ [])

  def preflight(agent, input, opts) when is_binary(input) and byte_size(input) > 0 do
    if is_list(opts) and Keyword.keyword?(opts) do
      {reply, request_opts} = Keyword.pop(opts, :reply)

      with {:ok, runtime} <- Request.options(request_opts),
           {:ok, ai_config} <- ai_config(agent),
           do: Request.prepare(ai_config, input, runtime, reply)
    else
      {:error, {:invalid_options, opts}}
    end
  end

  def preflight(_agent, "", _opts), do: {:error, :empty_input}

  def preflight(_agent, input, _opts) when not is_binary(input),
    do: {:error, {:invalid_input, input}}

  def preflight(_agent, _input, opts), do: {:error, {:invalid_options, opts}}

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
         {:ok, ai_config} <- ai_config(agent),
         {:ok, request} <- Request.prepare(ai_config, input, runtime, nil) do
      run_prepared(ai_config, request, runtime.jido_context)
    end
  end

  def reason(_agent, "", _opts), do: {:error, :empty_input}
  def reason(_agent, input, _opts) when not is_binary(input), do: {:error, {:invalid_input, input}}
  def reason(_agent, _input, opts), do: {:error, {:invalid_options, opts}}

  @doc "Runs one request and returns an explicit completed or failed result."
  @spec run(module() | Jido.Agent.t(), String.t(), keyword()) ::
          {:ok, Result.t()}
          | {:ok, Result.t(), Jido.Action.effects()}
          | {:error, Result.t() | request_error()}
  def run(agent, input, opts \\ [])

  def run(agent, input, opts) when is_binary(input) and byte_size(input) > 0 do
    with {:ok, runtime} <- Request.options(opts),
         {:ok, ai_config} <- ai_config(agent),
         {:ok, request} <- Request.prepare(ai_config, input, runtime, nil) do
      started_at = System.monotonic_time(:millisecond)

      case run_prepared(ai_config, request, runtime.jido_context) do
        {:ok, %Result{} = result} ->
          {:ok, result}

        {:ok, %Result{} = result, effects} ->
          {:ok, result, effects}

        {:error, reason} ->
          elapsed_ms = max(System.monotonic_time(:millisecond) - started_at, 0)
          {:error, failed_result(request, reason, elapsed_ms)}
      end
    end
  end

  def run(_agent, "", _opts), do: {:error, :empty_input}
  def run(_agent, input, _opts) when not is_binary(input), do: {:error, {:invalid_input, input}}
  def run(_agent, _input, opts), do: {:error, {:invalid_options, opts}}

  @doc """
  Generates reply data for a standalone Signal Action.

  The required `:reply` option is a `Jido.SignalAction` with an output Signal.
  Its output schema shapes the model result. This function starts the configured
  reasoning Flow and returns the reply data.

  Do not call this function from an Action inside another Flow. Add
  `Jido.AI.Flow.Reason` as a normal step in the parent Flow so all work remains
  in one execution graph.
  """
  @spec respond(map(), String.t(), keyword()) ::
          {:ok, map()} | {:error, request_error()}
  def respond(context, input, opts \\ []) do
    context
    |> respond_result(input, opts)
    |> output_result()
  end

  @doc "Runs one structured reply request and returns its explicit result."
  @spec respond_result(map(), String.t(), keyword()) ::
          {:ok, Result.t()}
          | {:ok, Result.t(), Jido.Action.effects()}
          | {:error, request_error()}
  def respond_result(context, input, opts \\ [])

  def respond_result(context, input, opts)
      when is_map(context) and is_binary(input) and byte_size(input) > 0 and is_list(opts) do
    if Keyword.keyword?(opts) do
      {reply, request_opts} = Keyword.pop(opts, :reply)

      with {:ok, ai_config} <- prepared_ai_config(context),
           {:ok, runtime} <- Request.options(Keyword.put(request_opts, :jido_context, context)),
           {:ok, request} <- Request.prepare(ai_config, input, runtime, reply) do
        run_prepared(ai_config, request, runtime.jido_context)
      end
    else
      {:error, {:invalid_options, opts}}
    end
  end

  def respond_result(_context, "", _opts), do: {:error, :empty_input}

  def respond_result(_context, input, _opts) when not is_binary(input),
    do: {:error, {:invalid_input, input}}

  def respond_result(_context, _input, opts), do: {:error, {:invalid_options, opts}}

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

  defp run_prepared(config, %Request{} = request, jido_context) do
    params = %{prepared: request}
    context = put_plugin_input(jido_context, config)

    case Jido.Exec.run(Reason, params, context, timeout: config.controls.timeout) do
      {:ok, %Result{status: :completed, usage: usage, events: events} = result}
      when is_map(usage) and is_list(events) ->
        {:ok, result}

      {:ok, %Result{status: :completed, usage: usage, events: events} = result, effects}
      when is_map(usage) and is_list(events) and is_list(effects) ->
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

  defp failed_result(request, reason, elapsed_ms) do
    started =
      Event.new(request, :request_started, Request.started_event_data(request),
        sequence: 1,
        elapsed_ms: 0,
        iteration: 0
      )

    failed =
      Event.new(request, :request_failed, %{error: State.summarize(reason)},
        sequence: 2,
        elapsed_ms: elapsed_ms,
        iteration: 0
      )

    Result.failed(request, reason, [started, failed])
  end
end
