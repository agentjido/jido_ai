defmodule ReqLLM.Coverage.Anthropic.ThinkingTokensTest do
  use ExUnit.Case, async: true
  alias ReqLLM.Test.LiveFixture, as: ReqFixture
  import ReqFixture
  import ReqLLM.Context

  @moduletag :coverage
  @moduletag :anthropic
  @moduletag :thinking_tokens
  @moduletag :reasoning_models

  describe "thinking tokens (reasoning models)" do
    test "enable thinking with token budget" do
      # Use a reasoning-capable model
      model = ReqLLM.Model.from("anthropic:claude-3-7-sonnet-20250219")

      context =
        ReqLLM.Context.new([
          user(
            "Solve this step by step: If a train leaves station A at 2 PM going 60 mph, and another train leaves station B at 3 PM going 80 mph, and the stations are 280 miles apart, when do they meet?"
          )
        ])

      {:ok, response} =
        use_fixture("thinking_tokens/basic_reasoning", [], fn ->
          ReqLLM.generate_text(model,
            context: context,
            thinking: %{type: "enabled", budget_tokens: 2048},
            max_tokens: 300
          )
        end)

      # Should contain both thinking and final answer
      thinking_chunks = response.chunks |> Enum.filter(&(&1.type == :thinking))
      text_chunks = response.chunks |> Enum.filter(&(&1.type == :text))

      assert length(thinking_chunks) > 0
      assert length(text_chunks) > 0

      # Thinking content should show reasoning process
      thinking_text = thinking_chunks |> Enum.map(& &1.text) |> Enum.join()
      assert String.length(thinking_text) > 50

      # Final answer should be coherent
      final_text = text_chunks |> Enum.map(& &1.text) |> Enum.join()
      assert final_text =~ ~r/(meet|time|PM)/i
    end

    test "thinking tokens with minimal budget" do
      model = ReqLLM.Model.from("anthropic:claude-3-7-sonnet-20250219")

      context =
        ReqLLM.Context.new([
          user("What's 12 + 15?")
        ])

      {:ok, response} =
        use_fixture("thinking_tokens/minimal_budget", [], fn ->
          ReqLLM.generate_text(model,
            context: context,
            # Minimum allowed
            thinking: %{type: "enabled", budget_tokens: 1024},
            max_tokens: 100
          )
        end)

      # Even with minimal budget, should get some thinking
      thinking_chunks = response.chunks |> Enum.filter(&(&1.type == :thinking))
      text_chunks = response.chunks |> Enum.filter(&(&1.type == :text))

      # Might not always generate thinking for simple problems, but if it does:
      if length(thinking_chunks) > 0 do
        thinking_text = thinking_chunks |> Enum.map(& &1.text) |> Enum.join()
        assert String.length(thinking_text) > 0
      end

      # Should have final answer
      assert length(text_chunks) > 0
      final_text = text_chunks |> Enum.map(& &1.text) |> Enum.join()
      assert final_text =~ "27"
    end

    test "thinking tokens with complex reasoning task" do
      model = ReqLLM.Model.from("anthropic:claude-3-7-sonnet-20250219")

      context =
        ReqLLM.Context.new([
          user("""
          You have 3 boxes: Box A contains 2 red balls and 3 blue balls. Box B contains 4 red balls and 1 blue ball. 
          Box C contains 1 red ball and 4 blue balls. You randomly select a box, then randomly draw a ball. 
          What's the probability of drawing a red ball? Show your work.
          """)
        ])

      {:ok, response} =
        use_fixture("thinking_tokens/complex_reasoning", [], fn ->
          ReqLLM.generate_text(model,
            context: context,
            thinking: %{type: "enabled", budget_tokens: 3000},
            max_tokens: 400
          )
        end)

      thinking_chunks = response.chunks |> Enum.filter(&(&1.type == :thinking))
      text_chunks = response.chunks |> Enum.filter(&(&1.type == :text))

      # Complex problem should trigger thinking
      assert length(thinking_chunks) > 0

      thinking_text = thinking_chunks |> Enum.map(& &1.text) |> Enum.join()
      # Should show step-by-step reasoning
      assert thinking_text =~ ~r/(box|probability|calculate)/i

      final_text = text_chunks |> Enum.map(& &1.text) |> Enum.join()
      # Should contain probability calculation
      assert final_text =~ ~r/(probability|%|\d+\/\d+|0\.\d+)/i
    end

    test "thinking tokens in streaming mode" do
      model = ReqLLM.Model.from("anthropic:claude-3-7-sonnet-20250219")

      context =
        ReqLLM.Context.new([
          user(
            "Plan a simple web application architecture. Consider frontend, backend, and database layers."
          )
        ])

      {:ok, response} =
        use_fixture("thinking_tokens/streaming_thinking", [], fn ->
          ReqLLM.stream_text(model,
            context: context,
            thinking: %{type: "enabled", budget_tokens: 2500},
            max_tokens: 350
          )
        end)

      thinking_chunks = response.chunks |> Enum.filter(&(&1.type == :thinking))
      text_chunks = response.chunks |> Enum.filter(&(&1.type == :text))

      # In streaming, thinking should come before text
      if length(thinking_chunks) > 0 do
        first_thinking_index = Enum.find_index(response.chunks, &(&1.type == :thinking))
        first_text_index = Enum.find_index(response.chunks, &(&1.type == :text))

        if first_text_index do
          assert first_thinking_index < first_text_index
        end
      end

      # Should have architectural content
      final_text = text_chunks |> Enum.map(& &1.text) |> Enum.join()
      assert final_text =~ ~r/(frontend|backend|database|architecture)/i
    end

    test "thinking disabled shows no thinking tokens" do
      model = ReqLLM.Model.from("anthropic:claude-3-7-sonnet-20250219")

      context =
        ReqLLM.Context.new([
          user("Explain the concept of recursion in programming")
        ])

      {:ok, response} =
        use_fixture("thinking_tokens/disabled_thinking", [], fn ->
          ReqLLM.generate_text(model,
            context: context,
            # No thinking parameter - should be disabled by default
            max_tokens: 200
          )
        end)

      # Should have no thinking chunks when disabled
      thinking_chunks = response.chunks |> Enum.filter(&(&1.type == :thinking))
      text_chunks = response.chunks |> Enum.filter(&(&1.type == :text))

      assert length(thinking_chunks) == 0
      assert length(text_chunks) > 0

      final_text = text_chunks |> Enum.map(& &1.text) |> Enum.join()
      assert final_text =~ ~r/(recursion|function|call)/i
    end

    test "thinking with tool calling" do
      model = ReqLLM.Model.from("anthropic:claude-3-7-sonnet-20250219")

      {:ok, calculator_tool} =
        ReqLLM.Tool.new(
          name: "calculate",
          description: "Perform mathematical calculations",
          parameter_schema: [expression: [type: :string, required: true]]
        )

      context =
        ReqLLM.Context.new([
          user(
            "I need to calculate compound interest: $1000 principal, 5% annual rate, compounded monthly for 2 years. Walk me through this."
          )
        ])

      {:ok, response} =
        use_fixture("thinking_tokens/thinking_with_tools", [], fn ->
          ReqLLM.generate_text(model,
            context: context,
            thinking: %{type: "enabled", budget_tokens: 2000},
            tools: [calculator_tool],
            max_tokens: 400
          )
        end)

      thinking_chunks = response.chunks |> Enum.filter(&(&1.type == :thinking))
      _tool_call_chunks = response.chunks |> Enum.filter(&(&1.type == :tool_call))
      text_chunks = response.chunks |> Enum.filter(&(&1.type == :text))

      # Should think about the problem, possibly call tool, then explain
      if length(thinking_chunks) > 0 do
        thinking_text = thinking_chunks |> Enum.map(& &1.text) |> Enum.join()
        assert thinking_text =~ ~r/(compound|formula|calculate)/i
      end

      # May or may not use the tool depending on reasoning
      assert length(text_chunks) > 0
    end

    test "non-reasoning model with thinking parameter" do
      # Test with a non-reasoning model (older Claude)
      model = ReqLLM.Model.from("anthropic:claude-3-haiku-20240307")

      context =
        ReqLLM.Context.new([
          user("Solve this puzzle: What comes next in the sequence 2, 4, 8, 16, ?")
        ])

      # Non-reasoning models should either ignore thinking parameter or return error
      result =
        use_fixture("thinking_tokens/non_reasoning_model", [], fn ->
          ReqLLM.generate_text(model,
            context: context,
            thinking: %{type: "enabled", budget_tokens: 1500},
            max_tokens: 100
          )
        end)

      case result do
        {:ok, response} ->
          # If successful, should not have thinking tokens
          thinking_chunks = response.chunks |> Enum.filter(&(&1.type == :thinking))
          assert length(thinking_chunks) == 0

          text_chunks = response.chunks |> Enum.filter(&(&1.type == :text))
          assert length(text_chunks) > 0

        {:error, _error} ->
          # Error is acceptable for unsupported models
          assert true
      end
    end
  end
end
