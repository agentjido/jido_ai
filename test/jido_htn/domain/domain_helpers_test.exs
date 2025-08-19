defmodule JidoTest.HTN.Domain.HelpersTest do
  use ExUnit.Case, async: true

  import Jido.HTN.Domain.Helpers
  @moduletag :capture_log
  describe "merge/1" do
    test "merges changes into a map" do
      original = %{a: 1, b: %{c: 2}}
      changes = %{b: %{d: 3}, e: 4}
      merged = merge(changes).(original)
      assert merged == %{a: 1, b: %{c: 2, d: 3}, e: 4}
    end
  end

  describe "noop/0" do
    test "returns the input unchanged" do
      input = %{a: 1}
      assert noop().(input) == input
    end
  end

  describe "op/3" do
    test "returns an error tuple for undefined workflows" do
      domain = %{allowed_workflows: %{}}

      assert {:error, error_message} = op(domain, "test_op")
      assert error_message =~ "Workflow test_op not allowed in this domain"
    end

    test "returns an ok tuple with a function for defined workflows" do
      mock_module = MockModule
      domain = %{allowed_workflows: %{"test_op" => mock_module}}

      assert {:ok, workflow_func} = op(domain, "test_op")
      assert is_function(workflow_func, 1)
    end
  end

  describe "camel_case/1" do
    test "converts string to camel case" do
      assert camel_case("test_string") == "TestString"
      assert camel_case("already_camel_case") == "AlreadyCamelCase"
    end
  end

  describe "function_to_string/1" do
    test "converts function to string representation" do
      fun = fn -> :ok end
      assert function_to_string(fun) =~ ~r/&.+\/0/
    end
  end
end
