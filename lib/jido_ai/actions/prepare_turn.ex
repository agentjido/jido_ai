defmodule Jido.AI.Actions.PrepareTurn do
  @moduledoc """
  Validates the current Agent turn before later Flow steps do work.

  The Action reads the current Signal and Agent state from the execution
  context. It returns the Thread or open Session stored at `:state_key`.
  It does not call a model, change Agent state, or commit a turn.

  The default state key is `:session`. A Flow can select another key through
  normal Action parameters or replace this step with another Action.
  """

  alias Jido.AI.Turn

  @state_key_schema Zoi.atom(description: "Agent state key that owns the turn")
                    |> Zoi.refine({__MODULE__, :valid_state_key, []})

  use Jido.Action,
    name: "jido_ai_prepare_turn",
    description: "Validate one Agent turn before model work",
    schema:
      Zoi.object(%{
        state_key: @state_key_schema |> Zoi.default(:session)
      }),
    output_schema:
      Zoi.object(%{
        state_key: @state_key_schema,
        turn_state:
          Zoi.union([Jido.Thread.schema(), Jido.Session.schema()],
            description: "Validated Thread or open Session value"
          )
      })

  @doc false
  def valid_state_key(key, _opts) when key not in [nil, true, false], do: :ok
  def valid_state_key(_key, _opts), do: {:error, "must be a named Agent state key"}

  @impl Jido.Action
  def run(%{state_key: state_key}, context) do
    Turn.prepare(context, state_key: state_key)
  end
end
