defmodule JidoAI.Examples.RequestScopeTest do
  use JidoAI.Examples.Case
  alias JidoAI.Examples.RequestScope.{Agent, Echo, Open}
  alias JidoAI.Examples.PublicAgent.ObjectAgent

  setup do
    old = Application.fetch_env(:jido_ai, :model_aliases)
    Application.put_env(:jido_ai, :model_aliases, %{example: MockLLM.model()})

    on_exit(fn ->
      case old do
        {:ok, value} -> Application.put_env(:jido_ai, :model_aliases, value)
        :error -> Application.delete_env(:jido_ai, :model_aliases)
      end
    end)

    :ok
  end

  @tag history_case: "HIST-11/raw-bypass"
  test "raw and custom output requests leave the default typed contract intact", %{jido: jido} do
    {mock, context} =
      mock([
        %{reply: {:text, "Plain"}},
        %{reply: {:object, %{count: 3}}},
        %{reply: {:object, %{answer: "Default"}}}
      ])

    server = start_agent(jido, ObjectAgent.new!())
    assert {:ok, "Plain"} = ObjectAgent.ask_sync(server, "Raw", context: context, output: :raw)

    assert {:ok, %{count: 3}} =
             ObjectAgent.ask_sync(server, "Count",
               context: context,
               output: [object_schema: Zoi.object(%{count: Zoi.integer()}), retries: "0"]
             )

    assert {:ok, %{answer: "Default"}} = ObjectAgent.ask_sync(server, "Default", context: context)
    [raw, custom, default] = MockLLM.report(mock).requests
    refute raw.body["response_format"]
    assert custom.body["response_format"]["json_schema"]["schema"]["properties"]["count"]
    assert default.body["response_format"]["json_schema"]["schema"]["properties"]["answer"]
    assert_script_done(mock)
  end

  @tag history_case: "HIST-11/imported-schema"
  test "a request accepts an imported JSON object schema", %{jido: jido} do
    {mock, context} = mock([%{reply: {:object, %{count: 4}}}])

    schema =
      Jason.decode!(
        ~s({"type":"object","properties":{"count":{"type":"integer"}},"required":["count"]})
      )

    server = start_agent(jido, ObjectAgent.new!())

    assert {:ok, %{"count" => 4}} =
             ObjectAgent.ask_sync(server, "Count", context: context, output: %{schema: schema})

    assert_script_done(mock)
  end

  test "empty and named tool selections affect one request and actual execution", %{jido: jido} do
    {mock, context} =
      mock([
        %{reply: {:text, "No tools"}},
        %{reply: {:tools, [%{id: "alias-call", name: "renamed", arguments: %{value: 8}}]}},
        %{reply: {:text, "Used alias"}},
        %{reply: {:text, "Original tools"}}
      ])

    server = start_agent(jido, Agent.new!())
    assert {:ok, "No tools"} = Agent.ask_sync(server, "None", context: context, allowed_tools: [])

    assert {:ok, "Used alias"} =
             Agent.ask_sync(server, "Alias",
               context: context,
               tools: %{"renamed" => Echo},
               allowed_tools: ["renamed"],
               max_iterations: 2
             )

    assert {:ok, "Original tools"} = Agent.ask_sync(server, "Default", context: context)
    [none, alias_call, result, default] = MockLLM.report(mock).requests
    refute none.body["tools"]
    assert names(alias_call) == ["renamed"]
    tool_result = Enum.find(result.body["messages"], &(&1["role"] == "tool"))
    assert tool_result["tool_call_id"] == "alias-call"
    assert Jason.decode!(tool_result["content"]) == %{"ok" => true, "result" => %{"value" => 8}}
    assert names(default) == ["scope_echo"]
    assert_script_done(mock)
  end

  test "single module and module list overrides share the same catalog path", %{jido: jido} do
    {mock, context} = mock([%{reply: {:text, "Single"}}, %{reply: {:text, "List"}}])
    server = start_agent(jido, Agent.new!())
    assert {:ok, "Single"} = Agent.ask_sync(server, "One", context: context, tools: Open)
    assert {:ok, "List"} = Agent.ask_sync(server, "Two", context: context, tools: [Open])
    [single, list] = MockLLM.report(mock).requests
    assert single.body["tools"] == list.body["tools"]
    assert names(single) == ["scope_open"]

    assert hd(single.body["tools"])["function"]["parameters"]["properties"]["params"][
             "additionalProperties"
           ] == true

    assert_script_done(mock)
  end

  test "an open request tool keeps dynamic fields through real execution", %{jido: jido} do
    {mock, context} =
      mock([
        %{
          reply:
            {:tools,
             [%{id: "open", name: "scope_open", arguments: %{params: %{dynamic_field: 42}}}]}
        },
        %{reply: {:text, "Dynamic field retained"}}
      ])

    server = start_agent(jido, Agent.new!())

    assert {:ok, "Dynamic field retained"} =
             Agent.ask_sync(server, "Open", context: context, tools: Open, max_iterations: 2)

    [_, result] = MockLLM.report(mock).requests
    tool = Enum.find(result.body["messages"], &(&1["role"] == "tool"))

    assert Jason.decode!(tool["content"]) == %{
             "ok" => true,
             "result" => %{"params" => %{"dynamic_field" => 42}}
           }

    assert_script_done(mock)
  end

  test "invalid selections and schemas fail before a request record or provider call", %{
    jido: jido
  } do
    {mock, context} = mock([])
    server = start_agent(jido, Agent.new!())
    before = Server.agent(server)

    for opts <- [
          [allowed_tools: ["absent"]],
          [tools: [String]],
          [output: [schema: Zoi.string()]],
          [tools: 42]
        ] do
      assert {:error, _} = Agent.ask(server, "Invalid", [context: context] ++ opts)
      assert Server.agent(server) == before
    end

    assert_script_done(mock)
  end

  @tag history_case: "HIST-08/request-limits"
  test "a positive iteration override permits another round and a later request retains its limit",
       %{jido: jido} do
    call = %{reply: {:tools, [%{id: "echo", name: "scope_echo", arguments: %{value: 1}}]}}
    {mock, context} = mock([call, %{reply: {:text, "Second round"}}, call])
    server = start_agent(jido, Agent.new!())

    assert {:ok, "Second round"} =
             Agent.ask_sync(server, "Two", context: context, max_iterations: 2)

    assert {:ok, request} = Agent.ask(server, "Default", context: context)
    assert {:ok, "Maximum iterations reached without a final answer."} = Agent.await(request)
    record = Server.agent(server).state.requests[request.id]
    assert record.meta.termination_reason == :max_iterations
    assert record.meta.model_calls == 1
    assert record.meta.tool_calls == 1
    assert length(MockLLM.report(mock).requests) == 3
    assert_script_done(mock)
  end

  @tag history_case: "HIST-08/request-limits"
  test "a smaller request limit does not reduce the next request limit", %{jido: jido} do
    alias JidoAI.Examples.RequestScope.TwoTurns
    call = %{reply: {:tools, [%{id: "echo", name: "scope_echo", arguments: %{value: 1}}]}}
    {mock, context} = mock([call, call, %{reply: {:text, "Two turns"}}])
    server = start_agent(jido, TwoTurns.new!())

    assert {:ok, "Maximum iterations reached without a final answer."} =
             TwoTurns.ask_sync(server, "One", context: context, max_iterations: 1)

    assert {:ok, "Two turns"} = TwoTurns.ask_sync(server, "Default", context: context)
    assert length(MockLLM.report(mock).requests) == 3
    assert_script_done(mock)
  end

  @tag history_case: "HIST-08/request-limits"
  test "invalid iteration values keep the configured limit", %{jido: jido} do
    script =
      for _ <- 1..3,
          do: %{reply: {:tools, [%{id: "echo", name: "scope_echo", arguments: %{value: 1}}]}}

    {mock, context} = mock(script)
    server = start_agent(jido, Agent.new!())

    for value <- [0, -1, "3"] do
      assert {:ok, "Maximum iterations reached without a final answer."} =
               Agent.ask_sync(server, "Limit", context: context, max_iterations: value)
    end

    assert length(MockLLM.report(mock).requests) == 3
    assert_script_done(mock)
  end

  @tag history_case: "HIST-11/finalization"
  test "an iteration limit still validates and repairs a typed result", %{jido: jido} do
    {mock, context} =
      mock([
        %{reply: {:tools, [%{id: "echo", name: "scope_echo", arguments: %{value: 1}}]}},
        %{reply: {:object, %{answer: "Repaired limit"}}}
      ])

    server = start_agent(jido, Agent.new!())

    assert {:ok, request} =
             Agent.ask(server, "Typed limit",
               context: context,
               output: [schema: Zoi.object(%{answer: Zoi.string()}), retries: 1]
             )

    assert {:ok, %{answer: "Repaired limit"}} = Agent.await(request)
    [_, repair] = MockLLM.report(mock).requests
    refute repair.body["tools"]
    assert repair.body["response_format"]["type"] == "json_schema"

    assert Server.agent(server).state.requests[request.id].meta.termination_reason ==
             :max_iterations

    assert_script_done(mock)
  end

  defp names(request), do: Enum.map(request.body["tools"], & &1["function"]["name"])
end
