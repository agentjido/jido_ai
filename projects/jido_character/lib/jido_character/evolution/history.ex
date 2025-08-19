defmodule Jido.Character.Evolution.History do
  use TypedEctoSchema
  import Ecto.Changeset

  @derive {Jason.Encoder, except: []}
  @primary_key false
  typed_embedded_schema do
    field(:event_type, :string)
    field(:description, :string)
    field(:timestamp, :utc_datetime_usec)
    field(:previous_state, :map)
    field(:new_state, :map)
    field(:metadata, :map, default: %{})
  end

  @event_types ~w(age_increment maturity_increase stage_transition maturity_decay cognitive_growth)

  def changeset(history, attrs) do
    history
    |> cast(attrs, [:event_type, :description, :timestamp, :previous_state, :new_state, :metadata])
    |> validate_required([:event_type, :description, :timestamp])
    |> validate_inclusion(:event_type, @event_types)
    |> validate_metadata()
  end

  defp validate_metadata(changeset) do
    case get_field(changeset, :event_type) do
      "age_increment" ->
        validate_age_metadata(changeset)

      "maturity_increase" ->
        validate_maturity_metadata(changeset)

      "stage_transition" ->
        validate_stage_metadata(changeset)

      "maturity_decay" ->
        validate_decay_metadata(changeset)

      "cognitive_growth" ->
        validate_growth_metadata(changeset)

      _ ->
        changeset
    end
  end

  defp validate_age_metadata(changeset) do
    changeset
    |> validate_state_fields(:age)
    |> validate_metadata_field(:amount, :integer)
  end

  defp validate_maturity_metadata(changeset) do
    changeset
    |> validate_state_fields(:maturity)
    |> validate_metadata_field(:amount, :float)
  end

  defp validate_stage_metadata(changeset) do
    changeset
    |> validate_state_fields(:stage)
    |> validate_metadata_field(:from_stage, :string)
    |> validate_metadata_field(:to_stage, :string)
  end

  defp validate_decay_metadata(changeset) do
    changeset
    |> validate_state_fields(:maturity)
    |> validate_metadata_field(:amount, :float)
  end

  defp validate_growth_metadata(changeset) do
    changeset
    |> validate_state_fields(:maturity)
    |> validate_metadata_field(:amount, :float)
    |> validate_metadata_field(:factor_weights, :map)
  end

  defp validate_state_fields(changeset, field) do
    previous_state = get_field(changeset, :previous_state) || %{}
    new_state = get_field(changeset, :new_state) || %{}

    cond do
      not is_map(previous_state) ->
        add_error(changeset, :previous_state, "must be a map")

      not is_map(new_state) ->
        add_error(changeset, :new_state, "must be a map")

      not Map.has_key?(previous_state, field) ->
        add_error(changeset, :previous_state, "must contain #{field}")

      not Map.has_key?(new_state, field) ->
        add_error(changeset, :new_state, "must contain #{field}")

      true ->
        changeset
    end
  end

  defp validate_metadata_field(changeset, field, type) do
    metadata = get_field(changeset, :metadata) || %{}

    cond do
      not is_map(metadata) ->
        add_error(changeset, :metadata, "must be a map")

      not Map.has_key?(metadata, field) ->
        add_error(changeset, :metadata, "must contain #{field}")

      type == :float and not is_float(metadata[field]) ->
        add_error(changeset, :metadata, "#{field} must be a float")

      type == :integer and not is_integer(metadata[field]) ->
        add_error(changeset, :metadata, "#{field} must be an integer")

      type == :string and not is_binary(metadata[field]) ->
        add_error(changeset, :metadata, "#{field} must be a string")

      type == :map and not is_map(metadata[field]) ->
        add_error(changeset, :metadata, "#{field} must be a map")

      true ->
        changeset
    end
  end
end
