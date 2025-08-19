defmodule Jido.Character.Evolution.GrowthSystem do
  use TypedEctoSchema
  import Ecto.Changeset

  @derive {Jason.Encoder, except: []}
  @primary_key false
  typed_embedded_schema do
    field(:rules, :map,
      default: %{
        "maturity_thresholds" => %{
          "growing" => 0.25,
          "mature" => 0.75,
          "transcendent" => 0.95
        },
        "knowledge_weight" => 0.4,
        "memory_weight" => 0.3,
        "emotional_weight" => 0.3
      }
    )

    field(:growth_rate, :float, default: 0.1)
    field(:decay_rate, :float, default: 0.05)
  end

  def changeset(growth_system, attrs) do
    growth_system
    |> cast(attrs, [:rules, :growth_rate, :decay_rate])
    |> validate_number(:growth_rate, greater_than: 0, less_than_or_equal_to: 1)
    |> validate_number(:decay_rate, greater_than_or_equal_to: 0, less_than: 1)
    |> validate_rules()
  end

  defp validate_rules(changeset) do
    case get_field(changeset, :rules) do
      %{"maturity_thresholds" => thresholds} = rules when is_map(thresholds) ->
        validate_thresholds(changeset, thresholds, rules)

      _ ->
        add_error(changeset, :rules, "must contain maturity_thresholds")
    end
  end

  defp validate_thresholds(changeset, thresholds, rules) do
    with true <- Map.has_key?(thresholds, "growing"),
         true <- Map.has_key?(thresholds, "mature"),
         true <- Map.has_key?(thresholds, "transcendent"),
         true <- thresholds["growing"] < thresholds["mature"],
         true <- thresholds["mature"] < thresholds["transcendent"],
         true <- all_weights_valid?(rules) do
      changeset
    else
      _ -> add_error(changeset, :rules, "invalid thresholds or weights configuration")
    end
  end

  defp all_weights_valid?(%{
         "knowledge_weight" => k,
         "memory_weight" => m,
         "emotional_weight" => e
       })
       when is_number(k) and is_number(m) and is_number(e) do
    abs(k + m + e - 1.0) < 0.000001
  end

  defp all_weights_valid?(_), do: false
end
