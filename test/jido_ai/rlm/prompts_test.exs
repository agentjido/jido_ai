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

    test "when max_depth > 0, includes Tool Selection Guide with both tools" do
      result = Prompts.system_prompt(%{tools: [SomeTool], max_depth: 3})

      assert result =~ "Tool Selection Guide"
      assert result =~ "llm_subquery_batch"
      assert result =~ "rlm_spawn_agent"
      assert result =~ "rlm_lua_plan"
    end

    test "lua_only mode excludes direct spawn guidance" do
      result =
        Prompts.system_prompt(%{
          tools: [SomeTool],
          max_depth: 2,
          orchestration_mode: :lua_only
        })

      assert result =~ "rlm_lua_plan"
      refute result =~ "rlm_spawn_agent"
    end

    test "spawn_only mode excludes lua plan guidance" do
      result =
        Prompts.system_prompt(%{
          tools: [SomeTool],
          max_depth: 2,
          orchestration_mode: :spawn_only
        })

      assert result =~ "rlm_spawn_agent"
      refute result =~ "rlm_lua_plan"
    end

    test "when max_depth is 0, does NOT include rlm_spawn_agent" do
      result = Prompts.system_prompt(%{tools: [SomeTool], max_depth: 0})

      refute result =~ "rlm_spawn_agent"
    end

    test "when max_depth is not present, does NOT include rlm_spawn_agent" do
      result = Prompts.system_prompt(%{tools: [SomeTool]})

      refute result =~ "rlm_spawn_agent"
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

    test "when current_depth and max_depth provided with max_depth > 0, includes depth line" do
      result =
        Prompts.next_step_prompt(%{
          query: "test",
          iteration: 2,
          workspace_summary: "progress",
          current_depth: 1,
          max_depth: 3
        })

      assert result.content =~ "Depth: 1/3"
    end

    test "when at max depth, includes maximum depth warning" do
      result =
        Prompts.next_step_prompt(%{
          query: "test",
          iteration: 2,
          workspace_summary: "progress",
          current_depth: 3,
          max_depth: 3
        })

      assert result.content =~ "Depth: 3/3"
      assert result.content =~ "maximum depth"
    end

    test "when max_depth is 0, no depth line appears" do
      result =
        Prompts.next_step_prompt(%{
          query: "test",
          iteration: 2,
          workspace_summary: "progress",
          max_depth: 0
        })

      refute result.content =~ "Depth:"
    end

    test "when max_depth is not provided, no depth line appears" do
      result =
        Prompts.next_step_prompt(%{
          query: "test",
          iteration: 2,
          workspace_summary: "progress"
        })

      refute result.content =~ "Depth:"
    end
  end
end
