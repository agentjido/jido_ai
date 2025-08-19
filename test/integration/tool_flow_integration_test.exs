defmodule Jido.AI.ToolFlowIntegrationTest do
  use ExUnit.Case, async: true

  import Jido.AI.Messages

  alias Jido.AI.Message

  describe "tool conversation structure validation" do
    test "validates basic tool call conversation" do
      messages = [
        user("What is 5 + 3?"),
        tool_result("call_123", "add", %{result: 8}),
        assistant("The answer is 8")
      ]

      assert Enum.all?(messages, &Message.valid?/1)

      # Verify structure
      [_user, tool_msg, _final] = messages
      assert tool_msg.tool_call_id == "call_123"
      assert tool_msg.role == :tool
    end
  end
end
