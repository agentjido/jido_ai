defmodule Sparq.Handlers.TypesTest do
  use ExUnit.Case, async: true
  alias Sparq.{Context, Handlers.Types}

  describe "handle/4" do
    setup do
      ctx = Context.new()
      {:ok, ctx: ctx}
    end

    test "handles string operations", %{ctx: ctx} do
      {result, _ctx} = Types.handle(:string, %{}, ["test"], ctx)
      assert result == "test"

      {result, _ctx} = Types.handle(:string_concat, %{}, ["hello", " world"], ctx)
      assert result == "hello world"
    end

    test "handles atom operations", %{ctx: ctx} do
      {result, _ctx} = Types.handle(:atom, %{}, [:test], ctx)
      assert result == :test

      {result, _ctx} = Types.handle(:atom_to_string, %{}, [:test], ctx)
      assert result == "test"
    end

    test "handles list operations", %{ctx: ctx} do
      {result, _ctx} = Types.handle(:cons, %{}, [1, [2, 3]], ctx)
      assert result == [1, 2, 3]

      {result, _ctx} = Types.handle(:head, %{}, [[1, 2, 3]], ctx)
      assert result == 1

      {result, _ctx} = Types.handle(:tail, %{}, [[1, 2, 3]], ctx)
      assert result == [2, 3]

      {result, _ctx} = Types.handle(:empty?, %{}, [[]], ctx)
      assert result == true

      {result, _ctx} = Types.handle(:empty?, %{}, [[1]], ctx)
      assert result == false
    end

    test "handles map operations", %{ctx: ctx} do
      {result, _ctx} = Types.handle(:map_put, %{}, [%{}, :key, "value"], ctx)
      assert result == %{key: "value"}

      {result, _ctx} = Types.handle(:map_get, %{}, [%{key: "value"}, :key], ctx)
      assert result == "value"

      {result, _ctx} = Types.handle(:map_get, %{}, [%{}, :missing], ctx)
      assert is_nil(result)

      {result, _ctx} = Types.handle(:map_delete, %{}, [%{key: "value"}, :key], ctx)
      assert result == %{}
    end

    test "handles boolean operations", %{ctx: ctx} do
      {result, _ctx} = Types.handle(:and, %{}, [true, true], ctx)
      assert result == true

      {result, _ctx} = Types.handle(:and, %{}, [true, false], ctx)
      assert result == false

      {result, _ctx} = Types.handle(:or, %{}, [true, false], ctx)
      assert result == true

      {result, _ctx} = Types.handle(:or, %{}, [false, false], ctx)
      assert result == false

      {result, _ctx} = Types.handle(:not, %{}, [true], ctx)
      assert result == false
    end

    test "handles tuple operations", %{ctx: ctx} do
      {result, _ctx} = Types.handle(:tuple, %{}, [1, 2, 3], ctx)
      assert result == {1, 2, 3}

      {result, _ctx} = Types.handle(:tuple_get, %{}, [{:a, :b, :c}, 1], ctx)
      assert result == :b

      assert_raise ArgumentError, "tuple_get index out of range", fn ->
        Types.handle(:tuple_get, %{}, [{:a}, 1], ctx)
      end
    end

    test "handles type checking", %{ctx: ctx} do
      {result, _ctx} = Types.handle(:type_of, %{}, ["string"], ctx)
      assert result == :string

      {result, _ctx} = Types.handle(:type_of, %{}, [42], ctx)
      assert result == :number

      {result, _ctx} = Types.handle(:type_of, %{}, [true], ctx)
      assert result == :boolean

      {result, _ctx} = Types.handle(:type_of, %{}, [nil], ctx)
      assert is_nil(result)
    end
  end

  describe "validate/2" do
    test "validates string operations" do
      assert :ok = Types.validate(:string, ["test"])
      assert {:error, :invalid_string} = Types.validate(:string, [42])

      assert :ok = Types.validate(:string_concat, ["a", "b"])
      assert {:error, :invalid_arity} = Types.validate(:string_concat, ["a"])
      assert {:error, :invalid_string} = Types.validate(:string_concat, [42, "b"])
      assert {:error, :invalid_string} = Types.validate(:string_concat, ["a", 42])
    end

    test "validates atom operations" do
      assert :ok = Types.validate(:atom, [:test])
      assert {:error, :invalid_atom} = Types.validate(:atom, ["test"])

      assert :ok = Types.validate(:atom_to_string, [:test])
      assert {:error, :invalid_atom} = Types.validate(:atom_to_string, ["test"])
    end

    test "validates list operations" do
      assert :ok = Types.validate(:cons, [1, [2, 3]])
      assert {:error, :invalid_list} = Types.validate(:cons, [1, 2])

      assert :ok = Types.validate(:head, [[1]])
      assert {:error, :empty_list} = Types.validate(:head, [[]])

      assert :ok = Types.validate(:tail, [[1]])
      assert {:error, :empty_list} = Types.validate(:tail, [[]])

      assert :ok = Types.validate(:empty?, [[]])
      assert {:error, :invalid_list} = Types.validate(:empty?, [42])
    end

    test "validates map operations" do
      assert :ok = Types.validate(:map_put, [%{}, :key, "value"])
      assert {:error, :invalid_map} = Types.validate(:map_put, [42, :key, "value"])

      assert :ok = Types.validate(:map_get, [%{}, :key])
      assert {:error, :invalid_map} = Types.validate(:map_get, [42, :key])

      assert :ok = Types.validate(:map_delete, [%{}, :key])
      assert {:error, :invalid_map} = Types.validate(:map_delete, [42, :key])
    end

    test "validates boolean operations" do
      assert :ok = Types.validate(:and, [true, true])
      assert {:error, :invalid_arity} = Types.validate(:and, [true])
      assert {:error, :invalid_boolean} = Types.validate(:and, [42, true])
      assert {:error, :invalid_boolean} = Types.validate(:and, [true, 42])

      assert :ok = Types.validate(:or, [true, false])
      assert {:error, :invalid_arity} = Types.validate(:or, [true])
      assert {:error, :invalid_boolean} = Types.validate(:or, [42, true])
      assert {:error, :invalid_boolean} = Types.validate(:or, [true, 42])

      assert :ok = Types.validate(:not, [true])
      assert {:error, :invalid_arity} = Types.validate(:not, [])
      assert {:error, :invalid_boolean} = Types.validate(:not, [42])
    end

    test "validates tuple operations" do
      assert :ok = Types.validate(:tuple, [1, 2, 3])

      assert :ok = Types.validate(:tuple_get, [{:a}, 0])
      assert {:error, :invalid_tuple_get} = Types.validate(:tuple_get, [42, 0])
      assert {:error, :invalid_tuple_get} = Types.validate(:tuple_get, [{:a}, "0"])

      assert :ok = Types.validate(:tuple_put, [{:a}, 0, :b])
      assert {:error, :invalid_tuple_put} = Types.validate(:tuple_put, [42, 0, :b])
      assert {:error, :invalid_tuple_put} = Types.validate(:tuple_put, [{:a}, "0", :b])
    end
  end
end
