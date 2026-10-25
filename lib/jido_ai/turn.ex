defmodule Jido.AI.Turn do
  @moduledoc """
  Completes one AI request and reply turn inside an Agent Action.

  `complete/4` accepts reply data or a completed `Jido.AI.Result`. It uses the
  selected route contract to create a typed history Signal. It appends the
  request and reply to a Thread or Session in Agent state. It returns output
  for the route `state` and `reply` projections. The Agent remains responsible
  for the final state commit and correlated reply delivery.

  `prepare/2` validates the current request and turn state without doing model
  work or changing state. Use it as an Action step before a reasoning step.
  """

  alias Jido.AI.{Result, Route}
  alias Jido.{Session, Signal, Thread}

  @type error_reason ::
          :invalid_reply_route
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
  @spec complete(map(), Route.ref(), term(), keyword()) ::
          {:ok, %{state: map(), reply: term()}} | {:error, error_reason()}
  def complete(context, route, %Result{status: :completed, output: output} = result, opts) do
    case Result.validate(result) do
      :ok -> complete(context, route, output, opts)
      {:error, reason} -> {:error, {:invalid_ai_result, reason}}
    end
  end

  def complete(_context, _route, %Result{status: status}, _opts),
    do: {:error, {:turn_not_completed, status}}

  def complete(context, route, answer, opts) when is_map(context) and is_list(opts) do
    with {:ok, request, _agent_state} <- turn_context(context),
         {:ok, contract} <- reply_route(route, request),
         {:ok, prepared} <- prepare_context(context, opts),
         %{
           agent_state: agent_state,
           state_key: state_key,
           turn_state: conversation
         } <- prepared,
         {:ok, reply} <- Route.reply(contract, request, answer),
         {:ok, conversation} <- append(conversation, [request, reply]) do
      {:ok, %{state: Map.put(agent_state, state_key, conversation), reply: reply.data}}
    end
  end

  def complete(context, _route, _answer, _opts) when not is_map(context),
    do: {:error, :invalid_turn_context}

  def complete(_context, _route, _answer, opts),
    do: {:error, {:invalid_turn_options, opts}}

  @doc "Creates reply projection output without changing Agent state."
  @spec complete_reply(map(), Route.ref(), term()) ::
          {:ok, %{reply: term()}} | {:error, error_reason()}
  def complete_reply(context, route, answer) when is_map(context) do
    with {:ok, request, _agent_state} <- turn_context(context),
         {:ok, contract} <- reply_route(route, request),
         {:ok, reply} <- Route.reply_data(contract, answer) do
      {:ok, %{reply: reply}}
    end
  end

  def complete_reply(context, _route, _answer) when not is_map(context),
    do: {:error, :invalid_turn_context}

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

  defp reply_route(route, %Signal{type: type}) do
    case Route.resolve(route) do
      {:ok, %Route{input_type: ^type} = contract} -> {:ok, contract}
      {:ok, %Route{}} -> {:error, :invalid_reply_route}
      {:error, _reason} -> {:error, :invalid_reply_route}
    end
  end

  defp append(%Thread{} = thread, signals), do: Thread.append_many(thread, signals)
  defp append(%Session{} = session, signals), do: Session.append_many(session, signals)
end
