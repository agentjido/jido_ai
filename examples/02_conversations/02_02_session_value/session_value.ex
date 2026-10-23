defmodule JidoAI.Examples.SessionValue.Record do
  @moduledoc "Defines the typed note request and reply contract."

  use Jido.SignalAction,
    name: "session_value_record",
    description: "Record one note in an open Session",
    vsn: 1,
    input: [
      type: "examples.session_value.record",
      default_source: "/examples/session-value/client",
      schema: Zoi.object(%{note: Zoi.string() |> Zoi.min(1)})
    ],
    output: [
      type: "examples.session_value.recorded",
      default_source: "/examples/session-value",
      schema: Zoi.object(%{note: Zoi.string() |> Zoi.min(1)})
    ]

  @impl Jido.Action
  def run(%{note: note}, _context), do: {:ok, %{note: note}}
end

defmodule JidoAI.Examples.SessionValue.RecordSession do
  @moduledoc "Commits one typed note exchange to Session state."

  alias Jido.Agent.Directive
  alias JidoAI.Examples.SessionValue.Record

  use Jido.Action,
    name: "session_value_record_session",
    description: "Commit one note exchange to Session state",
    schema: Record.schema()

  @impl Jido.Action
  def run(%{note: note}, %{agent_state: %{session: session} = state, signal: request}) do
    with {:ok, reply} <- Record.reply(request, %{note: note}),
         {:ok, session} <- Jido.Session.append_many(session, [request, reply]) do
      {:ok, %{state | session: session}, [Directive.reply(reply)]}
    end
  end
end

defmodule JidoAI.Examples.SessionValue.Close do
  @moduledoc "Defines the typed Session close request and reply contract."

  use Jido.SignalAction,
    name: "session_value_close",
    description: "Close the current Session",
    vsn: 1,
    input: [
      type: "examples.session_value.close",
      default_source: "/examples/session-value/client",
      schema: Zoi.object(%{})
    ],
    output: [
      type: "examples.session_value.closed",
      default_source: "/examples/session-value",
      schema: Zoi.object(%{session_id: Zoi.string(), status: Zoi.literal("closed")})
    ]

  @impl Jido.Action
  def run(_params, %{agent_state: %{session: session}}),
    do: {:ok, %{session_id: session.id, status: "closed"}}
end

defmodule JidoAI.Examples.SessionValue.CloseSession do
  @moduledoc "Commits the close exchange and closes Session state."

  alias Jido.Agent.Directive
  alias JidoAI.Examples.SessionValue.Close

  use Jido.Action,
    name: "session_value_close_session",
    description: "Commit the close exchange and close Session state",
    schema: Close.schema()

  @impl Jido.Action
  def run(_params, %{agent_state: %{session: session} = state, signal: request}) do
    with {:ok, reply} <- Close.reply(request, %{session_id: session.id, status: "closed"}),
         {:ok, session} <- Jido.Session.append_many(session, [request, reply]),
         {:ok, session} <- Jido.Session.close(session) do
      {:ok, %{state | session: session}, [Directive.reply(reply)]}
    end
  end
end

defmodule JidoAI.Examples.SessionValue.Agent do
  @moduledoc "A complete Agent that owns and closes one portable Session."

  alias JidoAI.Examples.SessionValue.{Close, CloseSession, Record, RecordSession}

  use Jido.Agent, name: "session_value_example"

  agent do
    schema Zoi.object(%{session: Jido.Session.schema()})
  end

  routes do
    signal_source "/examples/session-value"

    route Record, RecordSession, as: :record
    route Close, CloseSession, as: :close
  end
end

defmodule JidoAI.Examples.SessionValue do
  @moduledoc "Builds the complete Agent used to teach Session value lifecycle."

  alias JidoAI.Examples.SessionValue.Agent

  @doc "Builds an Agent with a new open Session."
  def new(opts \\ []) do
    definition = Agent.definition()

    initial_state =
      Map.put(
        definition.initial_state,
        :session,
        Jido.Session.new!(metadata: %{example: "session_value"})
      )

    Jido.Agent.instantiate(%{definition | initial_state: initial_state}, opts)
  end
end
