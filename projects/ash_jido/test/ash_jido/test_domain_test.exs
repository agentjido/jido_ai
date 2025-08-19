defmodule AshJido.Test.DomainTest do
  use ExUnit.Case, async: true

  alias AshJido.Test.Domain

  describe "domain functionality" do
    test "includes all test resources" do
      dsl_state = Domain.spark_dsl_config()
      resources = Spark.Dsl.Extension.get_entities(dsl_state, [:resources])

      resource_modules = Enum.map(resources, & &1.resource)

      assert AshJido.Test.User in resource_modules
      assert AshJido.Test.Post in resource_modules
      assert AshJido.Test.CustomModules in resource_modules
    end

    test "__using__ macro works correctly" do
      defmodule TestUsage do
        use AshJido.Test.Domain

        def test_function do
          # This should have access to Domain alias
          Domain
        end
      end

      # Verify the module was created and the alias works
      assert Code.ensure_loaded?(TestUsage)
      assert TestUsage.test_function() == Domain
    end
  end
end
