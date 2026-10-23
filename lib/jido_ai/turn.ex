defmodule Jido.AI.Turn do
  @moduledoc """
  Completes one AI request and reply turn inside an Agent Action.

  `complete/4` accepts reply data or a completed `Jido.AI.Result`. It creates a
  typed reply Signal, appends the request and reply to a Thread or Session in
  Agent state, and returns the candidate state with one Reply Directive. The
  Agent remains responsible for the final state commit and Directive delivery.

  `prepare/2` validates the current request and turn state without doing model
  work or changing state. Use it as an Action step before a reasoning step.
  """

  alias Jido.Agent.Directive
  alias Jido.AI.Result
  alias Jido.{Session, Signal, Thread}

  @type error_reason ::
          :invalid_reply_action
          | {:invalid_ai_result, term()}
          | :invalid_turn_context
          | :session_closed
          | {:turn_not_completed, Result.status()}
          | {:invalid_turn_state, term()}
          | {:invalid_turn_options, term()}
          | {:missing_turn_state, atom()}
          | {:unsupported_turn_state, term()}
          | term()

  @doc "Validates the current request and Thread or open Session at `:state_key`."
  @spec prepare(map(), keyword()) ::
          {:ok, %{state_key: atom(), turn_state: Thread.t() | Session.t()}}
          | {:error, error_reason()}
  def prepare(context, opts) when is_map(context) and is_list(opts) do
    with {:ok, prepared} <- prepare_context(context, opts) do
      {:ok, Map.take(prepared, [:state_key, :turn_state])}
    end
  end

  def prepare(context, _opts) when not is_map(context), do: {:error, :invalid_turn_context}
  def prepare(_context, opts), do: {:error, {:invalid_turn_options, opts}}

  @doc "Completes a typed turn for the Thread or Session at `:state_key`."
  @spec complete(map(), module(), term(), keyword()) ::
          {:ok, map(), [Directive.t()]} | {:error, error_reason()}
  def complete(context, reply_action, %Result{status: :completed, output: output} = result, opts) do
    case Result.validate(result) do
      :ok -> complete(context, reply_action, output, opts)
      {:error, reason} -> {:error, {:invalid_ai_result, reason}}
    end
  end

  def complete(_context, _reply_action, %Result{status: status}, _opts),
    do: {:error, {:turn_not_completed, status}}

  def complete(context, reply_action, answer, opts)
      when is_map(context) and is_atom(reply_action) and is_list(opts) do
    with :ok <- validate_reply_action(reply_action),
         {:ok, prepared} <- prepare_context(context, opts),
         %{
           agent_state: agent_state,
           request: request,
           state_key: state_key,
           turn_state: conversation
         } <- prepared,
         {:ok, reply} <- reply(reply_action, request, answer),
         {:ok, conversation} <- append(conversation, [request, reply]) do
      {:ok, Map.put(agent_state, state_key, conversation), [Directive.reply(reply)]}
    end
  end

  def complete(context, _reply_action, _answer, _opts) when not is_map(context),
    do: {:error, :invalid_turn_context}

  def complete(_context, reply_action, _answer, _opts)
      when not is_atom(reply_action) or reply_action in [nil, true, false],
      do: {:error, :invalid_reply_action}

  def complete(_context, _reply_action, _answer, opts),
    do: {:error, {:invalid_turn_options, opts}}

  @doc "Creates one typed Reply Directive without changing Agent state."
  @spec complete_reply(map(), module(), term()) ::
          {:ok, map(), [Directive.t()]} | {:error, error_reason()}
  def complete_reply(context, reply_action, answer)
      when is_map(context) and is_atom(reply_action) do
    with {:ok, request, agent_state} <- turn_context(context),
         {:ok, reply} <- reply(reply_action, request, answer) do
      {:ok, agent_state, [Directive.reply(reply)]}
    end
  end

  def complete_reply(context, _reply_action, _answer) when not is_map(context),
    do: {:error, :invalid_turn_context}

  def complete_reply(_context, _reply_action, _answer), do: {:error, :invalid_reply_action}

  defp prepare_context(context, opts) do
    with {:ok, state_key} <- state_key(opts),
         {:ok, request, agent_state} <- turn_context(context),
         {:ok, turn_state} <- turn_state(agent_state, state_key),
         :ok <- validate_turn_state(turn_state) do
      {:ok,
       %{
         agent_state: agent_state,
         request: request,
         state_key: state_key,
         turn_state: turn_state
       }}
    end
  end

  defp state_key(opts) do
    if Keyword.keyword?(opts) and Keyword.keys(opts) == [:state_key] do
      case Keyword.fetch!(opts, :state_key) do
        key when is_atom(key) and key not in [nil, true, false] -> {:ok, key}
        _key -> {:error, {:invalid_turn_options, opts}}
      end
    else
      {:error, {:invalid_turn_options, opts}}
    end
  end

  defp turn_context(%{signal: %Signal{} = signal, agent_state: state})
       when is_map(state) and not is_struct(state),
       do: {:ok, signal, state}

  defp turn_context(_context), do: {:error, :invalid_turn_context}

  defp turn_state(state, key) do
    case Map.fetch(state, key) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, {:missing_turn_state, key}}
    end
  end

  defp validate_turn_state(%Thread{} = thread) do
    case Thread.validate(thread) do
      :ok -> :ok
      {:error, reason} -> {:error, {:invalid_turn_state, reason}}
    end
  end

  defp validate_turn_state(%Session{} = session) do
    with :ok <- validate_session(session) do
      if session.status == :open, do: :ok, else: {:error, :session_closed}
    end
  end

  defp validate_turn_state(value), do: {:error, {:unsupported_turn_state, value}}

  defp validate_session(session) do
    case Session.validate(session) do
      :ok -> :ok
      {:error, reason} -> {:error, {:invalid_turn_state, reason}}
    end
  end

  defp reply(module, request, answer) do
    with :ok <- validate_reply_action(module), do: module.reply(request, answer)
  end

  defp validate_reply_action(module) do
    if Jido.SignalAction.defined?(module) and function_exported?(module, :reply, 2),
      do: :ok,
      else: {:error, :invalid_reply_action}
  end

  defp append(%Thread{} = thread, signals), do: Thread.append_many(thread, signals)
  defp append(%Session{} = session, signals), do: Session.append_many(session, signals)
end
