defmodule Jido.E2E.ToolAgentTest do
  use ExUnit.Case, async: false
  use Mimic

  require Logger

  alias Jido.AI.Agent
  alias Jido.AI.Actions.Instructor.ChatCompletion
  alias Jido.Actions.Arithmetic.{Add, Subtract, Multiply, Divide}
  alias Instructor.Adapters.Anthropic

  setup :set_mimic_global

  describe "tool calling integration" do
    setup do
      # Mock the Anthropic adapter's chat_completion
      expect(Anthropic, :chat_completion, fn opts, config ->
        # Verify the options passed to the adapter
        assert opts[:model] == "claude-3-haiku-20240307"
        assert length(opts[:messages]) > 0
        assert opts[:temperature] == 0.7
        assert opts[:max_tokens] == 1024
        assert config[:adapter] == Anthropic
        assert config[:api_key] == "test-api-key"

        {:ok, "I'll help you solve that math problem. Let me use the appropriate tool."}
      end)

      # Mock Instructor to use our mocked adapter
      expect(Instructor, :chat_completion, fn opts, config ->
        Anthropic.chat_completion(opts, config)
      end)

      :ok
    end

    test "agent can perform arithmetic operations using tools" do
      # Start the agent with arithmetic tools
      {:ok, agent} =
        Agent.start_link(
          ai: [
            model: {:anthropic, [model_id: "claude-3-haiku-20240307"]},
            prompt: """
            You are a super math genius.
            You are given a math problem and you need to solve it using the tools provided.
            """,
            tools: [
              Add,
              Subtract,
              Multiply,
              Divide
            ]
          ]
        )

      state = Agent.state(agent)
      # Log initial state
      # Logger.info("Initial agent state: #{inspect(Agent.state(agent))}")
      # IO.inspect(state, label: "Initial agent state")

      # # Test addition
      {:ok, result} = Agent.chat_response(agent, "What is the capital of France?")
      IO.inspect(result)
      # assert result == 200

      # # Test multiplication
      # {:ok, result} = Agent.tool_response(agent, "What is 4 * 6?")
      # assert result == 200

      # # Test complex operation
      # {:ok, result} = Agent.tool_response(agent, "What is (5 + 3) * 2?")
      # assert result == 200

      # # Log final state
      # Logger.info("Final agent state: #{inspect(Agent.state(agent))}")
    end
  end
end
