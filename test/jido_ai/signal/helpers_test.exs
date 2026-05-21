defmodule Jido.AI.Signal.HelpersTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Signal.Helpers

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
