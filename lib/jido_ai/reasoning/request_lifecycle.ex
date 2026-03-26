defmodule Jido.AI.Reasoning.RequestLifecycle do
  @moduledoc """
  Shared request lifecycle helpers for non-delegated reasoning strategies.
  """

  alias Jido.AI.Observe
  alias Jido.AI.Signal

  @type lifecycle_event :: :start | :complete | :failed

  @spec put_active_request_id(map(), map(), String.t() | nil, [term()]) :: map()
  def put_active_request_id(previous_state, new_state, request_id, active_statuses)
      when is_map(previous_state) and is_map(new_state) and is_list(active_statuses) do
    cond do
      terminal_status?(new_state[:status]) ->
        Map.put(new_state, :active_request_id, nil)

      is_binary(request_id) and new_state[:status] in active_statuses ->
        Map.put(new_state, :active_request_id, request_id)

      true ->
        Map.put(new_state, :active_request_id, previous_state[:active_request_id])
    end
  end

  @spec emit_started(atom(), map(), String.t(), String.t(), keyword()) :: :ok
  def emit_started(strategy, state, request_id, query, opts \\ [])
      when is_atom(strategy) and is_map(state) and is_binary(request_id) and is_binary(query) and is_list(opts) do
    signal = Signal.RequestStarted.new!(%{request_id: request_id, query: query, run_id: request_id})
    Jido.AgentServer.cast(self(), signal)
    emit_request_telemetry(strategy, state, :start, request_id, opts)
  end

  @spec emit_terminal(atom(), map(), map(), keyword()) :: :ok
  def emit_terminal(strategy, previous_state, new_state, opts \\ [])
      when is_atom(strategy) and is_map(previous_state) and is_map(new_state) and is_list(opts) do
    request_id =
      Keyword.get(opts, :request_id, new_state[:active_request_id] || previous_state[:active_request_id])

    cond do
      not completed_status?(previous_state[:status]) and completed_status?(new_state[:status]) and is_binary(request_id) ->
        signal = Signal.RequestCompleted.new!(%{request_id: request_id, result: new_state[:result], run_id: request_id})
        Jido.AgentServer.cast(self(), signal)
        emit_request_telemetry(strategy, new_state, :complete, request_id, opts)

      not error_status?(previous_state[:status]) and error_status?(new_state[:status]) and is_binary(request_id) ->
        signal = Signal.RequestFailed.new!(%{request_id: request_id, error: new_state[:result], run_id: request_id})
        Jido.AgentServer.cast(self(), signal)
        emit_request_telemetry(strategy, new_state, :failed, request_id, opts)

      true ->
        :ok
    end
  end

  @spec emit_request_telemetry(atom(), map(), lifecycle_event(), String.t(), keyword()) :: :ok
  def emit_request_telemetry(strategy, state, event, request_id, opts \\ [])
      when is_atom(strategy) and is_map(state) and is_binary(request_id) and is_list(opts) do
    obs_cfg = get_in(state, [:config, :observability]) || %{}
    usage = Keyword.get(opts, :usage, extract_usage(state))
    model = Keyword.get(opts, :model, config_model(state))
    iteration = Keyword.get(opts, :iteration)
    llm_call_id = Keyword.get(opts, :llm_call_id, state[:current_call_id])
    operation = Keyword.get(opts, :operation, :stream_text)
    error_type = Keyword.get(opts, :error_type)

    metadata = %{
      agent_id: nil,
      request_id: request_id,
      run_id: request_id,
      iteration: iteration,
      llm_call_id: llm_call_id,
      tool_call_id: nil,
      tool_name: nil,
      model: if(model, do: Jido.AI.ModelInput.label(model), else: nil),
      origin: :worker_runtime,
      operation: operation,
      strategy: strategy,
      termination_reason: telemetry_termination_reason(event, state),
      error_type: if(event == :failed, do: error_type || infer_error_type(state[:result]), else: nil)
    }

    measurements = %{
      duration_ms: 0,
      input_tokens: Map.get(usage, :input_tokens, 0),
      output_tokens: Map.get(usage, :output_tokens, 0),
      total_tokens: Map.get(usage, :total_tokens, Map.get(usage, :input_tokens, 0) + Map.get(usage, :output_tokens, 0))
    }

    Observe.emit(obs_cfg, Observe.request(event), measurements, metadata)
  end

  @spec extract_usage(map()) :: map()
  def extract_usage(%{usage: usage}) when is_map(usage) and usage != %{}, do: usage
  def extract_usage(%{result: %{usage: usage}}) when is_map(usage), do: usage
  def extract_usage(_state), do: %{}

  @spec infer_error_type(term()) :: atom() | nil
  def infer_error_type(%{termination: termination}) when is_atom(termination), do: termination
  def infer_error_type(%{reason: reason}) when is_atom(reason), do: reason
  def infer_error_type(%{type: type}) when is_atom(type), do: type
  def infer_error_type(%{code: type}) when is_atom(type), do: type
  def infer_error_type({:error, reason, _effects}) when is_atom(reason), do: reason
  def infer_error_type({:error, reason}) when is_atom(reason), do: reason
  def infer_error_type(reason) when is_atom(reason), do: reason
  def infer_error_type(_), do: nil

  defp telemetry_termination_reason(:complete, _state), do: :complete
  defp telemetry_termination_reason(:failed, state), do: state[:termination_reason] || :error
  defp telemetry_termination_reason(_event, _state), do: nil

  defp completed_status?(:completed), do: true
  defp completed_status?("completed"), do: true
  defp completed_status?(_status), do: false

  defp error_status?(:error), do: true
  defp error_status?("error"), do: true
  defp error_status?(_status), do: false

  defp terminal_status?(status), do: completed_status?(status) or error_status?(status)

  defp config_model(state) do
    state
    |> Map.get(:config, %{})
    |> Map.get(:model)
  end
end
