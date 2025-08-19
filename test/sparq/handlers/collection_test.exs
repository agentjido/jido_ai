defmodule Sparq.Handlers.CollectionTest do
  use ExUnit.Case, async: true
  alias Sparq.{Context, Handlers.Collection}

  describe "handle/4" do
    setup do
      ctx = Context.new()
      {:ok, ctx: ctx}
    end

    test "list_map with anonymous function", %{ctx: ctx} do
      fun = fn x -> x * 2 end
      {result, _ctx} = Collection.handle(:list_map, %{}, [fun, [1, 2, 3]], ctx)
      assert result == [2, 4, 6]
    end

    test "list_filter to keep even", %{ctx: ctx} do
      fun = fn x -> rem(x, 2) == 0 end
      {result, _ctx} = Collection.handle(:list_filter, %{}, [fun, [1, 2, 3, 4, 5]], ctx)
      assert result == [2, 4]
    end

    test "list_reduce sum", %{ctx: ctx} do
      fun = fn elem, acc -> elem + acc end
      {result, _ctx} = Collection.handle(:list_reduce, %{}, [fun, 0, [5, 5, 10]], ctx)
      assert result == 20
    end

    test "handle/4 map_keys", %{ctx: ctx} do
      map = %{a: 1, b: 2}
      {result, _ctx} = Collection.handle(:map_keys, %{}, [map], ctx)
      assert MapSet.new(result) == MapSet.new([:a, :b])
    end

    test "handle/4 map_values", %{ctx: ctx} do
      map = %{a: 1, b: 2}
      {result, _ctx} = Collection.handle(:map_values, %{}, [map], ctx)
      assert MapSet.new(result) == MapSet.new([1, 2])
    end

    test "raises on unknown operation", %{ctx: ctx} do
      assert_raise ArgumentError, ~r/Unknown collection operation/, fn ->
        Collection.handle(:unknown, %{}, [], ctx)
      end
    end
  end

  describe "validate/2" do
    test "validates list_map arguments" do
      assert :ok = Collection.validate(:list_map, [fn x -> x end, []])

      assert {:error, :invalid_function_arity} =
               Collection.validate(:list_map, [fn _, _ -> nil end, []])

      assert {:error, :invalid_list} = Collection.validate(:list_map, [fn x -> x end, nil])
    end

    test "validates list_filter arguments" do
      assert :ok = Collection.validate(:list_filter, [fn x -> x end, []])

      assert {:error, :invalid_function_arity} =
               Collection.validate(:list_filter, [fn _, _ -> nil end, []])

      assert {:error, :invalid_list} = Collection.validate(:list_filter, [fn x -> x end, nil])
    end

    test "validates list_reduce arguments" do
      assert :ok = Collection.validate(:list_reduce, [fn x, y -> x + y end, 0, []])

      assert {:error, :invalid_function_arity} =
               Collection.validate(:list_reduce, [fn x -> x end, 0, []])

      assert {:error, :invalid_list} =
               Collection.validate(:list_reduce, [fn x, y -> x + y end, 0, nil])
    end

    test "validates map_keys arguments" do
      assert :ok = Collection.validate(:map_keys, [%{}])
      assert {:error, :invalid_map} = Collection.validate(:map_keys, [nil])
    end

    test "validates map_values arguments" do
      assert :ok = Collection.validate(:map_values, [%{}])
      assert {:error, :invalid_map} = Collection.validate(:map_values, [nil])
    end
  end
end
