defmodule Jido.AI.Directive.Helpers do
  @moduledoc """
  Helper functions for DirectiveExec implementations.

  This module centralizes directive runtime helpers for:
  - Task supervisor resolution
  - Model resolution from directive fields
  - Message normalization/building
  - Request option assembly
  - Error classification
  """

  alias Jido.AI.{Observe, Signal, Turn, Usage}

  @doc """
  Gets the task supervisor from agent state.

  First checks the TaskSupervisorSkill's internal state (`__task_supervisor_skill__`),
  then falls back to the top-level `:task_supervisor` field for standalone usage.

  ## Examples

      iex> state = %{__task_supervisor_skill__: %{supervisor: supervisor_pid}}
      iex> Jido.AI.Directive.Helpers.get_task_supervisor(state)
      supervisor_pid

      iex> state = %{task_supervisor: supervisor_pid}
      iex> Jido.AI.Directive.Helpers.get_task_supervisor(state)
      supervisor_pid

  """
  def get_task_supervisor(%Jido.AgentServer.State{agent: agent}) do
    # Handle AgentServer.State struct - extract the agent's state
    get_task_supervisor(agent.state)
  end

  def get_task_supervisor(state) when is_map(state) do
    # First check TaskSupervisorSkill's internal state
    case Map.get(state, :__task_supervisor_skill__) do
      %{supervisor: supervisor} when is_pid(supervisor) ->
        supervisor

      _ ->
        # Fall back to top-level state field (for standalone usage)
        case Map.get(state, :task_supervisor) do
          nil ->
            raise """
            Task supervisor not found in agent state.

            In Jido 2.0, each agent instance requires its own task supervisor.
            Ensure your agent is started with Jido.AI which will automatically
            create and store a per-instance supervisor in the agent state.

            Example:
                use Jido.AI.Agent,
                  name: "my_agent",
                  tools: [MyApp.Tool1, MyApp.Tool2]
            """

          supervisor when is_pid(supervisor) ->
            supervisor
        end
    end
  end

  @doc """
  Resolves a model from directive fields.

  Supports both direct model specification and model alias resolution.
  """
  @spec resolve_directive_model(map()) :: String.t()
  def resolve_directive_model(%{model: model}) when is_binary(model) and model != "", do: model

  def resolve_directive_model(%{model_alias: alias_atom}) when is_atom(alias_atom) and not is_nil(alias_atom) do
    Jido.AI.resolve_model(alias_atom)
  end

  def resolve_directive_model(%{model: nil, model_alias: nil}) do
    raise ArgumentError, "Either model or model_alias must be provided"
  end

  def resolve_directive_model(_) do
    raise ArgumentError, "Either model or model_alias must be provided"
  end

  @doc """
  Builds messages for LLM calls from context and optional system prompt.
  """
  @spec build_directive_messages(term(), String.t() | nil) :: list()
  def build_directive_messages(context, nil), do: normalize_directive_messages(context)

  def build_directive_messages(context, system_prompt) when is_binary(system_prompt) do
    messages = normalize_directive_messages(context)
    system_message = %{role: :system, content: system_prompt}
    [system_message | messages]
  end

  @doc false
  @spec normalize_directive_messages(term()) :: list()
  def normalize_directive_messages(%{messages: msgs}) when is_list(msgs), do: msgs
  def normalize_directive_messages(%{"messages" => msgs}) when is_list(msgs), do: msgs
  def normalize_directive_messages(msgs) when is_list(msgs), do: msgs
  def normalize_directive_messages(_context), do: []

  @doc """
  Adds timeout option to a keyword list if timeout is specified.
  """
  @spec add_timeout_opt(keyword(), integer() | nil) :: keyword()
  def add_timeout_opt(opts, nil), do: opts

  def add_timeout_opt(opts, timeout) when is_integer(timeout) do
    Keyword.put(opts, :receive_timeout, timeout)
  end

  @doc """
  Adds req_http_options option to a keyword list if options are specified.
  """
  @spec add_req_http_options(keyword(), list() | nil) :: keyword()
  def add_req_http_options(opts, nil), do: opts
  def add_req_http_options(opts, []), do: opts

  def add_req_http_options(opts, req_http_options) when is_list(req_http_options) do
    Keyword.put(opts, :req_http_options, req_http_options)
  end

  @doc """
  Adds tools option to a keyword list if tools are specified.
  """
  @spec add_tools_opt(keyword(), list()) :: keyword()
  def add_tools_opt(opts, []), do: opts
  def add_tools_opt(opts, tools), do: Keyword.put(opts, :tools, tools)

  @doc """
  Finishes a successful LLM directive telemetry span and emits completion telemetry.
  """
  def finish_llm_complete(obs_cfg, span_ctx, duration_ms, event_meta, turn)
      when is_map(event_meta) do
    usage = turn_usage(turn)
    measurements = llm_complete_measurements(duration_ms, usage)
    metadata = llm_complete_metadata(event_meta, usage)

    Observe.finish_span(span_ctx, measurements)
    Observe.emit(obs_cfg, Observe.llm(:complete), measurements, metadata)
  end

  @doc """
  Emits an `ai.usage` signal for per-call directive usage tracking.
  """
  def emit_llm_usage_report(_agent_pid, _call_id, _model, nil), do: :ok

  def emit_llm_usage_report(agent_pid, call_id, model, usage) when is_map(usage) do
    token_counts = Usage.token_counts(usage)

    if token_counts.input_tokens > 0 or token_counts.output_tokens > 0 do
      metadata_usage = Usage.normalize(usage) || usage

      signal =
        Signal.Usage.new!(%{
          call_id: call_id,
          model: model,
          input_tokens: token_counts.input_tokens,
          output_tokens: token_counts.output_tokens,
          total_tokens: token_counts.total_tokens,
          metadata: %{
            cache_creation_input_tokens: Usage.value(metadata_usage, :cache_creation_input_tokens),
            cache_read_input_tokens: Usage.value(metadata_usage, :cache_read_input_tokens)
          }
        })

      Jido.AgentServer.cast(agent_pid, signal)
    end

    :ok
  end

  defp turn_usage(%Turn{usage: usage}), do: usage
  defp turn_usage(%{usage: usage}), do: usage
  defp turn_usage(_turn), do: nil

  defp llm_complete_measurements(duration_ms, usage) do
    %{duration_ms: duration_ms}
    |> Map.merge(Usage.token_measurements(usage))
  end

  defp llm_complete_metadata(event_meta, usage) when is_map(usage) and map_size(usage) > 0 do
    Map.put(event_meta, :usage, Usage.with_token_counts(usage))
  end

  defp llm_complete_metadata(event_meta, _usage), do: event_meta

  @doc """
  Classifies an error into a runtime category.

  Returns one of: `:rate_limit`, `:auth`, `:timeout`, `:provider_error`,
  `:network`, `:validation`, `:unknown`.
  """
  @spec classify_error(term()) :: atom()
  def classify_error(%{status: status}) when status == 429, do: :rate_limit
  def classify_error(%{status: status}) when status in [401, 403], do: :auth
  def classify_error(%{status: status}) when status >= 500, do: :provider_error
  def classify_error(%{status: status}) when status >= 400, do: :validation

  def classify_error(%{reason: :timeout}), do: :timeout
  def classify_error(%{reason: :connect_timeout}), do: :timeout
  def classify_error(%{reason: :checkout_timeout}), do: :timeout

  def classify_error(%{reason: reason}) when reason in [:econnrefused, :nxdomain, :closed], do: :network

  def classify_error({:error, :timeout}), do: :timeout
  def classify_error(:timeout), do: :timeout

  def classify_error(%Mint.TransportError{}), do: :network
  def classify_error(%Mint.HTTPError{}), do: :network

  def classify_error(_), do: :unknown
end
