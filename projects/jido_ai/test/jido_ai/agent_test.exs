defmodule Jido.AI.AgentTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Agent

  describe "start_link/1" do
    test "starts an AI agent with default configuration" do
      assert {:ok, pid} = Agent.start_link(id: "test_agent")
      assert is_pid(pid)
      assert Jido.agent_alive?(pid)
    end

    test "starts an AI agent with custom configuration" do
      opts = [
        id: "custom_agent",
        default_model: "openai:gpt-3.5-turbo",
        temperature: 0.5,
        max_tokens: 2000
      ]

      assert {:ok, pid} = Agent.start_link(opts)
      assert is_pid(pid)
      assert Jido.agent_alive?(pid)
    end
  end

  describe "generate_text/4" do
    setup do
      {:ok, pid} = Agent.start_link(id: "text_agent")
      %{agent: pid}
    end

    @tag :skip
    test "generates text with simple string prompt", %{agent: pid} do
      # This test requires actual AI service integration
      # Skipping for now as we need proper mocking setup
      assert {:error, _reason} = Agent.generate_text(pid, "Hello, how are you?")
    end

    @tag :skip
    test "generates text with options", %{agent: pid} do
      # This test requires actual AI service integration
      # Skipping for now as we need proper mocking setup
      opts = [
        model: "openai:gpt-4o",
        temperature: 0.3,
        max_tokens: 100
      ]

      assert {:error, _reason} = Agent.generate_text(pid, "Explain AI", opts)
    end

    @tag :skip
    test "handles generation errors", %{agent: pid} do
      # This test requires actual AI service integration
      # Skipping for now as we need proper mocking setup
      assert {:error, _reason} = Agent.generate_text(pid, "test prompt")
    end
  end

  describe "generate_object/4" do
    setup do
      {:ok, pid} = Agent.start_link(id: "object_agent")
      %{agent: pid}
    end

    @tag :skip
    test "generates structured object", %{agent: pid} do
      schema = %{
        type: "object",
        properties: %{
          name: %{type: "string"},
          age: %{type: "integer"}
        }
      }

      # This test requires actual AI service integration
      # Skipping for now as we need proper mocking setup
      assert {:error, _reason} = Agent.generate_object(pid, "Create a person", schema: schema)
    end

    test "requires schema parameter", %{agent: pid} do
      assert_raise ArgumentError, "schema option is required for generate_object", fn ->
        Agent.generate_object(pid, "Create something")
      end
    end

    @tag :skip
    test "handles object generation errors", %{agent: pid} do
      schema = %{type: "object", properties: %{}}

      # This test requires actual AI service integration
      # Skipping for now as we need proper mocking setup
      assert {:error, _reason} = Agent.generate_object(pid, "test", schema: schema)
    end
  end

  describe "stream_text/4" do
    setup do
      {:ok, pid} = Agent.start_link(id: "stream_agent")
      %{agent: pid}
    end

    @tag :skip
    test "streams text generation", %{agent: pid} do
      # This test requires actual AI service integration
      # Skipping for now as we need proper mocking setup
      assert {:error, _reason} = Agent.stream_text(pid, "Tell me a story")
    end

    @tag :skip
    test "handles streaming errors", %{agent: pid} do
      # This test requires actual AI service integration
      # Skipping for now as we need proper mocking setup
      assert {:error, _reason} = Agent.stream_text(pid, "test prompt")
    end
  end

  describe "stream_object/4" do
    setup do
      {:ok, pid} = Agent.start_link(id: "stream_object_agent")
      %{agent: pid}
    end

    @tag :skip
    test "streams object generation", %{agent: pid} do
      schema = %{
        type: "object",
        properties: %{
          items: %{type: "array"}
        }
      }

      # This test requires actual AI service integration
      # Skipping for now as we need proper mocking setup
      assert {:error, _reason} = Agent.stream_object(pid, "Generate a list", schema: schema)
    end

    test "requires schema parameter", %{agent: pid} do
      assert_raise ArgumentError, "schema option is required for stream_object", fn ->
        Agent.stream_object(pid, "Create something")
      end
    end
  end

  describe "error handling" do
    setup do
      {:ok, pid} = Agent.start_link(id: "error_agent")
      %{agent: pid}
    end

    @tag :skip
    test "handles timeout errors", %{agent: pid} do
      # This test requires actual timeout behavior testing
      # Skipping for now as we need proper mocking setup
      assert {:error, _reason} = Agent.generate_text(pid, "test", [], 50)
    end

    @tag :skip
    test "handles unexpected response format", %{agent: pid} do
      # This test requires actual AI service integration
      # Skipping for now as we need proper mocking setup
      assert {:error, _reason} = Agent.generate_text(pid, "test")
    end
  end
end
