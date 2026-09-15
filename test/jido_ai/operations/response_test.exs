defmodule Jido.AI.Runtime.ResponseTest do
  use ExUnit.Case, async: true
  alias ReqLLM.{Context, Message, Response, ToolCall}
  alias ReqLLM.Message.ContentPart

  test "an empty text marker keeps the exact same assistant in the response and context" do
    {response, prefix} = response("one")
    fixed = Jido.AI.Model.Messages.align_context(response)
    assert fixed.message == response.message
    assert fixed.context.messages == prefix ++ [fixed.message]
    assert fixed.context.tools == response.context.tools
    assert Jido.AI.Model.Messages.align_context(fixed) == fixed
    result = Context.tool_result("one", "echo", "7")
    assert {:ok, context} = Context.append_tool_exchange(fixed.context, fixed, [result])
    assert context.messages == prefix ++ [fixed.message, result]
  end

  for mismatch <- [:id, :arguments] do
    test "a different unresolved tool #{mismatch} still fails continuation" do
      {response, prefix} = response("one")

      call =
        if unquote(mismatch) == :id,
          do: ToolCall.new("other", "echo", ~s({"n":7})),
          else: ToolCall.new("one", "echo", ~s({"n":9}))

      previous = %{response.message | content: [], tool_calls: [call]}
      response = %{response | context: %{response.context | messages: prefix ++ [previous]}}
      assert Jido.AI.Model.Messages.align_context(response) == response

      assert {:error, %{tag: :tool_context_continuation, context: [kind: :pending_tool_calls]}} =
               Context.append_tool_exchange(response.context, response, [Context.tool_result("one", "echo", "7")])
    end
  end

  defp response(id) do
    prefix = [Context.user("Work")]
    original = %Message{role: :assistant, content: [], tool_calls: [ToolCall.new(id, "echo", ~s({"n":7}))]}
    context = Context.new(prefix ++ [original])
    message = %{original | content: [ContentPart.text("")]}
    {%Response{id: "response", model: "claude-sonnet-4-5", context: context, message: message}, prefix}
  end
end
