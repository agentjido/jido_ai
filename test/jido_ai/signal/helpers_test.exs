defmodule Jido.AI.Signal.HelpersTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Error
  alias Jido.AI.Signal.Helpers

  describe "correlation_id/1" do
    test "prefers request_id then call_id then run_id then id" do
      assert Helpers.correlation_id(%{request_id: "req_1", call_id: "call_1"}) == "req_1"
      assert Helpers.correlation_id(%{"call_id" => "call_1"}) == "call_1"
      assert Helpers.correlation_id(%{run_id: "run_1"}) == "run_1"
      assert Helpers.correlation_id(%{"id" => "id_1"}) == "id_1"
      assert Helpers.correlation_id(nil) == nil
    end

    test "supports Signals and every string or atom fallback field" do
      signal =
        Jido.Signal.new!("ai.test", %{request_id: "signal-request"}, %{source: "/test"})

      assert Helpers.correlation_id(signal) == "signal-request"

      assert Helpers.correlation_id(%{"request_id" => "request"}) == "request"
      assert Helpers.correlation_id(%{call_id: "call"}) == "call"
      assert Helpers.correlation_id(%{"run_id" => "run"}) == "run"
      assert Helpers.correlation_id(%{id: "id"}) == "id"
      assert Helpers.correlation_id(%{}) == nil
      assert Helpers.correlation_id(:invalid) == nil
    end
  end

  describe "sanitize_delta/2" do
    test "removes control bytes and truncates by max chars" do
      assert Helpers.sanitize_delta("abc" <> <<1>> <> "def", 10) == "abcdef"
      assert Helpers.sanitize_delta("abcdefghijklmnopqrstuvwxyz", 5) == "abcde"
    end

    test "uses the default bound and passes through non-text deltas" do
      assert byte_size(Helpers.sanitize_delta(String.duplicate("x", 5_000))) == 4_000
      assert Helpers.sanitize_delta(%{type: :image}, 10) == %{type: :image}
    end
  end

  describe "error compatibility delegates" do
    test "forward to Jido.AI.Error" do
      assert apply(Helpers, :error_envelope, [:execution_error, "boom", %{}, false]) ==
               Error.error_envelope(:execution_error, "boom")

      assert apply(Helpers, :normalize_error, [:timeout, :execution_error, "failed", %{}]) ==
               Error.normalize(:timeout, :execution_error, "failed")

      assert apply(Helpers, :normalize_result, [{:error, :timeout}, :tool_error, "failed"]) ==
               Error.normalize_result({:error, :timeout}, :tool_error, "failed")

      assert apply(Helpers, :retryable?, [:timeout])
    end

    test "default delegate arguments preserve the canonical behavior" do
      assert apply(Helpers, :error_envelope, [:execution_error, "boom"]) ==
               Error.error_envelope(:execution_error, "boom")

      assert apply(Helpers, :normalize_error, [:timeout]) == Error.normalize(:timeout)

      assert apply(Helpers, :normalize_error, [:timeout, :tool_error]) ==
               Error.normalize(:timeout, :tool_error)

      assert apply(Helpers, :normalize_error, [:timeout, :tool_error, "tool failed"]) ==
               Error.normalize(:timeout, :tool_error, "tool failed")

      assert apply(Helpers, :normalize_result, [{:ok, :done}]) ==
               Error.normalize_result({:ok, :done})

      assert apply(Helpers, :normalize_result, [{:ok, :done}, :tool_error]) ==
               Error.normalize_result({:ok, :done}, :tool_error)
    end
  end
end
