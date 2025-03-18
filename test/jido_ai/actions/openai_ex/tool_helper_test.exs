defmodule Jido.AI.Actions.OpenaiEx.ToolHelperTest do
  use ExUnit.Case, async: true
  alias Jido.AI.Actions.OpenaiEx.ToolHelper
  alias Jido.Actions.Arithmetic.Add

  @moduletag :capture_log

  describe "to_openai_tools/1" do
    test "converts a list of actions to OpenAI tool format" do
      actions = [Add]
      {:ok, tools} = ToolHelper.to_openai_tools(actions)

      assert length(tools) == 1
      [tool] = tools

      assert tool == %{
               type: "function",
               function: %{
                 name: "add",
                 description: "Adds two numbers",
                 parameters: %{
                   type: "object",
                   required: ["value", "amount"],
                   properties: %{
                     "amount" => %{type: "integer", description: "The second number to add"},
                     "value" => %{type: "integer", description: "The first number to add"}
                   }
                 }
               }
             }
    end

    test "returns error for module that doesn't implement protocol" do
      actions = [String]

      assert {:error,
              "Action String is not a valid compiled module or does not implement Jido.Action.Tool protocol"} =
               ToolHelper.to_openai_tools(actions)
    end
  end

  describe "handle_tool_call/2" do
    test "executes a tool call with valid parameters" do
      tool_call = %{
        name: "add",
        arguments: Jason.encode!(%{"value" => "5", "amount" => "3"})
      }

      available_actions = [Add]
      {:ok, result} = ToolHelper.handle_tool_call(tool_call, available_actions)
      assert result == 8
    end

    test "returns error for invalid tool name" do
      tool_call = %{
        name: "invalid_tool",
        arguments: "{}"
      }

      available_actions = [Add]

      assert {:error, "No action found for tool: invalid_tool"} =
               ToolHelper.handle_tool_call(tool_call, available_actions)
    end

    test "returns error for invalid arguments" do
      tool_call = %{
        name: "add",
        arguments: "invalid json"
      }

      available_actions = [Add]
      assert {:error, _} = ToolHelper.handle_tool_call(tool_call, available_actions)
    end

    test "returns error for invalid integer values" do
      tool_call = %{
        name: "add",
        arguments: Jason.encode!(%{"value" => "not a number", "amount" => "3"})
      }

      available_actions = [Add]

      assert {:error, "Invalid integer: not a number"} =
               ToolHelper.handle_tool_call(tool_call, available_actions)
    end
  end

  describe "process_response/2" do
    test "processes response with tool calls" do
      response = %{
        choices: [
          %{
            message: %{
              content: "Let me calculate that for you.",
              tool_calls: [
                %{
                  name: "add",
                  arguments: Jason.encode!(%{"value" => "5", "amount" => "3"})
                }
              ]
            }
          }
        ]
      }

      available_actions = [Add]
      {:ok, result} = ToolHelper.process_response(response, available_actions)

      assert result == %{
               content: "Let me calculate that for you.",
               tool_results: [
                 %{
                   tool: "add",
                   result: 8
                 }
               ]
             }
    end

    test "processes response without tool calls" do
      response = %{
        choices: [
          %{
            message: %{
              content: "Hello, how can I help you?"
            }
          }
        ]
      }

      available_actions = [Add]
      {:ok, result} = ToolHelper.process_response(response, available_actions)

      assert result == %{
               content: "Hello, how can I help you?",
               tool_results: []
             }
    end

    test "returns error for invalid response format" do
      response = %{invalid: "format"}
      available_actions = [Add]

      assert {:error, "Invalid response format"} =
               ToolHelper.process_response(response, available_actions)
    end
  end
end
