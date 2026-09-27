defmodule Jido.AI.Reasoning.ReAct.Worker.EmitEvent do
  @moduledoc false

  @schema Zoi.struct(
            __MODULE__,
            %{
              parent: Zoi.any(),
              signal: Zoi.any()
            }
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)
end

defimpl Jido.AgentServer.DirectiveExec, for: Jido.AI.Reasoning.ReAct.Worker.EmitEvent do
  @moduledoc false

  alias Jido.Tracing.Context, as: TraceContext

  def exec(%{parent: parent, signal: signal}, input_signal, state) do
    signal =
      case TraceContext.propagate_to(signal, input_signal.id) do
        {:ok, traced} -> traced
        {:error, _} -> signal
      end

    # Send from the worker process to preserve event order. The generic Emit
    # executor starts a separate dispatch task for each event. A cast does not
    # wait for the parent to process the signal.
    Jido.AgentServer.cast(parent, signal)
    {:ok, state}
  end
end
