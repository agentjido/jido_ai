defmodule JidoAITest.Actions.DelegateTaskTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Actions.Orchestration.DelegateTask

  @moduletag :requires_api

  describe "DelegateTask" do
    test "delegates to matching specialist" do
      params = %{
        task: "Analyze a PDF document",
        available_agents: [
          %{
            name: "doc_analyzer",
            description: "Analyzes documents",
            capabilities: ["pdf", "text_extraction"],
            agent_module: FakeDocAgent
          },
          %{
            name: "code_reviewer",
            description: "Reviews code",
            capabilities: ["code", "testing"]
          }
        ]
      }

      {:ok, result} = DelegateTask.run(params, %{})

      assert result.decision == :delegate
      assert result.target.name == "doc_analyzer"
      assert is_binary(result.reasoning)
    end

    test "returns local for unmatched tasks" do
      params = %{
        task: "What is 2 + 2?",
        available_agents: [
          %{name: "doc_analyzer", description: "Analyzes documents", capabilities: ["pdf"]}
        ]
      }

      {:ok, result} = DelegateTask.run(params, %{})

      assert result.decision == :local
      assert is_binary(result.reasoning)
    end
  end
end
