import ExUnit.Assertions

[beam_dir] = System.argv()
true = Code.prepend_path(beam_dir)
assert :code.is_loaded(JidoAI.Examples.UnloadedTool) == false

alias JidoAI.Examples.MockLLM

{:ok, mock} =
  MockLLM.start_link(
    script: [
      %{reply: {:tools, [%{id: "generated", name: "generated", arguments: %{n: 21}}]}},
      %{reply: {:text, "Forty-two"}}
    ]
  )

{:ok, _} = Jido.start_link(name: :unloaded_tool_example)

profile = %{
  id: :assistant,
  models: %{answer: MockLLM.model()},
  reasoning: %{method: :react, model: :answer},
  tools: [%{name: "generated", target: JidoAI.Examples.UnloadedTool}],
  result: %{schema: nil, into: :reply}
}

base = %{
  name: "generated_tool_session",
  schema: Zoi.object(%{reply: Zoi.string() |> Zoi.default("")}),
  routes: [{"ai.ask", Jido.AI.Authoring.ai(:assistant)}]
}

{:ok, definition} = Jido.AI.Authoring.lower(base, [profile])
assert :code.is_loaded(JidoAI.Examples.UnloadedTool) != false
{:ok, server} = Jido.start_agent(:unloaded_tool_example, Jido.Agent.instantiate!(definition))

{:ok, request} =
  Jido.AI.Request.create_and_send(server, "Double 21",
    signal_type: "ai.ask",
    source: "/example",
    context: %{ai: %{assistant: %{options: MockLLM.options(mock)}}}
  )

assert {:ok, "Forty-two"} = Jido.AI.Request.await(request)
assert %{remaining: [], unexpected: [], waiting: [], requests: [_, second]} = MockLLM.report(mock)
tool = Enum.find(second.body["messages"], &(&1["role"] == "tool"))
assert tool["tool_call_id"] == "generated"
assert Jason.decode!(tool["content"]) == %{"ok" => true, "result" => %{"value" => 42}}
:ok = Jido.AgentServer.stop(server)
GenServer.stop(mock)
IO.puts("UNLOADED_TOOL_SESSION_OK")
