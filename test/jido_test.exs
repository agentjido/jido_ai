defmodule JidoTest do
  use JidoTest.Case, async: true

  defmodule TestJido do
    use Jido, otp_app: :jido_test_app
  end

  @moduletag :capture_log

  describe "use Jido macro" do
    test "child_spec can be started under a supervisor" do
      # Set some config for :jido_test_app, TestJido
      Application.put_env(:jido_test_app, TestJido, name: TestJido)

      # Start the supervised instance
      {:ok, sup} = start_supervised(TestJido)

      # Verify it started a supervisor with the correct name
      assert Process.alive?(sup)
      # Could also check that the registry is started:
      registry_name = Module.concat(TestJido, "Registry")
      assert Process.whereis(registry_name)

      # or check dynamic supervisor
      dsup_name = Module.concat(TestJido, "AgentSupervisor")
      assert Process.whereis(dsup_name)
    end

    test "config is loaded from application env" do
      Application.put_env(:jido_test_app, TestJido, pubsub: "FakePubSub")
      assert TestJido.config()[:pubsub] == "FakePubSub"
    end
  end

  describe "get_agent/1" do
    setup context do
      test_name = context.test
      pubsub_name = Module.concat(TestJido, "#{test_name}.PubSub")
      registry_name = Module.concat(TestJido, "#{test_name}.Registry")

      {:ok, _} = start_supervised({Phoenix.PubSub, name: pubsub_name})
      {:ok, _} = start_supervised({Registry, keys: :unique, name: registry_name})

      # Temporarily override the Jido.Registry name for this test
      Application.put_env(:jido, :agent_registry, registry_name)
      on_exit(fn -> Application.delete_env(:jido, :agent_registry) end)

      {:ok, pubsub: pubsub_name, registry: registry_name}
    end

    test "returns the pid of an existing agent" do
      # Set up test agent using BasicAgent from test_agent.ex
      agent = JidoTest.TestAgents.BasicAgent.new("test_agent")
      {:ok, server} = Jido.Agent.Server.start_link(agent: agent)

      # Look up the agent by ID
      assert {:ok, pid} = Jido.get_agent("test_agent")
      assert pid == server
      assert Process.alive?(pid)
    end

    test "returns error for non-existent agent", %{pubsub: _pubsub} do
      assert {:error, :not_found} = Jido.get_agent("nonexistent")
    end
  end

  describe "clone_agent/3" do
    setup context do
      test_name = context.test
      pubsub_name = Module.concat(TestJido, "#{test_name}.PubSub")
      registry_name = Module.concat(TestJido, "#{test_name}.Registry")

      {:ok, _} = start_supervised({Phoenix.PubSub, name: pubsub_name})
      {:ok, _} = start_supervised({Registry, keys: :unique, name: registry_name})

      # Temporarily override the Jido.Registry name for this test
      Application.put_env(:jido, :agent_registry, registry_name)
      on_exit(fn -> Application.delete_env(:jido, :agent_registry) end)

      {:ok, pubsub: pubsub_name, registry: registry_name}
    end

    test "successfully clones an existing agent" do
      # Create source agent
      source_agent = JidoTest.TestAgents.BasicAgent.new("source_agent")
      {:ok, source_pid} = Jido.Agent.Server.start_link(agent: source_agent)

      # Clone the agent
      assert {:ok, cloned_pid} = Jido.clone_agent("source_agent", "cloned_agent")

      # Verify both agents exist and are different processes
      assert Process.alive?(source_pid)
      assert Process.alive?(cloned_pid)
      assert source_pid != cloned_pid

      # # Verify we can look up the cloned agent and IDs don't match
      # assert {:ok, ^cloned_pid} = Jido.get_agent("cloned_agent")
      # assert {:ok, source_topic} = Jido.get_agent_topic(source_pid)
      # assert {:ok, source_state} = Jido.get_agent_state(source_pid)
      # assert {:ok, cloned_topic} = Jido.get_agent_topic(cloned_pid)
      # assert {:ok, cloned_state} = Jido.get_agent_state(cloned_pid)
      # assert source_topic != cloned_topic
      # assert source_state.agent.id != cloned_state.agent.id
    end

    test "returns error when cloning non-existent agent", %{pubsub: _pubsub} do
      assert {:error, :not_found} = Jido.clone_agent("nonexistent", "new_agent")
    end
  end
end
