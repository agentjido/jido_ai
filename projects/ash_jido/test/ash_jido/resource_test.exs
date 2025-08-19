defmodule AshJido.ResourceTest do
  use ExUnit.Case, async: true

  @moduletag :capture_log

  describe "AshJido extension" do
    test "provides jido section" do
      # Check that the DSL section is available
      section = AshJido.Resource.Dsl.jido_section()
      assert section.name == :jido
      # action and all_actions
      assert length(section.entities) == 2
    end

    test "DSL entities are properly configured" do
      section = AshJido.Resource.Dsl.jido_section()

      action_entity = Enum.find(section.entities, &(&1.name == :action))
      assert action_entity != nil
      assert action_entity.target == AshJido.Resource.JidoAction
    end

    test "JidoAction struct has required fields" do
      jido_action = %AshJido.Resource.JidoAction{action: :test}
      assert jido_action.action == :test
      assert jido_action.output_map? == true
      assert jido_action.pagination? == true
    end
  end
end
