defmodule Jido.AI.Signal.HelpersTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Signal.Helpers

  describe "normalize_result/3" do
    test "passes through ok and error tuples and wraps invalid values" do
      assert Helpers.normalize_result({:ok, 1}) == {:ok, 1}
      assert Helpers.normalize_result({:error, %{code: :x}}) == {:error, %{code: :x}}

      assert {:error, envelope} = Helpers.normalize_result(:bad, :invalid_result, "Bad result")
      assert envelope.code == :invalid_result
      assert envelope.retryable == false
    end
  end

  describe "correlation_id/1" do
    test "prefers request_id then call_id then run_id then id" do
      assert Helpers.correlation_id(%{request_id: "req_1", call_id: "call_1"}) == "req_1"
      assert Helpers.correlation_id(%{"call_id" => "call_1"}) == "call_1"
      assert Helpers.correlation_id(%{run_id: "run_1"}) == "run_1"
      assert Helpers.correlation_id(%{"id" => "id_1"}) == "id_1"
      assert Helpers.correlation_id(nil) == nil
    end
  end

  describe "sanitize_delta/2" do
    test "removes control bytes and truncates by max chars" do
      assert Helpers.sanitize_delta("abc" <> <<1>> <> "def", 10) == "abcdef"
      assert Helpers.sanitize_delta("abcdefghijklmnopqrstuvwxyz", 5) == "abcde"
    end
  end
end
