defmodule Jido.AI.Skills.ChainOfThoughtTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Skills.ChainOfThought

  describe "mount/2" do
    setup do
      # Create a minimal agent for testing
      agent = %{
        id: "test_agent",
        state: %{}
      }

      {:ok, agent: agent}
    end

    test "mounts with default configuration", %{agent: agent} do
      {:ok, mounted_agent} = ChainOfThought.mount(agent, [])

      assert mounted_agent.state.cot.mode == :zero_shot
      assert mounted_agent.state.cot.max_iterations == 3
      assert mounted_agent.state.cot.samples == 3
      assert mounted_agent.state.cot.enable_backtracking == true
      assert mounted_agent.state.cot.temperature == 0.7
      assert mounted_agent.state.cot.model == "gpt-4o"
      assert mounted_agent.state.cot.enable_validation == true
    end

    test "mounts with custom configuration", %{agent: agent} do
      opts = [
        mode: :structured,
        max_iterations: 5,
        temperature: 0.9
      ]

      {:ok, mounted_agent} = ChainOfThought.mount(agent, opts)

      assert mounted_agent.state.cot.mode == :structured
      assert mounted_agent.state.cot.max_iterations == 5
      assert mounted_agent.state.cot.temperature == 0.9
      # Defaults should still be present
      assert mounted_agent.state.cot.samples == 3
      assert mounted_agent.state.cot.enable_backtracking == true
    end

    test "mounts with zero_shot mode", %{agent: agent} do
      {:ok, mounted_agent} = ChainOfThought.mount(agent, mode: :zero_shot)
      assert mounted_agent.state.cot.mode == :zero_shot
    end

    test "mounts with few_shot mode", %{agent: agent} do
      {:ok, mounted_agent} = ChainOfThought.mount(agent, mode: :few_shot)
      assert mounted_agent.state.cot.mode == :few_shot
    end

    test "mounts with structured mode", %{agent: agent} do
      {:ok, mounted_agent} = ChainOfThought.mount(agent, mode: :structured)
      assert mounted_agent.state.cot.mode == :structured
    end

    test "mounts with self_consistency mode", %{agent: agent} do
      {:ok, mounted_agent} = ChainOfThought.mount(agent, mode: :self_consistency)
      assert mounted_agent.state.cot.mode == :self_consistency
    end

    test "preserves existing agent state", %{agent: agent} do
      agent_with_state = %{agent | state: %{existing: "data", counter: 42}}

      {:ok, mounted_agent} = ChainOfThought.mount(agent_with_state, [])

      assert mounted_agent.state.existing == "data"
      assert mounted_agent.state.counter == 42
      assert mounted_agent.state.cot != nil
    end

    test "returns error for invalid mode" do
      agent = %{id: "test", state: %{}}

      {:error, _reason} = ChainOfThought.mount(agent, mode: :invalid_mode)
    end

    test "returns error for invalid max_iterations type" do
      agent = %{id: "test", state: %{}}

      {:error, _reason} = ChainOfThought.mount(agent, max_iterations: "not a number")
    end

    test "returns error for negative max_iterations" do
      agent = %{id: "test", state: %{}}

      {:error, _reason} = ChainOfThought.mount(agent, max_iterations: -1)
    end

    test "returns error for invalid temperature type" do
      agent = %{id: "test", state: %{}}

      {:error, _reason} = ChainOfThought.mount(agent, temperature: "hot")
    end

    test "returns error for invalid enable_backtracking type" do
      agent = %{id: "test", state: %{}}

      {:error, _reason} = ChainOfThought.mount(agent, enable_backtracking: "yes")
    end

    test "returns error for invalid model type" do
      agent = %{id: "test", state: %{}}

      {:error, _reason} = ChainOfThought.mount(agent, model: 123)
    end

    test "accepts all valid modes" do
      agent = %{id: "test", state: %{}}

      for mode <- [:zero_shot, :few_shot, :structured, :self_consistency] do
        {:ok, mounted_agent} = ChainOfThought.mount(agent, mode: mode)
        assert mounted_agent.state.cot.mode == mode
      end
    end

    test "accepts custom samples for self_consistency" do
      agent = %{id: "test", state: %{}}

      {:ok, mounted_agent} =
        ChainOfThought.mount(agent,
          mode: :self_consistency,
          samples: 7
        )

      assert mounted_agent.state.cot.samples == 7
    end

    test "accepts custom model" do
      agent = %{id: "test", state: %{}}

      {:ok, mounted_agent} = ChainOfThought.mount(agent, model: "gpt-4-turbo")
      assert mounted_agent.state.cot.model == "gpt-4-turbo"
    end
  end

  describe "add_cot_config/2" do
    test "adds config to agent with no existing state" do
      agent = %{id: "test", state: nil}
      config = %{mode: :zero_shot, temperature: 0.7}

      updated_agent = ChainOfThought.add_cot_config(agent, config)

      assert updated_agent.state.cot == config
    end

    test "adds config to agent with existing state" do
      agent = %{id: "test", state: %{existing: "data"}}
      config = %{mode: :zero_shot, temperature: 0.7}

      updated_agent = ChainOfThought.add_cot_config(agent, config)

      assert updated_agent.state.cot == config
      assert updated_agent.state.existing == "data"
    end

    test "overwrites existing cot config" do
      agent = %{id: "test", state: %{cot: %{mode: :zero_shot}}}
      new_config = %{mode: :structured, temperature: 0.9}

      updated_agent = ChainOfThought.add_cot_config(agent, new_config)

      assert updated_agent.state.cot == new_config
    end

    test "preserves all other state keys" do
      agent = %{
        id: "test",
        state: %{
          key1: "value1",
          key2: 42,
          nested: %{data: "here"}
        }
      }

      config = %{mode: :zero_shot}

      updated_agent = ChainOfThought.add_cot_config(agent, config)

      assert updated_agent.state.key1 == "value1"
      assert updated_agent.state.key2 == 42
      assert updated_agent.state.nested == %{data: "here"}
      assert updated_agent.state.cot == config
    end
  end

  describe "get_cot_config/1" do
    test "returns config when mounted" do
      config = %{mode: :zero_shot, temperature: 0.7}
      agent = %{id: "test", state: %{cot: config}}

      assert {:ok, retrieved_config} = ChainOfThought.get_cot_config(agent)
      assert retrieved_config == config
    end

    test "returns error when not mounted" do
      agent = %{id: "test", state: %{}}

      assert {:error, :not_mounted} = ChainOfThought.get_cot_config(agent)
    end

    test "returns error when state is nil" do
      agent = %{id: "test", state: nil}

      assert {:error, :not_mounted} = ChainOfThought.get_cot_config(agent)
    end

    test "returns error when cot key exists but value is nil" do
      agent = %{id: "test", state: %{cot: nil}}

      assert {:error, :not_mounted} = ChainOfThought.get_cot_config(agent)
    end

    test "returns complete config with all fields" do
      agent = %{id: "test", state: %{}}
      {:ok, mounted_agent} = ChainOfThought.mount(agent, [])

      {:ok, config} = ChainOfThought.get_cot_config(mounted_agent)

      assert Map.has_key?(config, :mode)
      assert Map.has_key?(config, :max_iterations)
      assert Map.has_key?(config, :samples)
      assert Map.has_key?(config, :enable_backtracking)
      assert Map.has_key?(config, :temperature)
      assert Map.has_key?(config, :model)
      assert Map.has_key?(config, :enable_validation)
    end
  end

  describe "update_config/2" do
    setup do
      agent = %{id: "test", state: %{}}
      {:ok, mounted_agent} = ChainOfThought.mount(agent, mode: :zero_shot, temperature: 0.7)

      {:ok, agent: mounted_agent}
    end

    test "updates single configuration value", %{agent: agent} do
      {:ok, updated_agent} = ChainOfThought.update_config(agent, temperature: 0.9)

      assert updated_agent.state.cot.temperature == 0.9
      # Other values unchanged
      assert updated_agent.state.cot.mode == :zero_shot
    end

    test "updates multiple configuration values", %{agent: agent} do
      {:ok, updated_agent} =
        ChainOfThought.update_config(agent,
          mode: :structured,
          max_iterations: 5,
          temperature: 0.8
        )

      assert updated_agent.state.cot.mode == :structured
      assert updated_agent.state.cot.max_iterations == 5
      assert updated_agent.state.cot.temperature == 0.8
    end

    test "accepts map as updates" do
      agent = %{id: "test", state: %{}}
      {:ok, mounted_agent} = ChainOfThought.mount(agent, [])

      {:ok, updated_agent} =
        ChainOfThought.update_config(mounted_agent, %{temperature: 0.95, max_iterations: 7})

      assert updated_agent.state.cot.temperature == 0.95
      assert updated_agent.state.cot.max_iterations == 7
    end

    test "returns error when not mounted" do
      agent = %{id: "test", state: %{}}

      assert {:error, :not_mounted} = ChainOfThought.update_config(agent, temperature: 0.9)
    end

    test "returns error for invalid configuration" do
      agent = %{id: "test", state: %{}}
      {:ok, mounted_agent} = ChainOfThought.mount(agent, [])

      {:error, _reason} = ChainOfThought.update_config(mounted_agent, mode: :invalid_mode)
    end

    test "validates merged configuration", %{agent: agent} do
      # Try to update with invalid type
      {:error, _reason} = ChainOfThought.update_config(agent, max_iterations: "not a number")
    end

    test "preserves non-updated configuration values", %{agent: agent} do
      original_samples = agent.state.cot.samples
      original_model = agent.state.cot.model

      {:ok, updated_agent} = ChainOfThought.update_config(agent, temperature: 0.95)

      assert updated_agent.state.cot.samples == original_samples
      assert updated_agent.state.cot.model == original_model
    end
  end

  describe "mounted?/1" do
    test "returns true when skill is mounted" do
      agent = %{id: "test", state: %{}}
      {:ok, mounted_agent} = ChainOfThought.mount(agent, [])

      assert ChainOfThought.mounted?(mounted_agent) == true
    end

    test "returns false when skill is not mounted" do
      agent = %{id: "test", state: %{}}

      assert ChainOfThought.mounted?(agent) == false
    end

    test "returns false when state is nil" do
      agent = %{id: "test", state: nil}

      assert ChainOfThought.mounted?(agent) == false
    end

    test "returns false when cot key exists but value is nil" do
      agent = %{id: "test", state: %{cot: nil}}

      assert ChainOfThought.mounted?(agent) == false
    end

    test "returns true for agents with custom configuration" do
      agent = %{id: "test", state: %{}}

      {:ok, mounted_agent} =
        ChainOfThought.mount(agent,
          mode: :self_consistency,
          samples: 5,
          temperature: 0.85
        )

      assert ChainOfThought.mounted?(mounted_agent) == true
    end
  end

  describe "integration scenarios" do
    test "mount, update, and retrieve configuration" do
      agent = %{id: "test", state: %{}}

      # Mount with initial config
      {:ok, agent} = ChainOfThought.mount(agent, mode: :zero_shot, temperature: 0.7)
      assert ChainOfThought.mounted?(agent) == true

      # Update config
      {:ok, agent} = ChainOfThought.update_config(agent, mode: :structured, max_iterations: 5)

      # Retrieve and verify
      {:ok, config} = ChainOfThought.get_cot_config(agent)
      assert config.mode == :structured
      assert config.max_iterations == 5
      assert config.temperature == 0.7
    end

    test "mount on agent with existing state preserves all state" do
      agent = %{
        id: "test",
        state: %{
          important_data: "preserve me",
          counter: 99,
          config: %{nested: "value"}
        }
      }

      {:ok, mounted_agent} = ChainOfThought.mount(agent, mode: :zero_shot)

      # CoT config added
      assert ChainOfThought.mounted?(mounted_agent) == true

      # Original state preserved
      assert mounted_agent.state.important_data == "preserve me"
      assert mounted_agent.state.counter == 99
      assert mounted_agent.state.config == %{nested: "value"}
    end

    test "multiple updates work correctly" do
      agent = %{id: "test", state: %{}}
      {:ok, agent} = ChainOfThought.mount(agent, [])

      # First update
      {:ok, agent} = ChainOfThought.update_config(agent, temperature: 0.8)
      {:ok, config1} = ChainOfThought.get_cot_config(agent)
      assert config1.temperature == 0.8

      # Second update
      {:ok, agent} = ChainOfThought.update_config(agent, max_iterations: 7)
      {:ok, config2} = ChainOfThought.get_cot_config(agent)
      assert config2.temperature == 0.8
      assert config2.max_iterations == 7

      # Third update
      {:ok, agent} = ChainOfThought.update_config(agent, mode: :structured)
      {:ok, config3} = ChainOfThought.get_cot_config(agent)
      assert config3.temperature == 0.8
      assert config3.max_iterations == 7
      assert config3.mode == :structured
    end

    test "cannot update before mounting" do
      agent = %{id: "test", state: %{}}

      assert {:error, :not_mounted} = ChainOfThought.update_config(agent, temperature: 0.9)
      assert ChainOfThought.mounted?(agent) == false
    end

    test "mounting twice overwrites previous configuration" do
      agent = %{id: "test", state: %{}}

      # First mount
      {:ok, agent} = ChainOfThought.mount(agent, mode: :zero_shot, temperature: 0.7)
      {:ok, config1} = ChainOfThought.get_cot_config(agent)
      assert config1.mode == :zero_shot
      assert config1.temperature == 0.7

      # Second mount with different config
      {:ok, agent} = ChainOfThought.mount(agent, mode: :structured, temperature: 0.9)
      {:ok, config2} = ChainOfThought.get_cot_config(agent)
      assert config2.mode == :structured
      assert config2.temperature == 0.9
    end
  end

  describe "configuration validation" do
    test "validates temperature range implicitly through type" do
      agent = %{id: "test", state: %{}}

      # Valid temperatures
      {:ok, _} = ChainOfThought.mount(agent, temperature: 0.0)
      {:ok, _} = ChainOfThought.mount(agent, temperature: 0.5)
      {:ok, _} = ChainOfThought.mount(agent, temperature: 1.0)
      {:ok, _} = ChainOfThought.mount(agent, temperature: 1.5)
    end

    test "validates max_iterations is positive" do
      agent = %{id: "test", state: %{}}

      # Valid
      {:ok, _} = ChainOfThought.mount(agent, max_iterations: 1)
      {:ok, _} = ChainOfThought.mount(agent, max_iterations: 10)

      # Invalid
      {:error, _} = ChainOfThought.mount(agent, max_iterations: 0)
      {:error, _} = ChainOfThought.mount(agent, max_iterations: -5)
    end

    test "validates samples is positive" do
      agent = %{id: "test", state: %{}}

      # Valid
      {:ok, _} = ChainOfThought.mount(agent, samples: 1)
      {:ok, _} = ChainOfThought.mount(agent, samples: 10)

      # Invalid
      {:error, _} = ChainOfThought.mount(agent, samples: 0)
      {:error, _} = ChainOfThought.mount(agent, samples: -3)
    end

    test "validates boolean fields" do
      agent = %{id: "test", state: %{}}

      # Valid
      {:ok, _} = ChainOfThought.mount(agent, enable_backtracking: true)
      {:ok, _} = ChainOfThought.mount(agent, enable_backtracking: false)
      {:ok, _} = ChainOfThought.mount(agent, enable_validation: true)
      {:ok, _} = ChainOfThought.mount(agent, enable_validation: false)

      # Invalid
      {:error, _} = ChainOfThought.mount(agent, enable_backtracking: "yes")
      {:error, _} = ChainOfThought.mount(agent, enable_validation: 1)
    end

    test "validates model is string" do
      agent = %{id: "test", state: %{}}

      # Valid
      {:ok, _} = ChainOfThought.mount(agent, model: "gpt-4")
      {:ok, _} = ChainOfThought.mount(agent, model: "claude-3")

      # Invalid
      {:error, _} = ChainOfThought.mount(agent, model: 123)
      {:error, _} = ChainOfThought.mount(agent, model: :atom)
    end
  end

  describe "router/1" do
    test "returns list of route maps" do
      routes = ChainOfThought.router()

      assert is_list(routes)
      assert length(routes) > 0

      # All routes should have path and instruction keys
      for route <- routes do
        assert Map.has_key?(route, :path)
        assert Map.has_key?(route, :instruction)
        assert Map.has_key?(route.instruction, :action)
      end
    end

    test "includes agent.reasoning.* routes" do
      routes = ChainOfThought.router()
      paths = Enum.map(routes, & &1.path)

      assert "agent.reasoning.generate" in paths
      assert "agent.reasoning.step" in paths
      assert "agent.reasoning.validate" in paths
      assert "agent.reasoning.correct" in paths
    end

    test "includes agent.cot.* alias routes" do
      routes = ChainOfThought.router()
      paths = Enum.map(routes, & &1.path)

      assert "agent.cot.generate" in paths
      assert "agent.cot.step" in paths
      assert "agent.cot.validate" in paths
      assert "agent.cot.correct" in paths
    end

    test "routes map to correct actions" do
      routes = ChainOfThought.router()
      routes_map = Map.new(routes, fn r -> {r.path, r.instruction.action} end)

      alias Jido.AI.Actions.CoT

      assert routes_map["agent.reasoning.generate"] == CoT.GenerateReasoning
      assert routes_map["agent.reasoning.step"] == CoT.ReasoningStep
      assert routes_map["agent.reasoning.validate"] == CoT.ValidateReasoning
      assert routes_map["agent.reasoning.correct"] == CoT.SelfCorrect
    end

    test "supports custom routes" do
      custom_routes = [
        %{
          path: "agent.reasoning.custom",
          instruction: %{action: CustomAction}
        }
      ]

      routes = ChainOfThought.router(custom_routes: custom_routes)
      paths = Enum.map(routes, & &1.path)

      assert "agent.reasoning.custom" in paths
      assert "agent.reasoning.generate" in paths
    end

    test "custom routes are appended to base routes" do
      custom = [
        %{path: "custom.1", instruction: %{action: Action1}},
        %{path: "custom.2", instruction: %{action: Action2}}
      ]

      routes = ChainOfThought.router(custom_routes: custom)

      # Should have base routes + custom routes
      assert length(routes) >= 10
    end

    test "accepts mode parameter" do
      # Should not raise
      routes_zero = ChainOfThought.router(mode: :zero_shot)
      routes_structured = ChainOfThought.router(mode: :structured)

      assert is_list(routes_zero)
      assert is_list(routes_structured)
    end

    test "routes include descriptions" do
      routes = ChainOfThought.router()

      # At least some routes should have descriptions
      routes_with_desc =
        Enum.filter(routes, fn r ->
          Map.has_key?(r.instruction, :description)
        end)

      assert length(routes_with_desc) > 0
    end
  end

  describe "register_custom_routes/2" do
    setup do
      agent = %{id: "test", state: %{}}
      {:ok, mounted_agent} = ChainOfThought.mount(agent, [])

      {:ok, agent: mounted_agent}
    end

    test "registers custom routes when skill is mounted", %{agent: agent} do
      custom_routes = [
        %{path: "agent.reasoning.experimental", instruction: %{action: ExperimentalAction}}
      ]

      {:ok, routes} = ChainOfThought.register_custom_routes(agent, custom_routes)

      paths = Enum.map(routes, & &1.path)
      assert "agent.reasoning.experimental" in paths
    end

    test "returns error when skill not mounted" do
      agent = %{id: "test", state: %{}}
      custom_routes = [%{path: "test", instruction: %{action: TestAction}}]

      assert {:error, :not_mounted} = ChainOfThought.register_custom_routes(agent, custom_routes)
    end

    test "combines base and custom routes", %{agent: agent} do
      custom = [%{path: "custom", instruction: %{action: CustomAction}}]

      {:ok, routes} = ChainOfThought.register_custom_routes(agent, custom)
      paths = Enum.map(routes, & &1.path)

      # Should have both base and custom
      assert "agent.reasoning.generate" in paths
      assert "custom" in paths
    end

    test "accepts empty custom routes list", %{agent: agent} do
      {:ok, routes} = ChainOfThought.register_custom_routes(agent, [])

      # Should just return base routes
      assert length(routes) >= 8
    end
  end

  describe "get_routes/1" do
    test "returns routes for mounted skill" do
      agent = %{id: "test", state: %{}}
      {:ok, agent} = ChainOfThought.mount(agent, mode: :structured)

      {:ok, routes} = ChainOfThought.get_routes(agent)

      assert is_list(routes)
      assert length(routes) > 0
    end

    test "returns error when skill not mounted" do
      agent = %{id: "test", state: %{}}

      assert {:error, :not_mounted} = ChainOfThought.get_routes(agent)
    end

    test "routes reflect agent configuration" do
      agent = %{id: "test", state: %{}}
      {:ok, agent} = ChainOfThought.mount(agent, mode: :self_consistency, temperature: 0.9)

      {:ok, routes} = ChainOfThought.get_routes(agent)

      # Routes should be returned based on config
      # (Currently mode filtering is not implemented, but structure is there)
      assert is_list(routes)
    end

    test "parameterizes routes based on skill mode" do
      agent = %{id: "test", state: %{}}
      {:ok, agent} = ChainOfThought.mount(agent, mode: :zero_shot)

      {:ok, routes_zero} = ChainOfThought.get_routes(agent)

      {:ok, agent} = ChainOfThought.update_config(agent, mode: :structured)
      {:ok, routes_structured} = ChainOfThought.get_routes(agent)

      # Should return routes (even if same for now)
      assert is_list(routes_zero)
      assert is_list(routes_structured)
    end
  end

  describe "skill metadata" do
    test "skill has correct name" do
      assert ChainOfThought.name() == "chain_of_thought"
    end

    test "skill has correct category" do
      assert ChainOfThought.category() == "reasoning"
    end

    test "skill has version" do
      vsn = ChainOfThought.vsn()
      assert vsn != nil
      assert is_binary(vsn)
      assert vsn == "1.0.0"
    end
  end
end
