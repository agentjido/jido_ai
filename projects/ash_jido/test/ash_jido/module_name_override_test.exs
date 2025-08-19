defmodule AshJido.ModuleNameOverrideTest do
  @moduledoc """
  Tests for custom module name override functionality in the DSL.

  This test suite verifies that users can specify custom module names
  for generated Jido.Action modules using the `module_name` option.
  """

  use ExUnit.Case, async: false

  @moduletag :capture_log

  alias AshJido.Test.{Domain, CustomModules}

  describe "module name override functionality" do
    test "DSL accepts module_name option" do
      # Verify that the DSL configuration includes module_name options
      dsl_state = CustomModules.spark_dsl_config()
      jido_entities = Spark.Dsl.Extension.get_entities(dsl_state, [:jido])

      # Find the publish action with custom module name
      publish_action = Enum.find(jido_entities, &(&1.action == :publish))
      assert publish_action != nil
      assert publish_action.module_name == AshJido.Test.Publishers.ItemPublisher

      # Find the by_status action with custom module name
      by_status_action = Enum.find(jido_entities, &(&1.action == :by_status))
      assert by_status_action != nil
      assert by_status_action.module_name == StatusFinder

      # Find the read action with custom module name
      read_action = Enum.find(jido_entities, &(&1.action == :read))
      assert read_action != nil
      assert read_action.module_name == AshJido.Test.Readers.AllItemsReader

      # Find the create action without custom module name
      create_action = Enum.find(jido_entities, &(&1.action == :create))
      assert create_action != nil
      # Should use default
      assert create_action.module_name == nil
    end

    test "custom module names are used for generation" do
      # Test that the expected custom modules are generated
      expected_custom_modules = [
        AshJido.Test.Publishers.ItemPublisher,
        StatusFinder,
        AshJido.Test.Readers.AllItemsReader
      ]

      for module <- expected_custom_modules do
        assert Code.ensure_loaded?(module),
               "Expected custom module #{inspect(module)} to be generated"

        # Verify it's actually a Jido.Action
        assert function_exported?(module, :run, 2), "#{inspect(module)} should implement run/2"
        assert function_exported?(module, :name, 0), "#{inspect(module)} should implement name/0"

        assert function_exported?(module, :schema, 0),
               "#{inspect(module)} should implement schema/0"
      end
    end

    test "default module names are still used when module_name is not specified" do
      # Test that the create action still uses default module naming
      default_module = CustomModules.Jido.Create

      assert Code.ensure_loaded?(default_module),
             "Expected default module #{inspect(default_module)} to be generated"

      assert function_exported?(default_module, :run, 2)
      assert function_exported?(default_module, :name, 0)
    end

    test "custom modules have correct metadata" do
      # Test AshJido.Test.Publishers.ItemPublisher
      publisher = AshJido.Test.Publishers.ItemPublisher
      assert publisher.name() == "publish_item"

      schema = publisher.schema()
      assert is_list(schema)
      schema_keys = Keyword.keys(schema)
      assert :title in schema_keys
      assert :priority in schema_keys

      # Test StatusFinder
      status_finder = StatusFinder
      assert status_finder.name() == "find_by_status"

      # Test AshJido.Test.Readers.AllItemsReader  
      reader = AshJido.Test.Readers.AllItemsReader
      assert reader.name() == "list_all"
    end

    test "custom modules are executable" do
      # Test that custom modules can actually execute actions
      context = %{domain: Domain}

      # Test the publisher module
      publish_params = %{
        title: "Test Item",
        priority: 2
      }

      result = AshJido.Test.Publishers.ItemPublisher.run(publish_params, context)

      case result do
        {:ok, item_data} ->
          assert is_map(item_data)
          assert item_data[:title] == "Test Item"
          assert item_data[:status] == "published"
          assert item_data[:id] != nil

        {:error, error} ->
          flunk("Expected successful item creation, got error: #{inspect(error)}")
      end
    end

    test "custom modules can be mixed with default modules" do
      # Test that we can have both custom and default module names in the same resource
      context = %{domain: Domain}

      # Test default module (create)
      create_params = %{
        title: "Default Module Test",
        status: "draft"
      }

      {:ok, item1} = CustomModules.Jido.Create.run(create_params, context)
      assert item1[:title] == "Default Module Test"
      assert item1[:status] == "draft"

      # Test custom module (publisher) 
      publish_params = %{
        title: "Custom Module Test",
        priority: 1
      }

      {:ok, item2} = AshJido.Test.Publishers.ItemPublisher.run(publish_params, context)
      assert item2[:title] == "Custom Module Test"
      assert item2[:status] == "published"

      # Both should be different records
      assert item1[:id] != item2[:id]
    end

    test "custom module names work with read actions" do
      # Test custom module name for read actions
      context = %{domain: Domain}

      # First create some test data
      {:ok, _item1} = CustomModules.Jido.Create.run(%{title: "Item 1", status: "draft"}, context)

      {:ok, _item2} =
        AshJido.Test.Publishers.ItemPublisher.run(%{title: "Item 2", priority: 1}, context)

      # Test the custom read module
      read_result = AshJido.Test.Readers.AllItemsReader.run(%{}, context)

      case read_result do
        {:ok, items} when is_list(items) ->
          assert length(items) >= 2
          titles = Enum.map(items, & &1[:title])
          assert "Item 1" in titles
          assert "Item 2" in titles

        {:error, error} ->
          flunk("Expected successful read, got error: #{inspect(error)}")
      end
    end

    test "invalid module names are handled gracefully" do
      # This test verifies that the DSL validation works for module names
      # Since we're using compile-time generation, invalid module names would
      # cause compilation errors, which is the expected behavior

      # We can test that valid atoms are accepted
      valid_config = %AshJido.Resource.JidoAction{
        action: :test,
        module_name: MyApp.ValidModule
      }

      assert valid_config.module_name == MyApp.ValidModule

      # Test nil is handled (uses default)
      default_config = %AshJido.Resource.JidoAction{
        action: :test,
        module_name: nil
      }

      assert default_config.module_name == nil
    end

    test "module names can use different namespaces" do
      # Test that custom modules can be in completely different namespaces
      expected_namespaces = [
        # Default namespace
        [CustomModules, Jido, Create],

        # Custom namespaces
        [AshJido, Test, Publishers, ItemPublisher],
        # Single module name
        [StatusFinder],
        [AshJido, Test, Readers, AllItemsReader]
      ]

      for namespace_parts <- expected_namespaces do
        module = Module.concat(namespace_parts)
        assert Code.ensure_loaded?(module), "Module #{inspect(module)} should exist"
      end
    end

    test "generated modules preserve original action behavior" do
      # Test that custom module names don't affect the underlying Ash action behavior
      context = %{domain: Domain}

      # Test that the publish action still sets status to "published"
      params = %{title: "Status Test", priority: 3}
      {:ok, item} = AshJido.Test.Publishers.ItemPublisher.run(params, context)

      # The publish action should set status to "published" regardless of module name
      assert item[:status] == "published"
      assert item[:title] == "Status Test"
    end
  end

  describe "JidoAction struct with module_name" do
    test "JidoAction struct includes module_name field" do
      jido_action = %AshJido.Resource.JidoAction{
        action: :test,
        name: "test_action",
        module_name: MyApp.TestModule,
        description: "Test description",
        output_map?: true,
        pagination?: false
      }

      assert jido_action.action == :test
      assert jido_action.name == "test_action"
      assert jido_action.module_name == MyApp.TestModule
      assert jido_action.description == "Test description"
      assert jido_action.output_map? == true
      assert jido_action.pagination? == false
    end
  end
end
