defmodule AshJido.EnhancedGeneratorTest do
  @moduledoc """
  Tests for enhanced generator support of update, destroy, and generic actions.
  """

  use ExUnit.Case, async: true

  @moduletag :capture_log

  describe "Enhanced Action Support" do
    test "generates module for update action with correct schema" do
      dsl_state = AshJido.Test.User.spark_dsl_config()

      jido_action = %AshJido.Resource.JidoAction{
        action: :update_age,
        name: "update_user_age",
        module_name: nil,
        description: "Update user age",
        output_map?: true
      }

      module_name =
        AshJido.Generator.generate_jido_action_module(AshJido.Test.User, jido_action, dsl_state)

      # Check the generated module exists
      assert Code.ensure_loaded?(module_name)

      # Check it has the correct schema (should include id + action arguments)
      schema = module_name.schema()
      schema_keys = Keyword.keys(schema)

      assert :id in schema_keys
      assert :age in schema_keys

      # Check id is required
      id_config = Keyword.get(schema, :id)
      assert id_config[:required] == true
    end

    test "generates module for destroy action with correct schema" do
      dsl_state = AshJido.Test.User.spark_dsl_config()

      jido_action = %AshJido.Resource.JidoAction{
        action: :destroy,
        name: "delete_user",
        module_name: nil,
        description: "Delete a user",
        output_map?: true
      }

      module_name =
        AshJido.Generator.generate_jido_action_module(AshJido.Test.User, jido_action, dsl_state)

      # Check the generated module exists
      assert Code.ensure_loaded?(module_name)

      # Check it has the correct schema (should just have id)
      schema = module_name.schema()
      schema_keys = Keyword.keys(schema)

      assert :id in schema_keys

      # Check id is required
      id_config = Keyword.get(schema, :id)
      assert id_config[:required] == true
    end

    test "generates module for custom destroy action" do
      dsl_state = AshJido.Test.User.spark_dsl_config()

      jido_action = %AshJido.Resource.JidoAction{
        action: :archive,
        name: "archive_user",
        module_name: nil,
        description: "Archive a user",
        output_map?: true
      }

      module_name =
        AshJido.Generator.generate_jido_action_module(AshJido.Test.User, jido_action, dsl_state)

      # Check the generated module exists
      assert Code.ensure_loaded?(module_name)

      # Check it has the correct schema (should just have id for destroy action)
      schema = module_name.schema()
      schema_keys = Keyword.keys(schema)

      assert :id in schema_keys
    end

    test "generates module for generic action with correct schema" do
      dsl_state = AshJido.Test.User.spark_dsl_config()

      jido_action = %AshJido.Resource.JidoAction{
        action: :deactivate,
        name: "deactivate_user",
        module_name: nil,
        description: "Deactivate a user account",
        output_map?: true
      }

      module_name =
        AshJido.Generator.generate_jido_action_module(AshJido.Test.User, jido_action, dsl_state)

      # Check the generated module exists
      assert Code.ensure_loaded?(module_name)

      # Check it has the correct schema (should include action arguments)
      schema = module_name.schema()
      schema_keys = Keyword.keys(schema)

      assert :reason in schema_keys
    end

    test "update action properly handles missing id parameter" do
      dsl_state = AshJido.Test.User.spark_dsl_config()

      jido_action = %AshJido.Resource.JidoAction{
        action: :update_age,
        name: "update_user_age_test",
        module_name: nil,
        description: "Update user age test",
        output_map?: true
      }

      module_name =
        AshJido.Generator.generate_jido_action_module(AshJido.Test.User, jido_action, dsl_state)

      # Running without id should return proper error
      {:error, jido_error} = module_name.run(%{age: 25}, %{domain: AshJido.Test.Domain})
      assert jido_error.message == "Update actions require an 'id' parameter"
    end

    test "destroy action properly handles missing id parameter" do
      dsl_state = AshJido.Test.User.spark_dsl_config()

      jido_action = %AshJido.Resource.JidoAction{
        action: :destroy,
        name: "destroy_user_test",
        module_name: nil,
        description: "Destroy user test",
        output_map?: true
      }

      module_name =
        AshJido.Generator.generate_jido_action_module(AshJido.Test.User, jido_action, dsl_state)

      # Running without id should return proper error
      {:error, jido_error} = module_name.run(%{}, %{domain: AshJido.Test.Domain})
      assert jido_error.message == "Destroy actions require an 'id' parameter"
    end

    test "read action with arguments generates correct schema" do
      dsl_state = AshJido.Test.User.spark_dsl_config()

      jido_action = %AshJido.Resource.JidoAction{
        action: :by_email,
        name: "find_user_by_email",
        module_name: nil,
        description: "Find user by email",
        output_map?: true
      }

      module_name =
        AshJido.Generator.generate_jido_action_module(AshJido.Test.User, jido_action, dsl_state)

      # Check the generated module exists
      assert Code.ensure_loaded?(module_name)

      # Check it has the correct schema (action arguments + read params)
      schema = module_name.schema()
      schema_keys = Keyword.keys(schema)

      # Should have action-specific argument
      assert :email in schema_keys

      # Should also have common read parameters
      assert :id in schema_keys
      assert :limit in schema_keys
      assert :offset in schema_keys
    end
  end
end
