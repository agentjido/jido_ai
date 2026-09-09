defmodule JidoAI.Examples.ThreadSessionValues do
  @moduledoc """
  A small application-owned interaction history built with `Jido.Thread` and
  `Jido.Session`.

  This module does not start an Agent, a Plugin, or a model request. It shows
  how an application can use the portable values before it binds them to live
  `Jido.AI.Session` request work.
  """

  alias Jido.{Session, Thread}

  @doc "Creates a session and records its first user message."
  @spec open_case(String.t(), String.t(), keyword()) :: Session.t()
  def open_case(case_id, question, opts \\ [])
      when is_binary(case_id) and case_id != "" and is_binary(question) and question != "" do
    now = Keyword.get(opts, :now, System.system_time(:millisecond))
    session_id = Keyword.get(opts, :session_id, "support:#{case_id}")
    request_id = Keyword.get(opts, :request_id, "request:#{case_id}:1")

    Session.new(id: session_id, now: now, metadata: %{case_id: case_id})
    |> Session.append(%{
      id: "#{session_id}:user:0",
      at: now,
      kind: :ai_message,
      payload: %{role: :user, content: question},
      refs: %{request_id: request_id}
    })
  end

  @doc "Returns a new session with one assistant answer appended."
  @spec record_answer(Session.t(), String.t(), keyword()) :: Session.t()
  def record_answer(%Session{} = session, answer, opts \\ [])
      when is_binary(answer) and answer != "" do
    at = Keyword.get(opts, :at, System.system_time(:millisecond))
    request_id = Keyword.get(opts, :request_id, "request:answer")

    Session.append(session, %{
      id: "#{session.id}:assistant:#{session.thread.rev}",
      at: at,
      kind: :ai_message,
      payload: %{role: :assistant, content: answer},
      refs: %{request_id: request_id}
    })
  end

  @doc "Returns the visible role and content pairs in append order."
  @spec messages(Session.t()) :: [{atom() | String.t() | nil, term()}]
  def messages(%Session{thread: thread}) do
    thread
    |> Thread.filter_by_kind(:ai_message)
    |> Enum.map(fn entry ->
      {field(entry.payload, :role), field(entry.payload, :content)}
    end)
  end

  @doc "Returns the portable versioned session document."
  @spec export(Session.t()) :: map()
  def export(%Session{} = session), do: Session.encode(session)

  @doc "Validates and restores a portable session document."
  @spec restore(map()) :: {:ok, Session.t()} | {:error, :invalid_session | :unsupported_version}
  def restore(document), do: Session.decode(document)

  defp field(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
