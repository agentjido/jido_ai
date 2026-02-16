defmodule Jido.AI.Directive.EmitRequestError do
  @moduledoc """
  Directive to immediately emit a request error signal.

  Used when a request cannot be processed (e.g., agent is busy). This ensures
  the caller receives feedback instead of the request being silently dropped.
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              request_id: Zoi.string(description: "Correlation ID for the request"),
              reason: Zoi.atom(description: "Error reason atom (e.g., :busy)"),
              message: Zoi.string(description: "Human-readable error message")
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc false
  def schema, do: @schema

  @doc "Create a new EmitRequestError directive."
  def new!(attrs) when is_map(attrs) do
    case Zoi.parse(@schema, attrs) do
      {:ok, directive} -> directive
      {:error, errors} -> raise "Invalid EmitRequestError: #{inspect(errors)}"
    end
  end
end

defimpl Jido.AgentServer.DirectiveExec, for: Jido.AI.Directive.EmitRequestError do
  @moduledoc """
  Immediately emits a request error signal without spawning a task.

  Used when a request cannot be processed (Issue #3 fix). This ensures
  callers receive feedback when the agent is busy instead of silent drops.
  """

  alias Jido.AI.Signal

  def exec(directive, _input_signal, state) do
    %{
      request_id: request_id,
      reason: reason,
      message: message
    } = directive

    agent_pid = self()

    # Emit the request error synchronously
    signal =
      Signal.RequestError.new!(%{
        request_id: request_id,
        reason: reason,
        message: message
      })

    Jido.AgentServer.cast(agent_pid, signal)

    {:ok, state}
  end
end
