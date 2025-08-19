defmodule AshJido.TypeMapperTest do
  @moduledoc """
  Tests for AshJido.TypeMapper module.

  Tests the conversion of Ash types to NimbleOptions types,
  which is critical for generating correct parameter schemas.
  """

  use ExUnit.Case, async: true

  @moduletag :capture_log

  alias AshJido.TypeMapper

  describe "ash_type_to_nimble_options/2" do
    test "maps primitive scalar types correctly" do
      # String type
      result = TypeMapper.ash_type_to_nimble_options(Ash.Type.String, %{allow_nil?: false})
      assert result[:type] == :string
      assert result[:required] == true

      result = TypeMapper.ash_type_to_nimble_options(Ash.Type.String, %{allow_nil?: true})
      assert result[:type] == :string
      refute Keyword.has_key?(result, :required)

      # Integer type
      result = TypeMapper.ash_type_to_nimble_options(Ash.Type.Integer, %{allow_nil?: false})
      assert result[:type] == :integer
      assert result[:required] == true

      result = TypeMapper.ash_type_to_nimble_options(Ash.Type.Integer, %{allow_nil?: true})
      assert result[:type] == :integer
      refute Keyword.has_key?(result, :required)

      # Float type
      result = TypeMapper.ash_type_to_nimble_options(Ash.Type.Float, %{allow_nil?: false})
      assert result[:type] == :float
      assert result[:required] == true

      # Boolean type
      result = TypeMapper.ash_type_to_nimble_options(Ash.Type.Boolean, %{})
      assert result[:type] == :boolean

      # UUID type
      result = TypeMapper.ash_type_to_nimble_options(Ash.Type.UUID, %{})
      assert result[:type] == :string
    end

    test "maps date and time types to string" do
      result = TypeMapper.ash_type_to_nimble_options(Ash.Type.Date, %{})
      assert result[:type] == :string

      result = TypeMapper.ash_type_to_nimble_options(Ash.Type.DateTime, %{})
      assert result[:type] == :string

      result = TypeMapper.ash_type_to_nimble_options(Ash.Type.Time, %{})
      assert result[:type] == :string

      # UtcDateTime falls through to default case (not explicitly handled)
      result = TypeMapper.ash_type_to_nimble_options(Ash.Type.UtcDateTime, %{})
      assert result[:type] == :map
    end

    test "maps decimal to float" do
      result = TypeMapper.ash_type_to_nimble_options(Ash.Type.Decimal, %{})
      assert result[:type] == :float

      result = TypeMapper.ash_type_to_nimble_options(Ash.Type.Decimal, %{allow_nil?: false})
      assert result[:type] == :float
      assert result[:required] == true
    end

    test "maps array types recursively" do
      # Array of strings
      result = TypeMapper.ash_type_to_nimble_options({:array, Ash.Type.String}, %{})
      assert result[:type] == {:list, :string}

      # Array of integers
      result =
        TypeMapper.ash_type_to_nimble_options({:array, Ash.Type.Integer}, %{allow_nil?: false})

      assert result[:type] == {:list, :integer}
      assert result[:required] == true

      # Array of floats
      result = TypeMapper.ash_type_to_nimble_options({:array, Ash.Type.Float}, %{})
      assert result[:type] == {:list, :float}
    end

    test "unknown types fallback to map" do
      result = TypeMapper.ash_type_to_nimble_options(:unknown_type, %{})
      assert result[:type] == :map

      result = TypeMapper.ash_type_to_nimble_options(SomeCustomType, %{})
      assert result[:type] == :map
    end

    test "uses storage_type for custom types" do
      # Create a custom type that has a storage_type returning Ash.Type.String
      defmodule CustomStringType do
        @behaviour Ash.Type

        def storage_type, do: Ash.Type.String
        def cast_input(value, _), do: {:ok, value}
        def cast_stored(value, _), do: {:ok, value}
        def dump_to_embedded(value, _), do: {:ok, value}
        def dump_to_native(value, _), do: {:ok, value}
      end

      result = TypeMapper.ash_type_to_nimble_options(CustomStringType, %{})
      assert result[:type] == :string
    end

    test "includes description when provided" do
      options = %{description: "User's age in years"}

      result = TypeMapper.ash_type_to_nimble_options(Ash.Type.Integer, options)
      assert result[:type] == :integer
      assert result[:doc] == "User's age in years - Numeric value"
    end

    test "includes default when provided" do
      options = %{default: 18}

      result = TypeMapper.ash_type_to_nimble_options(Ash.Type.Integer, options)
      assert result[:type] == :integer
      assert result[:default] == 18
    end

    test "combines all options correctly" do
      options = %{
        allow_nil?: false,
        description: "User's age in years",
        default: 18
      }

      result = TypeMapper.ash_type_to_nimble_options(Ash.Type.Integer, options)

      assert result[:type] == :integer
      assert result[:required] == true
      assert result[:doc] == "User's age in years - Numeric value - (required)"
      assert result[:default] == 18
    end

    test "handles empty options map" do
      assert TypeMapper.ash_type_to_nimble_options(Ash.Type.String, %{}) ==
               [type: :string]
    end

    test "nil allow_nil? is treated as allowing nil" do
      options = %{allow_nil?: nil}

      assert TypeMapper.ash_type_to_nimble_options(Ash.Type.String, options) ==
               [type: :string]
    end
  end

  describe "edge cases and complex scenarios" do
    test "nested array types" do
      # This tests how we handle complex nested structures
      nested_array = {:array, {:array, Ash.Type.String}}

      result = TypeMapper.ash_type_to_nimble_options(nested_array, %{})

      # Should handle nested arrays gracefully
      assert result[:type] == {:list, {:list, :string}}
    end

    test "all option combinations" do
      options = %{
        allow_nil?: false,
        description: "Complex field",
        default: "default_value"
      }

      result = TypeMapper.ash_type_to_nimble_options(Ash.Type.String, options)

      # Should include all provided options
      assert Keyword.get(result, :type) == :string
      assert Keyword.get(result, :required) == true
      assert Keyword.get(result, :doc) == "Complex field - Text input - (required)"
      assert Keyword.get(result, :default) == "default_value"
    end
  end
end
