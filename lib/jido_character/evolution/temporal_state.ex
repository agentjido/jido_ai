defmodule Jido.Character.Evolution.TemporalState do
  use TypedEctoSchema
  import Ecto.Changeset

  @derive {Jason.Encoder, except: []}
  @primary_key false
  typed_embedded_schema do
    field(:age, :integer, default: 0)
    field(:maturity, :float, default: 0.0)
    field(:stage, :string, default: "initial")
    field(:last_evolved_at, :utc_datetime_usec)
  end

  def changeset(state, attrs) do
    state = if is_map(state) and not is_struct(state), do: struct(__MODULE__, state), else: state

    state
    |> cast(attrs, [:age, :maturity, :stage, :last_evolved_at])
    |> validate_number(:age, greater_than_or_equal_to: 0)
    |> validate_number(:maturity, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
    |> validate_inclusion(:stage, ~w(initial growing mature transcendent))
  end
end
