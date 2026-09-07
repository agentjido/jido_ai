defmodule Jido.AI.ToolResultBoundaryTest do
  use ExUnit.Case, async: true
  alias Jido.Action.Error, as: ActionError
  alias Jido.AI.{Error, ToolResult}

  @call %{id: "one", name: "search"}

  test "returned typed Action error maps keep their type, message, details and retry hint" do
    for reason <- [
          %{type: :timeout, message: "Timed out", details: %{attempt: 2}, retryable?: false},
          %{"code" => "timeout", "message" => "Timed out", "details" => %{"attempt" => 2}, "retryable" => false}
        ] do
      wrapped = ActionError.execution_error(inspect(reason), %{reason: reason, retry: false})
      assert {:error, error, []} = ToolResult.normalize({:error, wrapped}, @call)

      assert error ==
               Error.normalize(reason, :execution_error, "Tool execution failed", %{
                 tool_name: "search",
                 tool_call_id: "one"
               })

      assert error.type == :timeout and error.message == "Timed out" and error.retryable? == false
    end
  end

  test "execution evidence prevents the returned-error unwrapping rule" do
    reason = %{type: :timeout, message: "Timed out"}
    wrapped = ActionError.execution_error("Tool process failed", %{reason: reason, retry: false, action: __MODULE__})
    assert {:error, error, []} = ToolResult.normalize({:error, wrapped}, @call)
    assert error.type == :execution_error and error.message == "Tool process failed"
    assert error.details.reason == reason and error.details.action == __MODULE__
    refute error.retryable?
  end

  test "exception structs and untyped returned errors keep the existing core normalization" do
    for reason <- [RuntimeError.exception("Broken"), %{message: "No type"}, "Unavailable"] do
      wrapped = ActionError.execution_error("Core failure", %{reason: reason, retry: false})
      assert {:error, error, []} = ToolResult.normalize({:error, wrapped}, @call)

      assert error ==
               Error.normalize(wrapped, :execution_error, "Tool execution failed", %{
                 tool_name: "search",
                 tool_call_id: "one"
               })
    end
  end

  test "nested skill exceptions can supply error details without implementing Access" do
    nested = Jido.AI.Skill.Error.Validation.InvalidField.exception(field: :name, reason: "Changed", value: "wrong")

    for details <- [%{reason: nested}, %{"reason" => nested}] do
      reason = %{type: :validation, message: "Skill rejected", details: details}
      wrapped = ActionError.execution_error(inspect(reason), %{reason: reason, retry: false})
      assert {:error, error, []} = ToolResult.normalize({:error, wrapped}, @call)
      assert error.type == :validation and error.message == "Skill rejected"
      refute error.retryable?
      stored = Map.get(error.details, :reason) || Map.fetch!(error.details, "reason")
      assert stored.field == :name and stored.reason == "Changed" and stored.value == "wrong"
      assert {:ok, _} = Jason.encode(error)
    end
  end

  test "the AI operation cause bridge still keeps typed tool failures" do
    reason = %{type: :timeout, message: "Timed out", retryable?: true}
    assert {:error, wrapped} = Error.capture(fn -> {:error, reason} end)
    assert {:error, error, []} = ToolResult.normalize({:error, wrapped}, @call)
    assert error.type == :timeout and error.message == "Timed out" and error.retryable?
    assert error.details == %{tool_name: "search", tool_call_id: "one"}
  end
end
