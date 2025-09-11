defmodule ReqLLM.Coverage.Anthropic.ToolsTest do
  @moduledoc """
  Anthropic tool calling coverage tests.

  Simple tests for tool calling functionality.

  Run with LIVE=true to test against live API and capture fixtures.
  """
  use ExUnit.Case, async: false

  alias ReqLLM.Test.LiveFixture, as: ReqFixture
  import ReqFixture

  @moduletag :coverage
  @moduletag :anthropic

  @model "anthropic:claude-3-haiku-20240307"

  @weather_tool %{
    name: "get_weather",
    description: "Get current weather for a location",
    input_schema: %{
      type: "object",
      properties: %{
        location: %{
          type: "string",
          description: "City name"
        }
      },
      required: ["location"]
    }
  }

  test "basic tool calling" do
    result =
      use_fixture(:anthropic, "basic_tool_calling", fn ->
        ctx =
          ReqLLM.Context.new([
            ReqLLM.Context.user("What's the weather in Tokyo?")
          ])

        ReqLLM.generate_text(@model, ctx, tools: [@weather_tool], max_tokens: 100)
      end)

    {:ok, resp} = result
    # Response might be text or contain tool calls
    assert resp.status == 200
    assert resp.body != nil
  end

  test "tool choice parameter" do
    result =
      use_fixture(:anthropic, "tool_choice_test", fn ->
        ctx =
          ReqLLM.Context.new([
            ReqLLM.Context.user("What's the weather in Paris?")
          ])

        ReqLLM.generate_text(@model, ctx,
          tools: [@weather_tool],
          tool_choice: %{type: "tool", name: "get_weather"},
          max_tokens: 100
        )
      end)

    {:ok, resp} = result
    assert resp.status == 200
    assert resp.body != nil
  end
end
