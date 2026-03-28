defmodule Jido.AI.Integration.ReActSteeringIntegrationTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Jido.AI
  alias Jido.AI.Reasoning.ReAct
  alias Jido.AI.TestSupport.StreamResponseFactory

  defmodule SteeringAgent do
    use Jido.AI.Agent,
      name: "react_steering_agent",
      model: "test:model",
      tools: []
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

    on_exit(fn ->
      :persistent_term.erase({__MODULE__, :llm_call_count})
    end)

    :ok
  end

  test "public steer continues the active request instead of starting a second one" do
    test_pid = self()

    Mimic.stub(ReqLLM.Generation, :stream_text, fn model, messages, _opts ->
      count = :persistent_term.get({__MODULE__, :llm_call_count}, 0) + 1
      :persistent_term.put({__MODULE__, :llm_call_count}, count)

      send(test_pid, {:llm_messages, count, messages})

      case count do
        1 ->
          Process.sleep(75)

          {:ok,
           StreamResponseFactory.build(
             [ReqLLM.StreamChunk.text("A1")],
             %{finish_reason: :stop, usage: %{input_tokens: 3, output_tokens: 1}},
             model
           )}

        2 ->
          {:ok,
           StreamResponseFactory.build(
             [ReqLLM.StreamChunk.text("A2")],
             %{finish_reason: :stop, usage: %{input_tokens: 4, output_tokens: 1}},
             model
           )}
      end
    end)

    Mimic.stub(ReqLLM.StreamResponse, :usage, fn
      %{usage: usage} -> usage
      _ -> nil
    end)

    {:ok, pid} = Jido.AgentServer.start_link(agent: SteeringAgent)
    on_exit(fn -> if Process.alive?(pid), do: Process.exit(pid, :kill) end)

    {:ok, request} = SteeringAgent.ask(pid, "Q1")

    assert_receive {:llm_messages, 1, first_messages}, 1_000
    assert user_contents(first_messages) == ["Q1"]
    assert assistant_contents(first_messages) == []

    assert {:ok, _agent} =
             ReAct.steer(
               pid,
               "Q2",
               expected_request_id: request.id,
               source: "/integration/test",
               extra_refs: %{origin: "suite"}
             )

    assert {:ok, "A2"} = SteeringAgent.await(request, timeout: 5_000)

    assert_receive {:llm_messages, 2, second_messages}, 1_000
    assert user_contents(second_messages) == ["Q1", "Q2"]
    assert assistant_contents(second_messages) == ["A1"]
  end

  test "public inject rejects idle agents" do
    {:ok, pid} = Jido.AgentServer.start_link(agent: SteeringAgent)
    on_exit(fn -> if Process.alive?(pid), do: Process.exit(pid, :kill) end)

    assert {:error, {:rejected, :idle}} = AI.inject(pid, "Programmatic input")
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
end
