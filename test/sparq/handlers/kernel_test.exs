defmodule Sparq.Handlers.KernelTest do
  use ExUnit.Case, async: true
  alias Sparq.{Context, Handlers.Kernel}

  describe "handle/4" do
    setup do
      ctx = Context.new()
      {:ok, ctx: ctx}
    end

    test "handles is_tuple operation", %{ctx: ctx} do
      {result, _ctx} = Kernel.handle(:is_tuple, %{}, [{:test}], ctx)
      assert result == true
      {result, _ctx} = Kernel.handle(:is_tuple, %{}, [:not_tuple], ctx)
      assert result == false
    end

    test "handles tuple_size operation", %{ctx: ctx} do
      {result, _ctx} = Kernel.handle(:tuple_size, %{}, [{:test, 1, 2}], ctx)
      assert result == 3
    end

    test "handles elem operation", %{ctx: ctx} do
      {result, _ctx} = Kernel.handle(:elem, %{}, [{:test, 1, 2}, 1], ctx)
      assert result == 1
    end

    test "handles put_elem operation", %{ctx: ctx} do
      {result, _ctx} = Kernel.handle(:put_elem, %{}, [{:test, 1, 2}, 1, :new], ctx)
      assert result == {:test, :new, 2}
    end

    test "handles system_time operation", %{ctx: ctx} do
      {result, _ctx} = Kernel.handle(:system_time, %{}, [], ctx)
      assert is_integer(result)

      {result, _ctx} = Kernel.handle(:system_time, %{}, [:nanosecond], ctx)
      assert is_integer(result)
    end

    test "handles monotonic_time operation", %{ctx: ctx} do
      {result, _ctx} = Kernel.handle(:monotonic_time, %{}, [], ctx)
      assert is_integer(result)

      {result, _ctx} = Kernel.handle(:monotonic_time, %{}, [:nanosecond], ctx)
      assert is_integer(result)
    end
  end

  describe "validate/2" do
    test "validates tuple_size with valid tuple" do
      assert :ok = Kernel.validate(:tuple_size, [{:test}])
    end

    test "validates tuple_size with invalid tuple" do
      assert {:error, :tuple} = Kernel.validate(:tuple_size, [:not_tuple])
    end

    test "validates elem with valid arguments" do
      assert :ok = Kernel.validate(:elem, [{:test}, 0])
    end

    test "validates elem with invalid arguments" do
      assert {:error, :index} = Kernel.validate(:elem, [:not_tuple, 0])
      assert {:error, :index} = Kernel.validate(:elem, [{:test}, :not_int])
    end

    test "validates put_elem with valid arguments" do
      assert :ok = Kernel.validate(:put_elem, [{:test}, 0, :new])
    end

    test "validates put_elem with invalid arguments" do
      assert {:error, :index} = Kernel.validate(:put_elem, [:not_tuple, 0, :new])
      assert {:error, :index} = Kernel.validate(:put_elem, [{:test}, :not_int, :new])
    end

    test "validates system_time with valid unit" do
      assert :ok = Kernel.validate(:system_time, [:nanosecond])
    end

    test "validates system_time with invalid unit" do
      assert {:error, :time_unit} = Kernel.validate(:system_time, ["not_unit"])
    end

    test "validates monotonic_time with valid unit" do
      assert :ok = Kernel.validate(:monotonic_time, [:nanosecond])
    end

    test "validates monotonic_time with invalid unit" do
      assert {:error, :time_unit} = Kernel.validate(:monotonic_time, ["not_unit"])
    end

    test "validates unknown operation" do
      assert :ok = Kernel.validate(:unknown, [:any])
    end
  end
end
