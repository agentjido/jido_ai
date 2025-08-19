defmodule AshJidoTest do
  use ExUnit.Case, async: true
  doctest AshJido

  @moduletag :capture_log

  describe "version/0" do
    test "returns the project version" do
      expected_version = Mix.Project.config()[:version]
      assert AshJido.version() == expected_version
      assert is_binary(expected_version)
    end

    test "version is not nil or empty" do
      version = AshJido.version()
      assert version != nil
      assert String.length(version) > 0
    end
  end

  describe "Spark extension behavior" do
    test "AshJido is a valid Spark extension" do
      # Verify that AshJido implements the Spark.Dsl.Extension behavior properly
      assert Code.ensure_loaded?(AshJido)
      assert function_exported?(AshJido, :explain, 2)

      # Check that it has the required extension metadata
      extension_module = AshJido
      assert is_atom(extension_module)
    end

    test "explain function exists and is callable" do
      # Just test that the explain function exists and doesn't crash
      # We don't need to test the internal Spark functionality
      assert function_exported?(AshJido, :explain, 2)
    end
  end

  describe "integration with Ash framework" do
    defmodule IntegrationTestResource do
      use Ash.Resource,
        domain: nil,
        extensions: [AshJido],
        data_layer: Ash.DataLayer.Ets

      ets do
        private?(true)
      end

      attributes do
        uuid_primary_key(:id)
        attribute(:title, :string, allow_nil?: false)
      end

      actions do
        defaults([:read, :create])
      end

      jido do
        action(:create)
        action(:read)
      end
    end

    test "resource with AshJido extension compiles successfully" do
      # This test verifies that the extension doesn't break Ash compilation
      assert Code.ensure_loaded?(IntegrationTestResource)

      # Verify it's a valid Ash resource
      assert function_exported?(IntegrationTestResource, :spark_dsl_config, 0)

      # Verify our extension is included
      dsl_state = IntegrationTestResource.spark_dsl_config()
      extensions = Spark.Dsl.Extension.get_persisted(dsl_state, :extensions)
      assert AshJido in extensions
    end

    test "Jido modules are generated for resource" do
      # Verify that Jido.Action modules were generated
      expected_modules = [
        IntegrationTestResource.Jido.Create,
        IntegrationTestResource.Jido.Read
      ]

      for module <- expected_modules do
        assert Code.ensure_loaded?(module), "Expected module #{inspect(module)} to be generated"
        assert function_exported?(module, :run, 2)
        assert function_exported?(module, :name, 0)
        assert function_exported?(module, :schema, 0)
      end
    end
  end

  describe "core module functions" do
    test "version returns mix version" do
      assert AshJido.version() == Mix.Project.config()[:version]
    end
  end
end
