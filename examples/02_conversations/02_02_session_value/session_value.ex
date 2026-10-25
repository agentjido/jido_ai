defmodule JidoAI.Examples.SessionValue.Record do
  @moduledoc "Defines the typed note request and reply contract."

  use Jido.Action,
    name: "session_value_record",
    description: "Record one note in an open Session",
    schema: Zoi.object(%{note: Zoi.string() |> Zoi.min(1)}),
    output_schema: Zoi.object(%{note: Zoi.string() |> Zoi.min(1)})

  @impl Jido.Action
  def run(%{note: note}, _context), do: {:ok, %{note: note}}
end

defmodule JidoAI.Examples.SessionValue.RecordSession do
  @moduledoc "Commits one typed note exchange to Session state."

  alias JidoAI.Examples.SessionValue.Record

  use Jido.Action,
    name: "session_value_record_session",
    description: "Commit one note exchange to Session state",
    schema: Record.schema(),
    output_schema:
      Zoi.object(%{
        state: Zoi.object(%{session: Jido.Session.schema()}),
        reply: Record.output_schema()
      })

  @impl Jido.Action
  def run(%{note: note}, context),
    do:
      Jido.AI.Turn.complete(
        context,
        {JidoAI.Examples.SessionValue.Agent, "examples.session_value.record"},
        %{note: note},
        state_key: :session
      )
end

defmodule JidoAI.Examples.SessionValue.Close do
  @moduledoc "Defines the typed Session close request and reply contract."

  use Jido.Action,
    name: "session_value_close",
    description: "Close the current Session",
    schema: Zoi.object(%{}),
    output_schema: Zoi.object(%{session_id: Zoi.string(), status: Zoi.literal("closed")})

  @impl Jido.Action
  def run(_params, %{agent_state: %{session: session}}),
    do: {:ok, %{session_id: session.id, status: "closed"}}
end

defmodule JidoAI.Examples.SessionValue.CloseSession do
  @moduledoc "Commits the close exchange and closes Session state."

  alias JidoAI.Examples.SessionValue.Close

  use Jido.Action,
    name: "session_value_close_session",
    description: "Commit the close exchange and close Session state",
    schema: Close.schema(),
    output_schema:
      Zoi.object(%{
        state: Zoi.object(%{session: Jido.Session.schema()}),
        reply: Close.output_schema()
      })

  @impl Jido.Action
  def run(_params, %{agent_state: %{session: session}} = context) do
    answer = %{session_id: session.id, status: "closed"}

    with {:ok, %{state: state, reply: reply}} <-
           Jido.AI.Turn.complete(
             context,
             {JidoAI.Examples.SessionValue.Agent, "examples.session_value.close"},
             answer,
             state_key: :session
           ),
         {:ok, session} <- Jido.Session.close(state.session) do
      {:ok, %{state: %{state | session: session}, reply: reply}}
    end
  end
end

defmodule JidoAI.Examples.SessionValue.Agent do
  @moduledoc "A complete Agent that owns and closes one portable Session."

  alias JidoAI.Examples.SessionValue.{Close, CloseSession, Record, RecordSession}

  use Jido.Agent, name: "session_value_example"

  state do
    schema Zoi.object(%{session: Jido.Session.schema()})
  end

  @impl Jido.Agent
  def initialize(state, _context) do
    {:ok,
     Map.put_new_lazy(state, :session, fn ->
       Jido.Session.new!(metadata: %{example: "session_value"})
     end)}
  end

  routes do
    signal_source "/examples/session-value"

    route "examples.session_value.record", RecordSession, as: :record do
      state(from: output(:state))
      reply("examples.session_value.recorded", from: output(:reply))
    end

    route "examples.session_value.close", CloseSession, as: :close do
      state(from: output(:state))
      reply("examples.session_value.closed", from: output(:reply))
    end
  end
end

defmodule JidoAI.Examples.SessionValue do
  @moduledoc "Builds the complete Agent used to teach Session value lifecycle."

  alias JidoAI.Examples.SessionValue.Agent

  @doc "Builds an Agent with a new open Session."
  def new(opts \\ []), do: Agent.instantiate(opts)
end
