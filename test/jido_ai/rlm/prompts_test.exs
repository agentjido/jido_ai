defmodule Jido.AI.RLM.PromptsTest do
  use ExUnit.Case, async: true

  alias Jido.AI.RLM.Prompts

  describe "system_prompt/1" do
    test "returns a string containing key methodology phrases" do
      result = Prompts.system_prompt(%{tools: [SomeTool]})

      assert is_binary(result)
      assert result =~ "data analyst"
      assert result =~ "Check stats"
      assert result =~ "Chunk"
      assert result =~ "Search / Delegate"
      assert result =~ "Record hypotheses"
      assert result =~ "Answer when confident"
      assert result =~ "Never attempt to read the entire context at once"
      assert result =~ "subquery batch"
      assert result =~ "Record your reasoning"
    end
  end

  describe "next_step_prompt/1" do
    test "iteration 1 mentions not explored" do
      result =
        Prompts.next_step_prompt(%{
          query: "Find revenue trends",
          iteration: 1,
          workspace_summary: ""
        })

      assert result.content =~ "not explored"
      assert result.content =~ "Find revenue trends"
    end

    test "iteration > 1 includes workspace summary" do
      summary = "Found 3 relevant sections in financial data."

      result =
        Prompts.next_step_prompt(%{
          query: "Find revenue trends",
          iteration: 3,
          workspace_summary: summary
        })

      assert result.content =~ summary
      assert result.content =~ "Find revenue trends"
      assert result.content =~ "Exploration Progress"
      assert result.content =~ "next action"
    end

    test "returns correct role" do
      result =
        Prompts.next_step_prompt(%{
          query: "test",
          iteration: 1,
          workspace_summary: ""
        })

      assert result.role == :user

      result2 =
        Prompts.next_step_prompt(%{
          query: "test",
          iteration: 5,
          workspace_summary: "progress"
        })

      assert result2.role == :user
    end
  end
end
