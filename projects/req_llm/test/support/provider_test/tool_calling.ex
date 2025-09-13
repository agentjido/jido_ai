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

      import ReqLLM.Test.LiveFixture

      alias ReqLLM.Test.LiveFixture, as: ReqFixture

      @moduletag :coverage
      @moduletag provider

      describe "tool calling" do
        test "basic tool calling with get_weather function" do
          {:ok, response} =
            use_fixture(unquote(provider), "basic_tool_call", fn ->
              tools = [
                ReqLLM.tool(
                  name: "get_weather",
                  description: "Get current weather information for a location",
                  parameter_schema: [
                    location: [
                      type: :string,
                      required: true,
                      doc: "The city and state, e.g. San Francisco, CA"
                    ],
                    unit: [
                      type: {:in, ["celsius", "fahrenheit"]},
                      doc: "The temperature unit to use"
                    ]
                  ],
                  callback: fn _args -> {:ok, "Weather data would go here"} end
                )
              ]

              # xAI reasoning models need more tokens for tool calling
              max_tokens = if unquote(provider) == :xai, do: 500, else: 100

              ReqLLM.generate_text(
                unquote(model),
                "What's the weather like in Paris, France?",
                tools: tools,
                max_tokens: max_tokens
              )
            end)

          # Verify we got a successful response
          assert response.message
          assert response.message.content

          # Find tool call in content
          tool_call_content =
            Enum.find(response.message.content, fn content ->
              content.type == :tool_call
            end)

          assert tool_call_content, "Expected to find tool_call in message content"
          assert tool_call_content.tool_name == "get_weather"
          assert tool_call_content.input
          assert tool_call_content.input["location"]
          assert is_binary(tool_call_content.input["location"])
        end
      end
    end
  end
end
