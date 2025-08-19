defmodule AshJido.IntegrationTest do
  @moduledoc """
  Integration tests that demonstrate end-to-end functionality of AshJido.

  These tests verify that:
  1. Ash resources with AshJido extension compile successfully
  2. Jido.Action modules are generated at compile time
  3. Generated modules have correct schemas and functionality
  4. The integration between Ash and Jido works as expected
  """

  use ExUnit.Case, async: false

  @moduletag :capture_log

  alias AshJido.Test.{Domain, User, Post}

  describe "AshJido Integration" do
    test "jido DSL configuration is properly parsed" do
      # Check that Spark parsed the jido DSL sections correctly
      dsl_state = User.spark_dsl_config()
      spark_extensions = Spark.Dsl.Extension.get_persisted(dsl_state, :extensions)
      assert AshJido in spark_extensions

      # Verify jido entities were parsed
      jido_entities = Spark.Dsl.Extension.get_entities(dsl_state, [:jido])

      # action :register, action :by_email, action :read, action :update_age, action :destroy, action :archive, action :deactivate
      assert length(jido_entities) == 7

      # Check specific configurations
      register_action = Enum.find(jido_entities, &(&1.action == :register))
      assert register_action != nil

      by_email_action = Enum.find(jido_entities, &(&1.action == :by_email))
      assert by_email_action != nil
      assert by_email_action.name == "find_user_by_email"
      assert by_email_action.description == "Find a user by their email address"
    end

    test "Jido.Action modules are generated at compile time" do
      # Check that the expected Jido.Action modules were generated
      expected_modules = [
        User.Jido.Register,
        User.Jido.ByEmail,
        User.Jido.Read,
        User.Jido.UpdateAge,
        Post.Jido.Create,
        Post.Jido.Read,
        Post.Jido.Publish
      ]

      for module <- expected_modules do
        assert Code.ensure_loaded?(module), "Expected module #{inspect(module)} to be generated"

        # Verify it's actually a Jido.Action
        assert function_exported?(module, :run, 2), "#{inspect(module)} should implement run/2"
        assert function_exported?(module, :name, 0), "#{inspect(module)} should implement name/0"

        assert function_exported?(module, :schema, 0),
               "#{inspect(module)} should implement schema/0"
      end
    end

    test "generated modules have correct metadata" do
      # Test User.Jido.Register module
      register_module = User.Jido.Register
      # Uses new smart naming
      assert register_module.name() == "create_user"

      schema = register_module.schema()
      assert is_list(schema)

      # Should have the arguments from the Ash action
      schema_keys = Keyword.keys(schema)
      assert :name in schema_keys
      assert :email in schema_keys
      assert :age in schema_keys

      # Test custom named action
      by_email_module = User.Jido.ByEmail
      assert by_email_module.name() == "find_user_by_email"

      # Test Post.Jido.Publish
      publish_module = Post.Jido.Publish
      assert publish_module.name() == "publish_post"
    end

    test "type mapping works correctly" do
      # Test that Ash types are correctly mapped to NimbleOptions types
      register_schema = User.Jido.Register.schema()

      name_spec = Keyword.get(register_schema, :name)
      assert name_spec[:type] == :string
      assert name_spec[:required] == true

      email_spec = Keyword.get(register_schema, :email)
      assert email_spec[:type] == :string
      assert email_spec[:required] == true

      age_spec = Keyword.get(register_schema, :age)
      assert age_spec[:type] == :integer
      # age is optional, so should not have required: true
      refute age_spec[:required]
    end

    test "generated Jido actions can be executed (create)" do
      # Test that we can actually run the generated Jido actions
      params = %{
        name: "John Doe",
        email: "john@example.com",
        age: 30
      }

      context = %{
        actor: nil,
        tenant: nil,
        domain: Domain
      }

      # Execute the register action
      result = User.Jido.Register.run(params, context)

      case result do
        {:ok, user_data} ->
          assert is_map(user_data)
          assert user_data[:name] == "John Doe"
          assert user_data[:email] == "john@example.com"
          assert user_data[:age] == 30
          assert user_data[:id] != nil

        {:error, error} ->
          flunk("Expected successful user creation, got error: #{inspect(error)}")
      end
    end

    test "generated Jido actions handle errors properly" do
      # Test error handling with invalid data
      params = %{
        # Missing required name field
        email: "invalid@example.com"
      }

      context = %{domain: Domain}

      result = User.Jido.Register.run(params, context)

      case result do
        {:error, _error} ->
          # Expected error due to missing required field
          assert true

        {:ok, _} ->
          flunk("Expected error due to missing required field, but got success")
      end
    end

    test "read actions work with generated modules" do
      # First create a user
      create_params = %{
        name: "Jane Doe",
        email: "jane@example.com",
        age: 25
      }

      context = %{domain: Domain}

      {:ok, _user} = User.Jido.Register.run(create_params, context)

      # Now test the read action
      read_result = User.Jido.Read.run(%{}, context)

      case read_result do
        {:ok, users} when is_list(users) ->
          assert length(users) >= 1
          found_user = Enum.find(users, &(&1[:email] == "jane@example.com"))
          assert found_user != nil

        {:error, error} ->
          flunk("Expected successful read, got error: #{inspect(error)}")
      end
    end

    test "custom action names work correctly" do
      # Test the by_email action which has a custom name
      by_email_module = User.Jido.ByEmail
      assert by_email_module.name() == "find_user_by_email"

      # The schema for read actions includes generic query parameters
      # For PoC, read actions use a generic schema, not action-specific arguments
      schema = by_email_module.schema()
      # Generic read parameter
      assert Keyword.has_key?(schema, :id)
      # Generic read parameter
      assert Keyword.has_key?(schema, :limit)
    end

    test "Post resource integration works" do
      # Test that the Post resource also works correctly
      params = %{
        title: "Test Post",
        content: "This is a test post content"
      }

      context = %{domain: Domain}

      # Test regular create
      {:ok, post} = Post.Jido.Create.run(params, context)
      assert post[:title] == "Test Post"
      # Default value
      assert post[:published] == false

      # Test publish action
      publish_params = %{
        title: "Published Post",
        content: "This post is published"
      }

      {:ok, published_post} = Post.Jido.Publish.run(publish_params, context)
      assert published_post[:title] == "Published Post"
      # Set by the publish action
      assert published_post[:published] == true
    end

    test "multiple resources can coexist" do
      # Test that having multiple resources with AshJido doesn't cause conflicts
      user_modules = [
        User.Jido.Register,
        User.Jido.ByEmail,
        User.Jido.Read,
        User.Jido.UpdateAge
      ]

      post_modules = [
        Post.Jido.Create,
        Post.Jido.Read,
        Post.Jido.Publish
      ]

      # All modules should be loadable and distinct
      all_modules = user_modules ++ post_modules

      for module <- all_modules do
        assert Code.ensure_loaded?(module)
        assert function_exported?(module, :name, 0)
        # Each should have a unique name
        name = module.name()
        assert is_binary(name)
        assert String.length(name) > 0
      end

      # Verify names are unique
      names = Enum.map(all_modules, & &1.name())
      assert length(names) == length(Enum.uniq(names))
    end
  end
end
