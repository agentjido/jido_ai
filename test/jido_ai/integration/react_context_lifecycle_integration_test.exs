defmodule Jido.AI.Integration.ReActContextLifecycleIntegrationTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.AI.Context
  alias Jido.AI.TestSupport.StreamResponseFactory
  alias Jido.Thread
  alias Jido.Thread.Agent, as: ThreadAgent

  defmodule EchoTool do
    use Jido.Action,
      name: "echo",
      description: "Echoes input text",
      schema: Zoi.object(%{text: Zoi.string()})

    def run(%{text: text}, _context), do: {:ok, %{text: text}}
  end

  defmodule ContextLifecycleAgent do
    use Jido.AI.Agent,
      name: "context_lifecycle_agent",
      model: "test:model",
      system_prompt: "Initial prompt",
      tools: [EchoTool]
  end

  setup :set_mimic_from_context

  setup do
    if is_nil(Process.whereis(Jido.Registry)) do
      start_supervised!({Registry, keys: :unique, name: Jido.Registry})
    end

    if is_nil(Process.whereis(Jido.AgentSupervisor)) do
      start_supervised!({DynamicSupervisor, strategy: :one_for_one, name: Jido.AgentSupervisor})
    end

    if is_nil(Process.whereis(Jido.TaskSupervisor)) do
      start_supervised!({Task.Supervisor, name: Jido.TaskSupervisor})
    end

    test_pid = self()

    # Mock LLM responses deterministically based on the latest user message
    # so the end-to-end context lifecycle is easy to reason about.
    Mimic.stub(ReqLLM.Generation, :stream_text, fn model, messages, _opts ->
      # Emit raw LLM input back to the test process; this is how we assert the
      # exact projected context sent to ReqLLM on each turn.
      send(test_pid, {:llm_messages, messages})

      text =
        case List.last(user_contents(messages)) do
          "Q1" -> "A1"
          "Q2" -> "A2"
          "Q3" -> "A3"
          other -> "unexpected: #{inspect(other)}"
        end

      {:ok,
       StreamResponseFactory.build(
         [ReqLLM.StreamChunk.text(text)],
         %{finish_reason: :stop, usage: %{input_tokens: 5, output_tokens: 2}},
         model
       )}
    end)

    Mimic.stub(ReqLLM.StreamResponse, :usage, fn
      %{usage: usage} -> usage
      _ -> nil
    end)

    :ok
  end

  test "developer flow: inspect accumulated context, reset it, and continue on new context lane state" do
    {:ok, pid} = Jido.AgentServer.start_link(agent: ContextLifecycleAgent)
    on_exit(fn -> if Process.alive?(pid), do: Process.exit(pid, :kill) end)

    # Turn 1: first question, no prior assistant history.
    assert {:ok, "A1"} = ContextLifecycleAgent.ask_sync(pid, "Q1", timeout: 5_000)

    assert_receive {:llm_messages, first_messages}, 1_000
    assert user_contents(first_messages) == ["Q1"]
    assert assistant_contents(first_messages) == []

    # Turn 2: prior user/assistant messages should now be included.
    assert {:ok, "A2"} = ContextLifecycleAgent.ask_sync(pid, "Q2", timeout: 5_000)

    assert_receive {:llm_messages, second_messages}, 1_000
    assert user_contents(second_messages) == ["Q1", "Q2"]
    assert assistant_contents(second_messages) == ["A1"]

    # Inspect the materialized ReAct context before reset.
    state_before_reset = strategy_state(pid)

    assert non_system_messages(state_before_reset.context) == [
             %{role: :user, content: "Q1"},
             %{role: :assistant, content: "A1"},
             %{role: :user, content: "Q2"},
             %{role: :assistant, content: "A2"}
           ]

    replacement_context =
      Context.new(system_prompt: "Reset prompt")
      |> Context.append_user("Reset seed")

    # Reset context through the canonical strategy command surface.
    reset_signal =
      Jido.Signal.new!(
        "ai.react.context.modify",
        %{
          op_id: "op_reset_demo",
          context_ref: "default",
          operation: %{
            type: :replace,
            reason: :manual,
            result_context: replacement_context
          }
        },
        source: "/integration/test"
      )

    assert {:ok, _agent} = Jido.AgentServer.call(pid, reset_signal, 5_000)

    # After reset, materialized strategy context is replaced immediately.
    state_after_reset = strategy_state(pid)
    assert state_after_reset.context.system_prompt == "Reset prompt"
    assert state_after_reset.config.system_prompt == "Reset prompt"
    assert non_system_messages(state_after_reset.context) == [%{role: :user, content: "Reset seed"}]

    # Turn 3 should project only from reset context, not from pre-reset turns.
    assert {:ok, "A3"} = ContextLifecycleAgent.ask_sync(pid, "Q3", timeout: 5_000)

    assert_receive {:llm_messages, third_messages}, 1_000
    assert user_contents(third_messages) == ["Reset seed", "Q3"]
    refute "Q1" in user_contents(third_messages)
    refute "Q2" in user_contents(third_messages)

    # Materialized strategy context now reflects post-reset conversation only.
    state_final = strategy_state(pid)

    assert non_system_messages(state_final.context) == [
             %{role: :user, content: "Reset seed"},
             %{role: :user, content: "Q3"},
             %{role: :assistant, content: "A3"}
           ]

    core_thread =
      pid
      |> fetch_agent()
      |> ThreadAgent.get()

    # Core thread is append-only: reset is represented as a context operation entry.
    [context_op] = Thread.filter_by_kind(core_thread, :ai_context_operation)
    assert context_op.payload.op_id == "op_reset_demo"
    assert context_op.payload.context_ref == "default"
    assert context_op.payload.operation.type == :replace
    assert context_op.payload.operation.reason == :manual

    # Core thread still preserves full audit history of all user/assistant turns.
    ai_messages = Thread.filter_by_kind(core_thread, :ai_message)

    assert Enum.count(ai_messages, &(entry_role(&1) == :user)) == 3
    assert Enum.count(ai_messages, &(entry_role(&1) == :assistant)) == 3
    assert Enum.any?(ai_messages, &(entry_content(&1) == "Q1"))
    assert Enum.any?(ai_messages, &(entry_content(&1) == "Q2"))
    assert Enum.any?(ai_messages, &(entry_content(&1) == "Q3"))
    refute Enum.any?(ai_messages, &(entry_content(&1) == "Reset seed"))
  end

  defp strategy_state(pid) do
    pid
    |> fetch_agent()
    |> StratState.get(%{})
  end

  defp fetch_agent(pid) do
    {:ok, server_state} = Jido.AgentServer.state(pid)
    server_state.agent
  end

  defp non_system_messages(%Context{} = context) do
    context
    |> Context.to_messages()
    |> Enum.reject(&(message_role(&1) == :system))
    |> Enum.map(fn message ->
      %{
        role: message_role(message),
        content: message_content(message)
      }
    end)
  end

  defp user_contents(messages) when is_list(messages) do
    messages
    |> Enum.filter(&(message_role(&1) == :user))
    |> Enum.map(&message_content/1)
  end

  defp assistant_contents(messages) when is_list(messages) do
    messages
    |> Enum.filter(&(message_role(&1) == :assistant))
    |> Enum.map(&message_content/1)
  end

  defp message_role(message) when is_map(message) do
    case Map.get(message, :role, Map.get(message, "role")) do
      role when is_atom(role) -> role
      "user" -> :user
      "assistant" -> :assistant
      "tool" -> :tool
      "system" -> :system
      _ -> :unknown
    end
  end

  defp message_content(message) when is_map(message) do
    Map.get(message, :content, Map.get(message, "content"))
  end

  defp entry_role(entry) when is_map(entry) do
    entry
    |> Map.get(:payload, %{})
    |> Map.get(:role)
  end

  defp entry_content(entry) when is_map(entry) do
    entry
    |> Map.get(:payload, %{})
    |> Map.get(:content)
  end
end
