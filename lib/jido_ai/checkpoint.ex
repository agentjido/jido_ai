defmodule Jido.AI.Checkpoint do
  @moduledoc """
  Removes process-local values from `Jido.AI.Agent` checkpoints.

  Request stream sinks and ReAct worker processes cannot survive a restore.
  Active streamed requests are stored as failed with
  `error: :stream_interrupted`, and the ReAct strategy is restored as idle.
  """

  alias Jido.AI.Request
  alias Jido.AI.ToolAdapter

  @strategy_key :__strategy__

  @strategy_handle_resets %{
    react_worker_pid: nil,
    react_worker_status: :missing,
    pending_worker_start: nil,
    pending_input_server: nil
  }

  @interrupted_run_resets %{
    status: :idle,
    iteration: 0,
    run_context: nil,
    pending_tool_calls: [],
    tool_results: [],
    final_answer: nil,
    result: nil,
    current_llm_call_id: nil,
    termination_reason: nil,
    run_tool_context: %{},
    run_req_http_options: [],
    run_llm_opts: [],
    active_request_id: nil,
    pending_input_server: nil,
    last_pending_input_control: nil,
    cancel_reason: nil,
    usage: %{},
    started_at: nil,
    streaming_text: "",
    streaming_thinking: "",
    thinking_trace: [],
    checkpoint_token: nil,
    react_worker_pid: nil,
    react_worker_status: :missing,
    pending_worker_start: nil
  }

  @doc false
  @spec sanitize_state(map()) :: map()
  def sanitize_state(state) when is_map(state) do
    state
    |> Request.sanitize_requests()
    |> update_strategy(&sanitize_strategy/1)
  end

  def sanitize_state(state), do: state

  @doc false
  @spec rehydrate_state(map()) :: map()
  def rehydrate_state(state), do: sanitize_state(state)

  defp update_strategy(state, fun) do
    case Map.get(state, @strategy_key) do
      strategy when is_map(strategy) -> Map.put(state, @strategy_key, fun.(strategy))
      _other -> state
    end
  end

  defp sanitize_strategy(strategy) do
    strategy
    |> reset_interrupted_run()
    |> reset_react_handles()
    |> rebuild_reqllm_tools()
  end

  defp reset_interrupted_run(strategy) do
    if react_run_active?(strategy), do: Map.merge(strategy, @interrupted_run_resets), else: strategy
  end

  defp react_run_active?(strategy) do
    react_strategy_state?(strategy) and
      (is_binary(Map.get(strategy, :active_request_id)) or
         Map.get(strategy, :status) in [:awaiting_llm, :awaiting_tool] or
         Map.get(strategy, :react_worker_status) in [:starting, :running])
  end

  defp reset_react_handles(strategy) do
    if react_strategy_state?(strategy), do: Map.merge(strategy, @strategy_handle_resets), else: strategy
  end

  defp react_strategy_state?(strategy) do
    Map.has_key?(strategy, :react_worker_pid) or Map.has_key?(strategy, :react_worker_status)
  end

  defp rebuild_reqllm_tools(%{config: %{tools: tools} = config} = strategy) when is_list(tools) do
    %{strategy | config: Map.put(config, :reqllm_tools, ToolAdapter.from_actions(tools))}
  end

  defp rebuild_reqllm_tools(strategy), do: strategy
end
