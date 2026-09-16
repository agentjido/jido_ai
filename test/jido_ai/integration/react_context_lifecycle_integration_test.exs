defmodule Jido.AI.Integration.ReActContextLifecycleIntegrationTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Jido.AI.{Configuration, Profile, Orchestration}
  alias Jido.Thread
  alias Jido.AI.TestSupport.StreamResponseFactory

  defmodule EchoTool do
    use Jido.Action,
      name: "echo",
      description: "Echoes input text",
      schema: Zoi.object(%{text: Zoi.string()})

    def run(%{text: text}, _context), do: {:ok, %{text: text}}
  end

  defmodule ContextLifecycleAgent do
    use Jido.AI.Agent, name: "context_lifecycle_agent"

    agent do
      schema Zoi.object(%{last_result: Zoi.any() |> Zoi.default(nil), messages: Jido.AI.Thread.Projection.schema()})

      ai :assistant do
        instructions("Initial prompt")
        model("openai:gpt-4o-mini")
        reasoning(:react)

        tools do
          action(EchoTool)
        end

        requests(mode: :session, streaming: true)
        memory(history: :messages)
        observability(diagnostics_content: true)
        result(into: :last_result)
      end
    end

    routes do
      route("ai.react.query", ai: :assistant)
    end
  end

  setup :set_mimic_from_context

  setup do
    if is_nil(Process.whereis(Jido)) do
      start_supervised!({Jido, name: Jido})
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

    # Inspect the committed conversation before reset.
    state_before_reset = conversation(pid)

    assert non_system_messages(state_before_reset) == [
             %{role: :user, content: "Q1"},
             %{role: :assistant, content: "A1"},
             %{role: :user, content: "Q2"},
             %{role: :assistant, content: "A2"}
           ]

    {:ok, replacement_context} =
      Jido.AI.Thread.Projection.append(
        Jido.Thread.new(metadata: %{system_prompt: "Reset prompt"}),
        [ReqLLM.Context.user("Reset seed")]
      )

    # Reset context through the Orchestration context command.
    reset_signal =
      Jido.Signal.new!(
        "jido.ai.context.modify",
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

    # After reset, committed conversation is replaced immediately.
    state_after_reset = conversation(pid)
    assert hd(state_after_reset) == %{role: :system, content: "Reset prompt"}
    assert {:ok, %Profile{instructions: "Reset prompt"} = profile} = Configuration.profile(fetch_agent(pid))

    assert {:ok, [%{role: :user, content: seed}]} =
             Jido.AI.Orchestration.Transcript.read(fetch_agent(pid).state, profile)

    assert Jido.AI.Query.summarize(seed) == "Reset seed"
    assert non_system_messages(state_after_reset) == [%{role: :user, content: "Reset seed"}]

    # Turn 3 should project only from reset context, not from pre-reset turns.
    assert {:ok, "A3"} = ContextLifecycleAgent.ask_sync(pid, "Q3", timeout: 5_000)

    assert_receive {:llm_messages, third_messages}, 1_000
    assert user_contents(third_messages) == ["Reset seed", "Q3"]
    refute "Q1" in user_contents(third_messages)
    refute "Q2" in user_contents(third_messages)

    # Committed conversation now reflects post-reset conversation only.
    state_final = conversation(pid)

    assert non_system_messages(state_final) == [
             %{role: :user, content: "Reset seed"},
             %{role: :user, content: "Q3"},
             %{role: :assistant, content: "A3"}
           ]

    session_thread = session_thread(pid)

    # The Agent-owned log is append-only: reset is a context operation entry.
    [context_op] = Thread.filter_by_kind(session_thread, :ai_context_operation)
    assert {:ok, operation} = Jido.AI.Thread.Operation.decode(context_op)
    assert operation.op_id == "op_reset_demo"
    assert operation.context_ref == "default"
    assert operation.operation.type == :replace
    assert operation.operation.reason == :manual

    # The session thread still preserves the full audit history of all turns.
    ai_messages = Thread.filter_by_kind(session_thread, :ai_message)

    assert Enum.count(ai_messages, &(entry_role(&1) == :user)) == 3
    assert Enum.count(ai_messages, &(entry_role(&1) == :assistant)) == 3
    assert Enum.any?(ai_messages, &(entry_content(&1) == "Q1"))
    assert Enum.any?(ai_messages, &(entry_content(&1) == "Q2"))
    assert Enum.any?(ai_messages, &(entry_content(&1) == "Q3"))
    refute Enum.any?(ai_messages, &(entry_content(&1) == "Reset seed"))
  end

  defp conversation(pid) do
    assert {:ok, view} = Orchestration.snapshot(pid, include_content: true)
    view.details.conversation
  end

  defp session_thread(pid) do
    fetch_agent(pid).state.messages.thread
  end

  defp fetch_agent(pid) do
    Jido.AgentServer.agent(pid)
  end

  defp non_system_messages(messages) do
    messages
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

  defp user_contents(%ReqLLM.Context{} = context),
    do: context |> ReqLLM.Context.to_list() |> user_contents()

  defp assistant_contents(messages) when is_list(messages) do
    messages
    |> Enum.filter(&(message_role(&1) == :assistant))
    |> Enum.map(&message_content/1)
  end

  defp assistant_contents(%ReqLLM.Context{} = context),
    do: context |> ReqLLM.Context.to_list() |> assistant_contents()

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

  defp message_content(%{content: parts}) when is_list(parts) do
    parts
    |> Enum.flat_map(fn
      %ReqLLM.Message.ContentPart{text: text} when is_binary(text) -> [text]
      %{text: text} when is_binary(text) -> [text]
      _ -> []
    end)
    |> Enum.join("")
  end

  defp message_content(message) when is_map(message) do
    Jido.AI.Query.summarize(Map.get(message, :content, Map.get(message, "content")))
  end

  defp entry_role(entry) when is_map(entry) do
    {:ok, message} = Jido.AI.Thread.Projection.message(entry)
    message.role
  end

  defp entry_content(entry) when is_map(entry) do
    {:ok, message} = Jido.AI.Thread.Projection.message(entry)
    Jido.AI.Query.summarize(message.content)
  end
end
