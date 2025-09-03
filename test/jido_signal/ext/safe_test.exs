defmodule Jido.Signal.Ext.SafeTest do
  use ExUnit.Case, async: true

  alias Jido.Signal.Ext

  defmodule CrashingExtension do
    @moduledoc false

    def validate_data(_data) do
      raise "Boom! Extension crashed"
    end

    def to_attrs(_data) do
      throw(:oops)
    end

    def from_attrs(_attrs) do
      exit(:normal)
    end
  end

  defmodule WorkingExtension do
    @moduledoc false

    def validate_data(data) do
      {:ok, data}
    end

    def to_attrs(data) do
      [{"test_key", data.value}]
    end

    def from_attrs(attrs) do
      Map.get(attrs, "test_key", nil)
    end
  end

  test "successfully calls extension callbacks" do
    data = %{value: "test"}

    assert {:ok, {:ok, %{value: "test"}}} =
             Ext.safe_validate_data(WorkingExtension, data)

    assert {:ok, [{"test_key", "test"}]} =
             Ext.safe_to_attrs(WorkingExtension, data)

    attrs = %{"test_key" => "test", "other" => "value"}

    assert {:ok, "test"} =
             Ext.safe_from_attrs(WorkingExtension, attrs)
  end

  test "catches and logs exceptions from validate_data" do
    import ExUnit.CaptureLog

    log =
      capture_log(fn ->
        assert {:error, %RuntimeError{message: "Boom! Extension crashed"}} =
                 Ext.safe_validate_data(CrashingExtension, %{})
      end)

    assert log =~ "crashed: Boom! Extension crashed"
  end

  test "catches and logs throws from to_attrs" do
    import ExUnit.CaptureLog

    log =
      capture_log(fn ->
        assert {:error, :oops} =
                 Ext.safe_to_attrs(CrashingExtension, %{})
      end)

    assert log =~ "threw: :oops"
  end

  test "catches and logs exits from from_attrs" do
    import ExUnit.CaptureLog

    log =
      capture_log(fn ->
        assert {:error, :normal} =
                 Ext.safe_from_attrs(CrashingExtension, %{})
      end)

    assert log =~ "exited: :normal"
  end
end
