defmodule Jido.AI.Reasoning.ReAct.Actions.Helpers do
  @moduledoc false

  alias Jido.AI.Reasoning.ReAct.Config

  @doc """
  Builds runtime ReAct configuration from action params and execution context.
  """
  @spec build_config(map(), map()) :: Config.t()
  def build_config(params, context) do
    opts = %{
      model: params[:model] || context[:model] || :capable,
      system_prompt: params[:system_prompt],
      tools: params[:tools] || context[:tools] || get_in(context, [:plugin_state, :tool_calling, :tools]) || %{},
      max_iterations: params[:max_iterations],
      max_tokens: params[:max_tokens],
      temperature: params[:temperature],
      llm_timeout_ms: params[:llm_timeout_ms] || params[:timeout_ms],
      tool_timeout_ms: params[:tool_timeout_ms],
      tool_max_retries: params[:tool_max_retries],
      tool_retry_backoff_ms: params[:tool_retry_backoff_ms],
      tool_concurrency: params[:tool_concurrency],
      emit_signals?: params[:emit_signals?],
      emit_telemetry?: params[:emit_telemetry?],
      redact_tool_args?: params[:redact_tool_args?],
      capture_deltas?: params[:capture_deltas?],
      capture_thinking?: params[:capture_thinking?],
      capture_messages?: params[:capture_messages?],
      token_secret: params[:token_secret] || context[:react_token_secret],
      token_ttl_ms: params[:token_ttl_ms],
      token_compress?: params[:token_compress?]
    }

    Config.new(opts)
  end

  @doc """
  Builds runner options (ids, task supervisor, runtime context) for ReAct actions.
  """
  @spec build_runner_opts(map(), map()) :: keyword()
  def build_runner_opts(params, context) do
    opts =
      []
      |> maybe_put(:request_id, params[:request_id])
      |> maybe_put(:run_id, params[:run_id])
      |> maybe_put(:task_supervisor, resolve_task_supervisor(params, context))

    runtime_context =
      context
      |> normalize_context()
      |> Map.merge(params[:runtime_context] || %{})

    Keyword.put(opts, :context, runtime_context)
  end

  @doc """
  Resolves a task supervisor from params or nested context sources.
  """
  @spec resolve_task_supervisor(map(), map()) :: pid() | atom() | nil
  def resolve_task_supervisor(params, context) do
    params[:task_supervisor] || context_task_supervisor(context)
  end

  defp context_task_supervisor(%Jido.AgentServer.State{agent: %{state: state}}),
    do: context_task_supervisor(state)

  defp context_task_supervisor(%Jido.Agent{state: state}), do: context_task_supervisor(state)

  defp context_task_supervisor(context) when is_map(context) do
    context[:task_supervisor] ||
      get_in(context, [:__task_supervisor_skill__, :supervisor]) ||
      get_in(context, [:state, :__task_supervisor_skill__, :supervisor]) ||
      get_in(context, [:agent, :state, :__task_supervisor_skill__, :supervisor]) ||
      get_in(context, [:agent_state, :__task_supervisor_skill__, :supervisor])
  end

  defp context_task_supervisor(_), do: nil

  defp normalize_context(%{} = context), do: context
  defp normalize_context(_), do: %{}

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
