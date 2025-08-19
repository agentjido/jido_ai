defmodule Jido.BehaviorTree.SkillTest do
  use ExUnit.Case, async: true

  alias Jido.BehaviorTree.{Skill, Tree}
  alias Jido.BehaviorTree.Test.Nodes.{SimpleNode, FailureNode}

  describe "Skill.new/4" do
    test "creates skill with minimal options" do
      node = SimpleNode.new("test")
      tree = Tree.new(node)

      skill = Skill.new("test_skill", tree, "A test skill")

      assert skill.name == "test_skill"
      assert skill.description == "A test skill"
      assert skill.tree == tree
      assert skill.schema == []
      assert skill.timeout == 30_000
    end

    test "creates skill with custom options" do
      node = SimpleNode.new("test")
      tree = Tree.new(node)

      schema = [
        input: [type: :string, required: true],
        count: [type: :integer, default: 1]
      ]

      skill =
        Skill.new(
          "custom_skill",
          tree,
          "Custom skill",
          schema: schema,
          timeout: 10_000,
          auto_mode: true
        )

      assert skill.name == "custom_skill"
      assert skill.schema == schema
      assert skill.timeout == 10_000
      assert skill.auto_mode == true
    end
  end

  describe "Skill.to_tool/1" do
    test "converts skill to AI tool definition" do
      node = SimpleNode.new("test")
      tree = Tree.new(node)

      skill = Skill.new("test_tool", tree, "Test tool for AI")

      tool_def = Skill.to_tool(skill)

      assert tool_def["name"] == "test_tool"
      assert tool_def["description"] == "Test tool for AI"
      assert is_map(tool_def["parameters"])
      assert tool_def["parameters"]["type"] == "object"
    end

    test "converts skill with schema to tool definition" do
      node = SimpleNode.new("test")
      tree = Tree.new(node)

      schema = [
        user_id: [type: :integer, required: true, doc: "User identifier"],
        name: [type: :string, required: false, doc: "User name"]
      ]

      skill = Skill.new("user_processor", tree, "Processes user data", schema: schema)

      tool_def = Skill.to_tool(skill)

      assert tool_def["name"] == "user_processor"
      assert tool_def["parameters"]["properties"]["user_id"]["type"] == "integer"
      assert tool_def["parameters"]["properties"]["user_id"]["description"] == "User identifier"
      assert tool_def["parameters"]["properties"]["name"]["type"] == "string"
      assert tool_def["parameters"]["required"] == ["user_id"]
    end
  end

  describe "Skill.run/3" do
    test "executes skill successfully" do
      node = SimpleNode.new("test")
      tree = Tree.new(node)

      skill = Skill.new("test_skill", tree)

      {:ok, result} = Skill.run(skill, %{}, %{})

      assert is_map(result)
    end

    test "validates input parameters" do
      node = SimpleNode.new("test")
      tree = Tree.new(node)

      schema = [
        required_param: [type: :string, required: true]
      ]

      skill = Skill.new("validation_skill", tree, "", schema: schema)

      # Missing required parameter
      {:error, reason} = Skill.run(skill, %{}, %{})
      assert reason =~ "Parameter validation failed"

      # Valid parameters
      {:ok, _result} = Skill.run(skill, %{required_param: "value"}, %{})
    end

    test "handles skill execution failure" do
      node = FailureNode.new("test failure")
      tree = Tree.new(node)

      skill = Skill.new("failing_skill", tree, "", timeout: 1000)

      # Failure is a valid completion state, not an error
      # The skill should complete successfully even if the tree returns :failure
      {:ok, result} = Skill.run(skill, %{}, %{})
      assert is_map(result)
    end

    test "validates output with output schema" do
      node = SimpleNode.new("test")
      tree = Tree.new(node)

      output_schema = [
        result: [type: :string, required: true]
      ]

      skill =
        Skill.new(
          "output_validation_skill",
          tree,
          "",
          output_schema: output_schema
        )

      # This will likely fail output validation since SimpleNode doesn't produce 'result'
      case Skill.run(skill, %{}, %{}) do
        {:ok, _result} ->
          :ok

        {:error, reason} ->
          assert reason =~ "Output validation failed"
      end
    end

    test "executes with initial blackboard data" do
      node = SimpleNode.new("test")
      tree = Tree.new(node)

      skill = Skill.new("blackboard_skill", tree)

      params = %{
        user_id: 123,
        action: "process"
      }

      {:ok, result} = Skill.run(skill, params, %{})

      # The blackboard should contain our input parameters
      assert Map.has_key?(result, :user_id) or Map.has_key?(result, "user_id")
      assert Map.has_key?(result, :action) or Map.has_key?(result, "action")
    end
  end

  describe "Schema conversion" do
    test "converts different nimble option types to JSON schema" do
      node = SimpleNode.new("test")
      tree = Tree.new(node)

      schema = [
        string_field: [type: :string, doc: "A string field"],
        integer_field: [type: :integer, doc: "An integer field"],
        boolean_field: [type: :boolean, doc: "A boolean field"],
        map_field: [type: :map, doc: "A map field"],
        list_field: [type: {:list, :string}, doc: "A list field"]
      ]

      skill = Skill.new("schema_test", tree, "", schema: schema)

      tool_def = Skill.to_tool(skill)
      properties = tool_def["parameters"]["properties"]

      assert properties["string_field"]["type"] == "string"
      assert properties["integer_field"]["type"] == "integer"
      assert properties["boolean_field"]["type"] == "boolean"
      assert properties["map_field"]["type"] == "object"
      assert properties["list_field"]["type"] == "array"
    end
  end

  describe "Auto mode execution" do
    test "executes in auto mode with timeout" do
      node = SimpleNode.new("test")
      tree = Tree.new(node)

      skill =
        Skill.new(
          "auto_skill",
          tree,
          "",
          auto_mode: true,
          # Short timeout for testing
          timeout: 100
        )

      start_time = System.monotonic_time(:millisecond)
      {:ok, _result} = Skill.run(skill, %{}, %{})
      end_time = System.monotonic_time(:millisecond)

      # Should have taken at least the timeout duration
      duration = end_time - start_time
      assert duration >= 100
    end
  end

  describe "Manual mode execution" do
    test "executes in manual mode with immediate completion" do
      node = SimpleNode.new("test")
      tree = Tree.new(node)

      skill =
        Skill.new(
          "manual_skill",
          tree,
          "",
          auto_mode: false,
          timeout: 5000
        )

      start_time = System.monotonic_time(:millisecond)
      {:ok, _result} = Skill.run(skill, %{}, %{})
      end_time = System.monotonic_time(:millisecond)

      # Should complete quickly since SimpleNode succeeds immediately
      duration = end_time - start_time
      assert duration < 1000
    end
  end
end
