defmodule ReqLLM.Coverage.Anthropic.ToolCallingTest do
  use ExUnit.Case, async: true
  alias ReqLLM.Test.LiveFixture, as: ReqFixture
  import ReqFixture
  import ReqLLM.Context

  @moduletag :coverage
  @moduletag :anthropic
  @moduletag :tool_calling

  describe "tool choice parameter" do
    test "tool_choice: auto (default behavior)" do
      model = ReqLLM.Model.from("anthropic:claude-3-haiku-20240307")

      {:ok, weather_tool} =
        ReqLLM.Tool.new(
          name: "get_weather",
          description: "Get current weather for a location",
          parameter_schema: [
            location: [type: :string, required: true]
          ]
        )

      context =
        ReqLLM.Context.new([
          user("What's the weather like in Paris?")
        ])

      {:ok, response} =
        use_fixture("tool_calling/choice_auto", [], fn ->
          ReqLLM.generate_text(model,
            context: context,
            tools: [weather_tool],
            # Explicit auto
            tool_choice: %{type: "auto"},
            max_tokens: 200
          )
        end)

      # Claude should decide to call the weather tool
      tool_calls = response.chunks |> Enum.filter(&(&1.type == :tool_call))
      assert length(tool_calls) > 0

      tool_call = hd(tool_calls)
      assert tool_call.name == "get_weather"
      assert tool_call.arguments["location"] =~ ~r/paris/i
      assert is_binary(tool_call.id)
    end

    test "tool_choice: none (force no tool use)" do
      model = ReqLLM.Model.from("anthropic:claude-3-haiku-20240307")

      {:ok, weather_tool} =
        ReqLLM.Tool.new(
          name: "get_weather",
          description: "Get current weather for a location",
          parameter_schema: [location: [type: :string, required: true]]
        )

      context =
        ReqLLM.Context.new([
          user("What's the weather like in Tokyo?")
        ])

      {:ok, response} =
        use_fixture("tool_calling/choice_none", [], fn ->
          ReqLLM.generate_text(model,
            context: context,
            tools: [weather_tool],
            tool_choice: %{type: "none"},
            max_tokens: 100
          )
        end)

      # Should not call any tools, just respond with text
      tool_calls = response.chunks |> Enum.filter(&(&1.type == :tool_call))
      assert length(tool_calls) == 0

      text_content =
        response.chunks
        |> Enum.filter(&(&1.type == :text))
        |> Enum.map(& &1.text)
        |> Enum.join()

      # Should respond about weather without calling tool
      assert text_content =~ ~r/(weather|temperature|can't|don't|unable)/i
    end

    test "tool_choice: any (force tool use)" do
      model = ReqLLM.Model.from("anthropic:claude-3-haiku-20240307")

      {:ok, calculator_tool} =
        ReqLLM.Tool.new(
          name: "calculate",
          description: "Perform mathematical calculations",
          parameter_schema: [
            expression: [type: :string, required: true]
          ]
        )

      {:ok, weather_tool} =
        ReqLLM.Tool.new(
          name: "get_weather",
          description: "Get weather information",
          parameter_schema: [location: [type: :string, required: true]]
        )

      context =
        ReqLLM.Context.new([
          # Question that doesn't need tools
          user("Hello, how are you?")
        ])

      {:ok, response} =
        use_fixture("tool_calling/choice_any", [], fn ->
          ReqLLM.generate_text(model,
            context: context,
            tools: [calculator_tool, weather_tool],
            # Force using one of the tools
            tool_choice: %{type: "any"},
            max_tokens: 200
          )
        end)

      # Must use at least one tool
      tool_calls = response.chunks |> Enum.filter(&(&1.type == :tool_call))
      assert length(tool_calls) > 0

      tool_call = hd(tool_calls)
      assert tool_call.name in ["calculate", "get_weather"]
    end

    test "tool_choice: specific tool by name" do
      model = ReqLLM.Model.from("anthropic:claude-3-haiku-20240307")

      {:ok, calculator_tool} =
        ReqLLM.Tool.new(
          name: "calculate",
          description: "Perform mathematical calculations",
          parameter_schema: [expression: [type: :string, required: true]]
        )

      {:ok, weather_tool} =
        ReqLLM.Tool.new(
          name: "get_weather",
          description: "Get weather information",
          parameter_schema: [location: [type: :string, required: true]]
        )

      context =
        ReqLLM.Context.new([
          user("What's 15 multiplied by 8?")
        ])

      {:ok, response} =
        use_fixture("tool_calling/choice_specific", [], fn ->
          ReqLLM.generate_text(model,
            context: context,
            tools: [calculator_tool, weather_tool],
            # Force specific tool
            tool_choice: %{type: "tool", name: "calculate"},
            max_tokens: 200
          )
        end)

      # Must use the calculate tool specifically
      tool_calls = response.chunks |> Enum.filter(&(&1.type == :tool_call))
      assert length(tool_calls) > 0

      tool_call = hd(tool_calls)
      assert tool_call.name == "calculate"
      assert tool_call.arguments["expression"] =~ ~r/(15.*8|8.*15)/
    end

    test "disable_parallel_tool_use option" do
      model = ReqLLM.Model.from("anthropic:claude-3-haiku-20240307")

      {:ok, tool1} =
        ReqLLM.Tool.new(
          name: "get_weather",
          description: "Get weather",
          parameter_schema: [location: [type: :string, required: true]]
        )

      {:ok, tool2} =
        ReqLLM.Tool.new(
          name: "get_time",
          description: "Get current time",
          parameter_schema: [timezone: [type: :string]]
        )

      context =
        ReqLLM.Context.new([
          user("Get weather for NYC and current time in EST")
        ])

      {:ok, response} =
        use_fixture("tool_calling/no_parallel", [], fn ->
          ReqLLM.generate_text(model,
            context: context,
            tools: [tool1, tool2],
            tool_choice: %{type: "auto", disable_parallel_tool_use: true},
            max_tokens: 200
          )
        end)

      # Should use only one tool call at a time
      tool_calls = response.chunks |> Enum.filter(&(&1.type == :tool_call))
      # With parallel disabled, might still get multiple but they should be sequential
      assert length(tool_calls) >= 1
    end
  end

  describe "tool result handling" do
    test "tool call followed by tool result in conversation" do
      model = ReqLLM.Model.from("anthropic:claude-3-haiku-20240307")

      {:ok, weather_tool} =
        ReqLLM.Tool.new(
          name: "get_weather",
          description: "Get current weather",
          parameter_schema: [location: [type: :string, required: true]]
        )

      # Initial request with tool call
      context =
        ReqLLM.Context.new([
          user("What's the weather in London?")
        ])

      {:ok, first_response} =
        use_fixture("tool_calling/initial_call", [], fn ->
          ReqLLM.generate_text(model,
            context: context,
            tools: [weather_tool],
            max_tokens: 200
          )
        end)

      # Get the tool call details
      tool_calls = first_response.chunks |> Enum.filter(&(&1.type == :tool_call))
      assert length(tool_calls) > 0

      tool_call = hd(tool_calls)
      assert tool_call.name == "get_weather"
      tool_call_id = tool_call.id

      # Create follow-up context with tool result
      tool_result =
        ReqLLM.Message.ContentPart.tool_result(
          tool_call_id,
          "London: 18°C, partly cloudy, light rain expected"
        )

      extended_context =
        ReqLLM.Context.new([
          user("What's the weather in London?"),
          assistant([
            ReqLLM.Message.ContentPart.tool_call(
              tool_call.name,
              tool_call.arguments,
              tool_call_id
            )
          ]),
          user([tool_result])
        ])

      {:ok, final_response} =
        use_fixture("tool_calling/with_result", [], fn ->
          ReqLLM.generate_text(model,
            context: extended_context,
            tools: [weather_tool],
            max_tokens: 150
          )
        end)

      # Should provide a summary based on the tool result
      text_content =
        final_response.chunks
        |> Enum.filter(&(&1.type == :text))
        |> Enum.map(& &1.text)
        |> Enum.join()

      assert text_content =~ ~r/(18|cloudy|rain)/i
    end

    test "multiple tool calls with results" do
      model = ReqLLM.Model.from("anthropic:claude-3-haiku-20240307")

      {:ok, weather_tool} =
        ReqLLM.Tool.new(
          name: "get_weather",
          description: "Get weather information",
          parameter_schema: [location: [type: :string, required: true]]
        )

      {:ok, time_tool} =
        ReqLLM.Tool.new(
          name: "get_time",
          description: "Get current time",
          parameter_schema: [location: [type: :string, required: true]]
        )

      # Simulate a conversation with multiple tool calls and results
      context =
        ReqLLM.Context.new([
          user("What's the weather and current time in Paris?"),
          assistant([
            ReqLLM.Message.ContentPart.tool_call(
              "get_weather",
              %{"location" => "Paris"},
              "call_1"
            ),
            ReqLLM.Message.ContentPart.tool_call("get_time", %{"location" => "Paris"}, "call_2")
          ]),
          user([
            ReqLLM.Message.ContentPart.tool_result("call_1", "Paris: 22°C, sunny"),
            ReqLLM.Message.ContentPart.tool_result("call_2", "Paris: 14:30 CEST")
          ])
        ])

      {:ok, response} =
        use_fixture("tool_calling/multiple_results", [], fn ->
          ReqLLM.generate_text(model,
            context: context,
            tools: [weather_tool, time_tool],
            max_tokens: 150
          )
        end)

      text_content =
        response.chunks
        |> Enum.filter(&(&1.type == :text))
        |> Enum.map(& &1.text)
        |> Enum.join()

      # Should synthesize information from both tool results
      assert text_content =~ ~r/(22|sunny)/i
      assert text_content =~ ~r/(14:30|2:30)/i
    end

    test "tool call with error result" do
      model = ReqLLM.Model.from("anthropic:claude-3-haiku-20240307")

      {:ok, api_tool} =
        ReqLLM.Tool.new(
          name: "call_api",
          description: "Call external API",
          parameter_schema: [endpoint: [type: :string, required: true]]
        )

      context =
        ReqLLM.Context.new([
          user("Get data from the API"),
          assistant([
            ReqLLM.Message.ContentPart.tool_call("call_api", %{"endpoint" => "/users"}, "call_1")
          ]),
          user([
            ReqLLM.Message.ContentPart.tool_result(
              "call_1",
              "Error: API endpoint not found (404)"
            )
          ])
        ])

      {:ok, response} =
        use_fixture("tool_calling/error_result", [], fn ->
          ReqLLM.generate_text(model,
            context: context,
            tools: [api_tool],
            max_tokens: 100
          )
        end)

      text_content =
        response.chunks
        |> Enum.filter(&(&1.type == :text))
        |> Enum.map(& &1.text)
        |> Enum.join()

      # Should handle error gracefully
      assert text_content =~ ~r/(error|404|not found|unavailable)/i
    end
  end

  describe "tool call IDs and correlation" do
    test "tool call IDs are unique and properly formatted" do
      model = ReqLLM.Model.from("anthropic:claude-3-haiku-20240307")

      {:ok, tool1} =
        ReqLLM.Tool.new(
          name: "search",
          description: "Search for information",
          parameter_schema: [query: [type: :string, required: true]]
        )

      {:ok, tool2} =
        ReqLLM.Tool.new(
          name: "translate",
          description: "Translate text",
          parameter_schema: [
            text: [type: :string, required: true],
            target_lang: [type: :string, required: true]
          ]
        )

      context =
        ReqLLM.Context.new([
          user("Search for 'Elixir programming' and translate to French")
        ])

      {:ok, response} =
        use_fixture("tool_calling/unique_ids", [], fn ->
          ReqLLM.generate_text(model,
            context: context,
            tools: [tool1, tool2],
            max_tokens: 300
          )
        end)

      tool_calls = response.chunks |> Enum.filter(&(&1.type == :tool_call))
      assert length(tool_calls) > 0

      # Verify all tool calls have IDs and they're unique
      ids = Enum.map(tool_calls, & &1.id)
      assert Enum.all?(ids, &is_binary/1)
      assert Enum.all?(ids, &(String.length(&1) > 0))
      # All unique
      assert length(ids) == length(Enum.uniq(ids))

      # Anthropic tool call IDs typically start with "toolu_"
      assert Enum.all?(ids, &String.starts_with?(&1, "toolu_"))
    end

    test "tool result references correct tool call ID" do
      model = ReqLLM.Model.from("anthropic:claude-3-haiku-20240307")

      {:ok, math_tool} =
        ReqLLM.Tool.new(
          name: "calculate",
          description: "Perform calculations",
          parameter_schema: [expression: [type: :string, required: true]]
        )

      # Step 1: Get tool call with ID
      context =
        ReqLLM.Context.new([
          user("Calculate 25 * 4")
        ])

      {:ok, first_response} =
        use_fixture("tool_calling/get_call_id", [], fn ->
          ReqLLM.generate_text(model,
            context: context,
            tools: [math_tool],
            max_tokens: 200
          )
        end)

      tool_calls = first_response.chunks |> Enum.filter(&(&1.type == :tool_call))
      assert length(tool_calls) > 0

      tool_call = hd(tool_calls)
      original_id = tool_call.id

      # Step 2: Provide result with matching ID
      extended_context =
        ReqLLM.Context.new([
          user("Calculate 25 * 4"),
          assistant([
            ReqLLM.Message.ContentPart.tool_call(
              "calculate",
              %{"expression" => "25 * 4"},
              original_id
            )
          ]),
          user([
            ReqLLM.Message.ContentPart.tool_result(original_id, "100")
          ])
        ])

      {:ok, final_response} =
        use_fixture("tool_calling/matched_id_result", [], fn ->
          ReqLLM.generate_text(model,
            context: extended_context,
            tools: [math_tool],
            max_tokens: 100
          )
        end)

      text_content =
        final_response.chunks
        |> Enum.filter(&(&1.type == :text))
        |> Enum.map(& &1.text)
        |> Enum.join()

      # Should acknowledge the calculation result
      assert text_content =~ ~r/(100|hundred)/i
    end
  end
end
