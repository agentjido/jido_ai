# defmodule Jido.Character.PersonalityTest do
#   use ExUnit.Case
#   alias Jido.Character.Personality
#   alias Jido.Character.Personality.{Traits, Narrative, Behavior, Expression}

#   describe "new/1" do
#     test "creates a new personality with default values" do
#       personality = Personality.new()
#       assert %Personality{} = personality
#       assert %Traits{} = personality.traits
#       assert %Narrative{} = personality.narrative
#       assert %Behavior{} = personality.behavior
#       assert %Expression{} = personality.expression
#     end

#     test "creates a personality with custom traits" do
#       traits_opts = %{openness: 75, conscientiousness: 80}
#       personality = Personality.new(traits: traits_opts)

#       assert personality.traits.openness == 75
#       assert personality.traits.conscientiousness == 80
#     end
#   end

#   describe "changeset/2" do
#     test "validates trait ranges" do
#       changeset =
#         Personality.changeset(%Personality{}, %{
#           traits: %{openness: 101}
#         })

#       refute changeset.valid?
#       assert {"is invalid", _} = changeset.changes.traits.errors[:openness]
#     end

#     test "validates expression tone" do
#       changeset =
#         Personality.changeset(%Personality{}, %{
#           expression: %{current_tone: :invalid_tone}
#         })

#       refute changeset.valid?
#       assert {"is invalid", _} = changeset.changes.expression.errors[:current_tone]
#     end
#   end

#   describe "Expression" do
#     test "handles atom filters" do
#       expression = Expression.new(%{active_filters: [:test, :filter]})
#       assert expression.active_filters == ["test", "filter"]
#       assert Expression.get_filters(expression) == [:test, :filter]
#     end

#     test "can add new filters" do
#       expression = Expression.new(%{})
#       updated = Expression.add_filter(expression, :new_filter)
#       assert "new_filter" in updated.active_filters
#     end

#     test "validates filter format" do
#       changeset = Expression.changeset(%Expression{}, %{active_filters: [123]})
#       refute changeset.valid?

#       assert {"is invalid", [type: {:array, :string}, validation: :cast]} =
#                changeset.errors[:active_filters]
#     end

#     test "accepts keyword list for new" do
#       expression = Expression.new(active_filters: [:test])
#       assert expression.active_filters == ["test"]
#     end
#   end
# end
