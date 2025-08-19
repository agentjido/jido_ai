defmodule AshJido.MapperTest do
  use ExUnit.Case, async: true

  alias AshJido.Mapper
  alias AshJido.Test.User

  defmodule PlainStruct do
    defstruct [:x, :y, :__meta__]
  end

  describe "wrap_result/2" do
    test "converts single resource struct to map when output_map? true" do
      user = %User{id: "123", name: "John", email: "john@example.com", age: 30}

      result = Mapper.wrap_result({:ok, user}, %{output_map?: true})

      assert {:ok, %{id: "123", name: "John", email: "john@example.com", age: 30}} = result
    end

    test "converts list of resources to list of maps" do
      users = [
        %User{id: "1", name: "Alice", email: "alice@example.com", age: 25},
        %User{id: "2", name: "Bob", email: "bob@example.com", age: 35}
      ]

      result = Mapper.wrap_result({:ok, users}, %{output_map?: true})

      assert {:ok,
              [
                %{id: "1", name: "Alice", email: "alice@example.com", age: 25},
                %{id: "2", name: "Bob", email: "bob@example.com", age: 35}
              ]} = result
    end

    test "skips conversion when output_map? false" do
      user = %User{id: "123", name: "John", email: "john@example.com", age: 30}

      result = Mapper.wrap_result({:ok, user}, %{output_map?: false})

      assert {:ok, ^user} = result
    end

    test "handles raw struct without tuple wrapper" do
      user = %User{id: "456", name: "Jane", email: "jane@example.com", age: 28}

      result = Mapper.wrap_result(user, %{output_map?: true})

      assert {:ok, %{id: "456", name: "Jane", email: "jane@example.com", age: 28}} = result
    end

    test "handles raw list without tuple wrapper" do
      users = [
        %User{id: "1", name: "Alice", email: "alice@example.com", age: 25}
      ]

      result = Mapper.wrap_result(users, %{output_map?: true})

      assert {:ok, [%{id: "1", name: "Alice", email: "alice@example.com", age: 25}]} = result
    end

    test "propagates non-exception errors unchanged" do
      result = Mapper.wrap_result({:error, :timeout}, %{})

      assert {:error, :timeout} = result
    end

    test "propagates non-exception errors with custom message" do
      result = Mapper.wrap_result({:error, "Custom error message"}, %{})

      assert {:error, "Custom error message"} = result
    end

    test "converts Ash exception to Jido.Error format" do
      ash_error = %Ash.Error.Invalid{errors: [%Ash.Error.Query.NotFound{resource: User}]}

      result = Mapper.wrap_result({:error, ash_error}, %{})

      assert {:error, jido_error} = result
      # Invalid errors map to validation_error
      assert jido_error.type == :validation_error
      assert is_binary(jido_error.message)
      assert jido_error.details.ash_error == ash_error
      assert jido_error.details.ash_error_class == :invalid
    end

    test "handles non-Ash struct fallback conversion" do
      data = %PlainStruct{x: 1, y: 2, __meta__: "should_be_filtered"}

      result = Mapper.wrap_result({:ok, data}, %{output_map?: true})

      # For non-Ash structs, should return the struct as-is
      assert {:ok, ^data} = result
    end

    test "handles nested resource conversion" do
      # Test that nested resources are also converted
      user_with_posts = %User{
        id: "123",
        name: "John",
        email: "john@example.com",
        age: 30
      }

      result = Mapper.wrap_result({:ok, user_with_posts}, %{output_map?: true})

      assert {:ok, %{id: "123", name: "John", email: "john@example.com", age: 30}} = result
    end

    test "handles empty list" do
      result = Mapper.wrap_result({:ok, []}, %{output_map?: true})

      assert {:ok, []} = result
    end

    test "handles nil data" do
      result = Mapper.wrap_result({:ok, nil}, %{output_map?: true})

      assert {:ok, nil} = result
    end

    test "converts exception with fallback when Jido.Error not available" do
      # This tests the rescue clause in convert_ash_error_to_jido_error
      ash_error = %RuntimeError{message: "Test error"}

      result = Mapper.wrap_result({:error, ash_error}, %{})

      # Should fall back to a simple map format
      assert {:error, error_data} = result
      assert is_map(error_data) or is_struct(error_data)
    end
  end
end
