defmodule AshJido.Resource.Transformers.GenerateJidoActionsTest do
  @moduledoc """
  Tests for AshJido.Resource.Transformers.GenerateJidoActions.

  Tests the Spark transformer that handles the compilation-time
  generation of Jido.Action modules.
  """

  use ExUnit.Case, async: true

  @moduletag :capture_log

  alias AshJido.Resource.Transformers.GenerateJidoActions

  # Test resource without jido section
  defmodule ResourceWithoutJido do
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets

    ets do
      private?(true)
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:name, :string)
    end

    actions do
      defaults([:read, :create])
    end
  end

  # Test resource with jido section
  defmodule ResourceWithJido do
    use Ash.Resource,
      domain: nil,
      extensions: [AshJido],
      data_layer: Ash.DataLayer.Ets

    ets do
      private?(true)
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:name, :string, allow_nil?: false)
      attribute(:email, :string, allow_nil?: false)
    end

    actions do
      defaults([:read])

      create :register do
        argument(:name, :string, allow_nil?: false)
        argument(:email, :string, allow_nil?: false)

        change(set_attribute(:name, arg(:name)))
        change(set_attribute(:email, arg(:email)))
      end
    end

    jido do
      action(:register)
      action(:read, name: "list_all")
    end
  end

  describe "transform/1" do
    test "returns original DSL state unchanged when no jido section" do
      dsl_state = ResourceWithoutJido.spark_dsl_config()

      result = GenerateJidoActions.transform(dsl_state)

      assert {:ok, returned_state} = result
      assert returned_state == dsl_state

      # Should not persist any generated modules
      generated_modules =
        Spark.Dsl.Extension.get_persisted(returned_state, :generated_jido_modules)

      assert generated_modules == [] or generated_modules == nil
    end

    test "processes jido actions when jido section exists" do
      dsl_state = ResourceWithJido.spark_dsl_config()

      result = GenerateJidoActions.transform(dsl_state)

      assert {:ok, new_state} = result

      # Should persist generated modules list
      generated_modules = Spark.Dsl.Extension.get_persisted(new_state, :generated_jido_modules)
      assert is_list(generated_modules)
      # action :register + action :read
      assert length(generated_modules) == 2

      # Check that modules were actually generated
      for module <- generated_modules do
        assert is_atom(module)
        assert Code.ensure_loaded?(module)
      end
    end

    test "handles empty jido section gracefully" do
      # Create a resource with jido section but no actions
      defmodule ResourceWithEmptyJido do
        use Ash.Resource,
          domain: nil,
          extensions: [AshJido],
          data_layer: Ash.DataLayer.Ets

        ets do
          private?(true)
        end

        attributes do
          uuid_primary_key(:id)
          attribute(:name, :string)
        end

        actions do
          defaults([:read])
        end

        jido do
          # Empty jido section
        end
      end

      dsl_state = ResourceWithEmptyJido.spark_dsl_config()

      result = GenerateJidoActions.transform(dsl_state)

      assert {:ok, new_state} = result

      # Should not generate any modules for empty jido section
      generated_modules = Spark.Dsl.Extension.get_persisted(new_state, :generated_jido_modules)
      assert generated_modules == [] or generated_modules == nil
    end

    # Note: Error propagation is tested via the Generator module tests
  end

  describe "transformer integration" do
    test "transformer is properly called during resource compilation" do
      # This test verifies that the transformer is actually called
      # when a resource with AshJido extension is compiled

      dsl_state = ResourceWithJido.spark_dsl_config()

      # Get the jido entities that should be processed
      jido_entities = Spark.Dsl.Extension.get_entities(dsl_state, [:jido])

      assert length(jido_entities) == 2

      # Verify the entities have the expected structure
      register_entity = Enum.find(jido_entities, &(&1.action == :register))
      assert register_entity != nil
      assert register_entity.__struct__ == AshJido.Resource.JidoAction

      action_entity = Enum.find(jido_entities, &(&1.action == :read))
      assert action_entity != nil
      assert action_entity.name == "list_all"
    end

    test "generated modules are accessible after transformation" do
      dsl_state = ResourceWithJido.spark_dsl_config()

      {:ok, transformed_state} = GenerateJidoActions.transform(dsl_state)

      generated_modules =
        Spark.Dsl.Extension.get_persisted(transformed_state, :generated_jido_modules)

      # Each generated module should be functional
      for module <- generated_modules do
        assert function_exported?(module, :run, 2)
        assert function_exported?(module, :name, 0)
        assert function_exported?(module, :schema, 0)

        # Verify the module name is a string
        name = module.name()
        assert is_binary(name)
        assert String.length(name) > 0

        # Verify the schema is valid
        schema = module.schema()
        assert is_list(schema)
      end
    end
  end

  # Error handling is tested via the Generator module integration
end
