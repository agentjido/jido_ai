defmodule ReqLLM.ProviderTest.ToolCalling do
  @moduledoc """
  Tool/function calling tests.

  Tests tool calling capabilities:
  - Tool definition and registration  
  - Parameter schema validation
  - Tool execution and result handling
  - Multi-tool scenarios
  - Error handling for malformed tool calls
  """

  defmacro __using__(opts) do
    provider = Keyword.fetch!(opts, :provider)
    model = Keyword.fetch!(opts, :model)

    quote bind_quoted: [provider: provider, model: model] do
      use ExUnit.Case, async: false

      alias ReqLLM.Test.LiveFixture, as: ReqFixture
      import ReqFixture

      @moduletag :coverage
      @moduletag provider

      # TODO: Implement tool calling test macros
      # Will include tests for generate_object/4, tool schemas, etc.
      
      # Example tests that could be implemented:
      #
      # test "basic tool calling" do
      #   result =
      #     use_fixture(unquote(provider), "basic_tool_call", fn ->
      #       tools = [
      #         %{
      #           "type" => "function",
      #           "function" => %{
      #             "name" => "get_weather",
      #             "description" => "Get weather information",
      #             "parameters" => %{
      #               "type" => "object",
      #               "properties" => %{
      #                 "location" => %{"type" => "string"}
      #               }
      #             }
      #           }
      #         }
      #       ]
      #
      #       ReqLLM.generate_object(
      #         unquote(model),
      #         "What's the weather in Paris?",
      #         tools
      #       )
      #     end)
      #
      #   {:ok, resp} = result
      #   assert resp.tool_calls != nil
      # end
    end
  end
end
