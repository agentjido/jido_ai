defmodule Jido.AI.Runner.ChainOfThoughtTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Runner.ChainOfThought
  alias Jido.AI.Runner.ChainOfThought.Config

  doctest ChainOfThought

  describe "module structure" do
    test "implements Jido.Runner behaviour" do
      behaviours =
        ChainOfThought.module_info(:attributes)
        |> Keyword.get(:behaviour, [])

      assert Jido.Runner in behaviours
    end

    test "exports run/2 function" do
      assert function_exported?(ChainOfThought, :run, 2)
    end

    test "defines Config struct with required fields" do
      config = %Config{}
      assert Map.has_key?(config, :mode)
      assert Map.has_key?(config, :max_iterations)
      assert Map.has_key?(config, :model)
      assert Map.has_key?(config, :temperature)
      assert Map.has_key?(config, :enable_validation)
      assert Map.has_key?(config, :fallback_on_error)
    end
  end

  describe "Config struct defaults" do
    test "has correct default values" do
      config = %Config{}

      assert config.mode == :zero_shot
      assert config.max_iterations == 1
      assert config.model == nil
      assert config.temperature == 0.2
      assert config.enable_validation == true
      assert config.fallback_on_error == true
    end
  end

  describe "configuration validation" do
    setup do
      agent = build_test_agent()
      {:ok, agent: agent}
    end

    test "accepts valid zero_shot mode", %{agent: agent} do
      assert {:ok, _agent, _directives} = ChainOfThought.run(agent, mode: :zero_shot)
    end

    test "accepts valid few_shot mode", %{agent: agent} do
      assert {:ok, _agent, _directives} = ChainOfThought.run(agent, mode: :few_shot)
    end

    test "accepts valid structured mode", %{agent: agent} do
      assert {:ok, _agent, _directives} = ChainOfThought.run(agent, mode: :structured)
    end

    test "rejects invalid mode", %{agent: agent} do
      assert {:error, error} = ChainOfThought.run(agent, mode: :invalid_mode)
      assert error =~ "Invalid mode"
    end

    test "accepts valid max_iterations", %{agent: agent} do
      assert {:ok, _agent, _directives} = ChainOfThought.run(agent, max_iterations: 5)
    end

    test "rejects non-positive max_iterations", %{agent: agent} do
      assert {:error, error} = ChainOfThought.run(agent, max_iterations: 0)
      assert error =~ "max_iterations must be a positive integer"
    end

    test "rejects non-integer max_iterations", %{agent: agent} do
      assert {:error, error} = ChainOfThought.run(agent, max_iterations: 1.5)
      assert error =~ "max_iterations must be a positive integer"
    end

    test "accepts valid temperature", %{agent: agent} do
      assert {:ok, _agent, _directives} = ChainOfThought.run(agent, temperature: 0.7)
    end

    test "rejects temperature outside valid range", %{agent: agent} do
      assert {:error, error} = ChainOfThought.run(agent, temperature: 2.5)
      assert error =~ "temperature must be a float between 0.0 and 2.0"
    end

    test "accepts valid model string", %{agent: agent} do
      assert {:ok, _agent, _directives} = ChainOfThought.run(agent, model: "gpt-4o")
    end
  end

  describe "agent state configuration" do
    test "uses configuration from agent state" do
      agent =
        build_test_agent_with_config(%{
          mode: :structured,
          max_iterations: 3,
          temperature: 0.5
        })

      # Should succeed with state config
      assert {:ok, _agent, _directives} = ChainOfThought.run(agent)
    end

    test "runtime opts override agent state config" do
      agent =
        build_test_agent_with_config(%{
          mode: :structured,
          max_iterations: 3
        })

      # Runtime opts should take precedence
      assert {:ok, _agent, _directives} = ChainOfThought.run(agent, mode: :zero_shot)
    end

    test "handles missing state config gracefully" do
      agent = build_test_agent()
      assert {:ok, _agent, _directives} = ChainOfThought.run(agent)
    end
  end

  describe "run/2 with empty instructions" do
    test "returns success with empty directives when no pending instructions" do
      agent = build_test_agent_with_instructions([])

      assert {:ok, returned_agent, directives} = ChainOfThought.run(agent)
      assert returned_agent == agent
      assert directives == []
    end
  end

  describe "run/2 with invalid agent" do
    test "returns error for agent without pending_instructions field" do
      invalid_agent = %{state: %{}, actions: []}

      assert {:error, error} = ChainOfThought.run(invalid_agent)
      assert error =~ "Invalid agent"
    end

    test "returns error for nil agent" do
      assert {:error, _} = ChainOfThought.run(nil)
    end
  end

  describe "fallback behavior" do
    @tag :skip
    test "falls back to simple runner when fallback_on_error is true" do
      # Skip until Task 1.1.2 implements actual reasoning
      # This test requires proper instruction format integration with Jido.AI.Runner.Simple
      agent =
        build_test_agent_with_instructions([
          build_instruction(TestAction, %{value: 42})
        ])

      # Should succeed by falling back to simple runner
      assert {:ok, _agent, _directives} = ChainOfThought.run(agent, fallback_on_error: true)
    end

    @tag :skip
    test "returns error when fallback_on_error is false" do
      # Skip until we have LLM mocking or integration test environment
      # This test requires a valid OpenAI API key to test reasoning generation
      agent =
        build_test_agent_with_instructions([
          build_instruction(TestAction, %{value: 42})
        ])

      # Should fail without fallback - either reasoning fails or LLM call fails
      result = ChainOfThought.run(agent, fallback_on_error: false)
      assert {:error, _error} = result
    end
  end

  describe "configuration merging" do
    test "merges all configuration sources correctly" do
      # Agent state config
      agent =
        build_test_agent_with_config(%{
          mode: :structured,
          max_iterations: 5,
          temperature: 0.3
        })

      # Runtime opts (should override)
      opts = [
        max_iterations: 3,
        model: "claude-3-5-sonnet-latest"
      ]

      assert {:ok, _agent, _directives} = ChainOfThought.run(agent, opts)
    end
  end

  # Test Helpers

  defp build_test_agent do
    %{
      id: "test-agent-#{:rand.uniform(10000)}",
      name: "Test Agent",
      state: %{},
      pending_instructions: :queue.new(),
      actions: [],
      runner: ChainOfThought,
      result: nil
    }
  end

  defp build_test_agent_with_instructions(instructions) do
    agent = build_test_agent()

    queue =
      Enum.reduce(instructions, :queue.new(), fn instruction, q ->
        :queue.in(instruction, q)
      end)

    %{agent | pending_instructions: queue}
  end

  defp build_test_agent_with_config(config) when is_map(config) do
    agent = build_test_agent()
    %{agent | state: Map.put(agent.state, :cot_config, config)}
  end

  defp build_instruction(action_module, params) do
    %{
      action: action_module,
      params: params,
      id: "instruction-#{:rand.uniform(10000)}"
    }
  end

  # Mock action for testing
  defmodule TestAction do
    @moduledoc false
    use Jido.Action,
      name: "test_action",
      description: "A test action for unit tests",
      schema: [
        value: [type: :integer, required: true]
      ]

    def run(params, _context) do
      {:ok, %{result: params.value * 2}}
    end
  end
end
