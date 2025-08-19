defmodule Depot.VisibilityTest do
  use ExUnit.Case, async: true

  alias Depot.Visibility

  describe "portable?/1" do
    test "returns true for :public" do
      assert Visibility.portable?(:public) == true
    end

    test "returns true for :private" do
      assert Visibility.portable?(:private) == true
    end

    test "returns false for non-portable values" do
      assert Visibility.portable?(:custom) == false
      assert Visibility.portable?("public") == false
      assert Visibility.portable?(nil) == false
      assert Visibility.portable?(123) == false
      assert Visibility.portable?({:custom, :value}) == false
    end
  end

  describe "guard_portable/1" do
    test "returns {:ok, visibility} for portable values" do
      assert Visibility.guard_portable(:public) == {:ok, :public}
      assert Visibility.guard_portable(:private) == {:ok, :private}
    end

    test "returns :error for non-portable values" do
      assert Visibility.guard_portable(:custom) == :error
      assert Visibility.guard_portable("public") == :error
      assert Visibility.guard_portable(nil) == :error
      assert Visibility.guard_portable(123) == :error
      assert Visibility.guard_portable({:custom, :value}) == :error
    end
  end
end
