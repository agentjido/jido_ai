defmodule JidoAI.Examples.ChatTest do
  use JidoAI.Examples.Case
  alias JidoAI.Examples.Chat, as: Example
  alias Jido.AI.Actions.LLM.{Chat, Complete, Embed, GenerateObject}
  alias Jido.AI.Actions.ToolCalling.{CallWithTools, ExecuteTool, ListTools}

  for {route, action} <- [{"simple", Chat}, {"complete", Complete}] do
    test "#{route} returns text and usage through direct Exec and capability calls", %{jido: jido} do
      {mock, context} = mock(List.duplicate(%{reply: {:text, "Ready"}}, 3))
      action = unquote(action)
      params = %{prompt: "Prepare the case"}
      assert {:ok, direct} = action.run(params, context)

      assert %{text: "Ready", usage: %{input_tokens: 10, output_tokens: 5, total_tokens: 15}} =
               direct

      assert {:ok, ^direct} = Jido.Exec.run(action, params, context)
      assert {:ok, definition} = Example.definition()
      server = start_agent(jido, definition)

      assert {:ok, agent} =
               Server.call(server, Example.signal(unquote(route), params), context: context)

      assert agent.state.result == direct and agent.state.case_id == "case-17"
      assert_script_done(mock)
    end
  end

  test "object generation uses the supplied schema through the provider", %{jido: jido} do
    {mock, context} = mock(List.duplicate(%{reply: {:object, %{label: "ready"}}}, 3))
    params = %{prompt: "Give the label", object_schema: Zoi.object(%{label: Zoi.string()})}
    assert {:ok, direct} = GenerateObject.run(params, context)
    assert direct.object == %{"label" => "ready"}
    assert {:ok, ^direct} = Jido.Exec.run(GenerateObject, params, context)
    assert {:ok, definition} = Example.definition()
    server = start_agent(jido, definition)

    assert {:ok, agent} =
             Server.call(server, Example.signal("generate_object", params), context: context)

    assert agent.state.result == direct
    assert_script_done(mock)
  end

  test "embeddings keep all vectors and the dimensions through direct Exec and capability calls",
       %{jido: jido} do
    {mock, context} = mock(List.duplicate(%{reply: {:embeddings, [[0.1, 0.2], [0.3, 0.4]]}}, 3))

    context = %{
      context
      | model: "openai:text-embedding-3-small",
        model_options: MockLLM.options(mock, :embedding)
    }

    params = %{texts_list: ["first", "second"], dimensions: 2}
    assert {:ok, direct} = Embed.run(params, context)

    assert direct.embeddings == [[0.1, 0.2], [0.3, 0.4]] and direct.dimensions == 2 and
             direct.count == 2

    assert {:ok, ^direct} = Jido.Exec.run(Embed, params, context)
    assert {:ok, definition} = Example.definition()
    server = start_agent(jido, definition)
    assert {:ok, agent} = Server.call(server, Example.signal("embed", params), context: context)
    assert agent.state.result == direct

    assert Enum.all?(
             MockLLM.report(mock).requests,
             &(&1.path == "/v1/embeddings" and &1.body["input"] == ["first", "second"])
           )

    assert_script_done(mock)
  end

  test "tool discovery and execution retain aliases through all three entry points", %{jido: jido} do
    {mock, context} = mock([])
    context = Map.put(context, :tools, %{"label" => Example.Echo, "admin_label" => Example.Echo})

    assert {:ok, %{tools: [%{name: "label"}], count: 1, sensitive_excluded: true}} =
             ListTools.run(%{include_schema: false}, context)

    assert {:ok, %{count: 2}} = Jido.Exec.run(ListTools, %{include_sensitive: true}, context)
    params = %{tool_name: "label", params: %{"label" => "ready"}}
    assert {:ok, direct} = ExecuteTool.run(params, context)
    assert direct == %{tool_name: "label", status: :success, result: %{label: "ready", count: 1}}
    assert {:ok, ^direct} = Jido.Exec.run(ExecuteTool, params, context)
    assert {:ok, definition} = Example.definition()
    server = start_agent(jido, definition)

    assert {:ok, agent} =
             Server.call(server, Example.signal("execute_tool", params), context: context)

    assert agent.state.result == direct

    assert {:ok, agent} =
             Server.call(server, Example.signal("list_tools", %{include_schema: false}),
               context: context
             )

    assert agent.state.result.tools == [%{name: "label"}]
    assert_script_done(mock)
  end

  test "the Chat capability executes aliased tools and returns the model answer", %{jido: jido} do
    {mock, context} = mock([%{reply: {:tools, [Example.tool()]}}, %{reply: {:text, "Ready"}}])
    assert {:ok, definition} = Example.definition()
    server = start_agent(jido, definition)

    assert {:ok, agent} =
             Server.call(server, Example.signal("message", %{prompt: "Prepare the case"}),
               context: context
             )

    assert %{type: :final_answer, text: "Ready", turns: 1, usage: %{total_tokens: 30}} =
             agent.state.result

    assert_receive {:chat_echo, %{label: "ready", count: 1}}
    [first, second] = MockLLM.report(mock).requests
    assert [%{"function" => %{"name" => "label"}}] = first.body["tools"]
    assert Enum.map(second.body["messages"], & &1["role"]) == ["user", "assistant", "tool"]
    assert_script_done(mock)
  end

  test "direct tool calls return pending tools without executing by default" do
    {mock, context} = mock([%{reply: {:tools, [Example.tool()]}}])
    context = Map.put(context, :tools, %{"label" => Example.Echo})

    assert {:ok, %{type: :tool_calls, tool_calls: [%{name: "label"}]}} =
             Jido.Exec.run(CallWithTools, %{prompt: "Prepare the case"}, context)

    refute_receive {:chat_echo, _}, 20
    assert_script_done(mock)
  end

  test "two tool rounds preserve options usage and one assistant message per response" do
    {mock, context} =
      mock([
        %{reply: {:tools, [Example.tool("first", "one")]}},
        %{reply: {:tools, [Example.tool("second", "two")]}},
        %{reply: {:text, "Done"}}
      ])

    context = Map.put(context, :tools, %{"label" => Example.Echo})

    assert {:ok, result} =
             CallWithTools.run(
               %{prompt: "Label twice", auto_execute: true, max_tokens: 77, temperature: 0.2},
               context
             )

    assert result.type == :final_answer and result.turns == 2 and result.usage.total_tokens == 45

    assert Enum.map(result.messages, & &1.role) == [
             :user,
             :assistant,
             :tool,
             :assistant,
             :tool,
             :assistant
           ]

    assert_receive {:chat_echo, %{label: "one"}}
    assert_receive {:chat_echo, %{label: "two"}}
    [_, second, third] = requests = MockLLM.report(mock).requests
    assert Enum.map(second.body["messages"], & &1["role"]) == ["user", "assistant", "tool"]

    assert Enum.map(third.body["messages"], & &1["role"]) == [
             "user",
             "assistant",
             "tool",
             "assistant",
             "tool"
           ]

    assert Enum.all?(requests, &(&1.body["max_tokens"] == 77 and &1.body["temperature"] == 0.2))

    assert Enum.map(third.body["messages"], & &1["tool_call_id"]) |> Enum.reject(&is_nil/1) == [
             "first",
             "second"
           ]

    assert_script_done(mock)
  end

  for limit <- [0, 1] do
    test "max_turns #{limit} counts tool rounds and retains the pending terminal result" do
      limit = unquote(limit)
      {mock, context} = mock(List.duplicate(%{reply: {:tools, [Example.tool()]}}, limit + 1))
      context = Map.put(context, :tools, %{"label" => Example.Echo})

      assert {:ok, result} =
               CallWithTools.run(
                 %{prompt: "Repeat", auto_execute: true, max_turns: limit},
                 context
               )

      assert result.type == :tool_calls and result.reason == :max_turns_reached and
               result.turns == limit

      assert result.usage.total_tokens == (limit + 1) * 15
      refute Map.has_key?(result, :messages)
      if limit == 1, do: assert_receive({:chat_echo, _})
      refute_receive {:chat_echo, _}, 20
      assert_script_done(mock)
    end
  end

  test "an unknown or invalid tool becomes a tool result and the model can recover" do
    calls = [
      %{id: "unknown", name: "missing", arguments: %{}},
      %{id: "invalid", name: "label", arguments: %{}}
    ]

    {mock, context} = mock([%{reply: {:tools, calls}}, %{reply: {:text, "Supply a label"}}])
    context = Map.put(context, :tools, %{"label" => Example.Echo})

    assert {:ok, %{text: "Supply a label", turns: 1}} =
             CallWithTools.run(%{prompt: "Label", auto_execute: true}, context)

    [_, request] = MockLLM.report(mock).requests
    messages = Enum.filter(request.body["messages"], &(&1["role"] == "tool"))
    assert Enum.map(messages, & &1["tool_call_id"]) == ["unknown", "invalid"]
    assert Enum.all?(messages, &(Jason.decode!(&1["content"])["ok"] == false))
    refute_receive {:chat_echo, _}, 20
    assert_script_done(mock)
  end

  test "later provider failure is an error result with usage from completed requests" do
    {mock, context} =
      mock([%{reply: {:tools, [Example.tool()]}}, %{reply: {:error, 503, "unavailable"}}])

    context = Map.put(context, :tools, %{"label" => Example.Echo})

    assert {:ok, %{type: :error, turns: 1, reason: reason, usage: %{total_tokens: 15}}} =
             CallWithTools.run(%{prompt: "Label", auto_execute: true}, context)

    assert is_struct(reason)
    assert_receive {:chat_echo, _}
    assert_script_done(mock)
  end

  test "first provider failures preserve domain state and return sanitized LLM errors", %{
    jido: jido
  } do
    {mock, context} = mock(List.duplicate(%{reply: {:error, 503, "private provider data"}}, 3))
    assert {:error, "An error occurred"} = Chat.run(%{prompt: "Label"}, context)
    assert {:error, _} = CallWithTools.run(%{prompt: "Label"}, context)
    assert {:ok, definition} = Example.definition()
    server = start_agent(jido, definition)

    assert {:error, _} =
             Server.call(server, Example.signal("simple", %{prompt: "Label"}), context: context)

    assert Server.agent(server).state.result == nil
    assert_script_done(mock)
  end

  test "explicit schema defaults and false auto_execute override Chat configuration", %{
    jido: jido
  } do
    {mock, context} =
      mock([
        %{reply: {:text, "First"}},
        %{reply: {:text, "Second"}},
        %{reply: {:tools, [Example.tool()]}}
      ])

    assert {:ok, definition} =
             Example.definition(
               default_max_tokens: 333,
               default_temperature: 0.1,
               default_system_prompt: "Use the case label"
             )

    server = start_agent(jido, definition)

    assert {:ok, _} =
             Server.call(server, Example.signal("simple", %{prompt: "Label"}), context: context)

    assert {:ok, _} =
             Server.call(
               server,
               Example.signal("simple", %{
                 prompt: "Label",
                 max_tokens: 1024,
                 temperature: 0.7,
                 system_prompt: "Explicit instruction"
               }),
               context: context
             )

    assert {:ok, agent} =
             Server.call(
               server,
               Example.signal("message", %{prompt: "Label", auto_execute: false}),
               context: context
             )

    assert agent.state.result.type == :tool_calls
    [omitted, explicit, _] = MockLLM.report(mock).requests
    assert omitted.body["max_tokens"] == 333 and omitted.body["temperature"] == 0.1
    assert hd(omitted.body["messages"])["content"] == "Use the case label"
    assert explicit.body["max_tokens"] == 1024 and explicit.body["temperature"] == 0.7
    assert hd(explicit.body["messages"])["content"] == "Explicit instruction"
    refute_receive {:chat_echo, _}, 20
    assert_script_done(mock)
  end

  test "complete excludes system prompts and current Agent structs provide direct Action defaults" do
    {mock, context} = mock(List.duplicate(%{reply: {:text, "Ready"}}, 2))

    assert {:ok, agent} =
             Example.definition(
               default_max_tokens: 212,
               default_system_prompt: "Plugin instruction"
             )

    context = Map.put(context, :agent, Jido.Agent.instantiate!(agent))

    assert {:ok, _} =
             Jido.Exec.run(
               Chat,
               %{"prompt" => "Label", "max_tokens" => 1024, "__jido_ai_action_provided__" => []},
               context
             )

    assert {:ok, _} =
             Complete.run(%{prompt: "Label", system_prompt: "Ignore for completion"}, context)

    [chat, complete] = MockLLM.report(mock).requests
    assert chat.body["max_tokens"] == 1024
    assert complete.body["max_tokens"] == 212
    assert Enum.map(chat.body["messages"], & &1["role"]) == ["system", "user"]
    assert Enum.map(complete.body["messages"], & &1["role"]) == ["user"]
    assert_script_done(mock)
  end

  test "invalid model options prompts schemas and embedding inputs fail before HTTP" do
    {mock, context} = mock([])

    for params <- [
          %{},
          %{prompt: 42},
          %{prompt: ""},
          %{prompt: "bad" <> <<0>>},
          %{prompt: "Label", model: :missing_chat_alias},
          %{prompt: "Label", system_prompt: 17}
        ] do
      assert {:error, _} = Chat.run(params, context)
    end

    assert {:error, _} = GenerateObject.run(%{prompt: "Label", object_schema: nil}, context)
    assert {:error, _} = Chat.run(%{prompt: "Label"}, Map.put(context, :model_options, %{}))

    for params <- [
          %{},
          %{texts_list: []},
          %{texts: "one", texts_list: ["two"]},
          %{texts_list: [""]},
          %{texts: "bad" <> <<0>>}
        ] do
      assert {:error, _} = Embed.run(params, context)
    end

    assert {:error, _} = CallWithTools.run(%{prompt: "Label", max_turns: -1}, context)
    assert MockLLM.report(mock).requests == []
    assert_script_done(mock)
  end

  test "tool filters restrict both advertised and executable tools and list schemas keep defaults" do
    {mock, context} =
      mock([%{reply: {:tools, [Example.tool()]}}, %{reply: {:text, "No such tool"}}])

    context = Map.put(context, :tools, %{"label" => Example.Echo, "other" => Example.Echo})

    assert {:ok, %{text: "No such tool"}} =
             CallWithTools.run(%{prompt: "Label", tools: ["other"], auto_execute: true}, context)

    [first, second] = MockLLM.report(mock).requests
    assert [%{"function" => %{"name" => "other"}}] = first.body["tools"]

    assert List.last(second.body["messages"])["content"] |> Jason.decode!() |> Map.fetch!("ok") ==
             false

    assert {:ok, %{tools: [%{name: "label", schema: schema}]}} =
             ListTools.run(%{allowed_tools: ["label"], filter: "lab"}, context)

    assert Enum.find(schema, &(&1.name == :count)).default == 1
    assert Enum.find(schema, &(&1.name == :label)).required == true
    refute_receive {:chat_echo, _}, 20
    assert_script_done(mock)
  end

  test "Exec cancellation stops a provider request inside the tool Flow" do
    {mock, context} =
      mock([
        %{reply: {:tools, [Example.tool()]}},
        %{reply: {:wait, :tool_followup, {:text, "late"}}}
      ])

    context = Map.put(context, :tools, %{"label" => Example.Echo})
    handle = Jido.Exec.run_async(CallWithTools, %{prompt: "Label", auto_execute: true}, context)
    assert_receive {:mock_llm_waiting, ^mock, :tool_followup, worker}, 3_000
    monitor = Process.monitor(worker)
    assert :ok = Jido.Exec.cancel(handle)
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 3_000
    assert_script_done(mock)
  end

  test "Action timeout stops the provider before the outer Exec timeout" do
    {mock, context} = mock([%{reply: {:wait, :slow_chat, {:text, "late"}}}])

    options =
      Keyword.update!(
        context.model_options,
        :req_http_options,
        &Keyword.delete(&1, :receive_timeout)
      )

    context = %{context | model_options: options}
    handle = Jido.Exec.run_async(Chat, %{prompt: "Label", timeout: 50}, context, timeout: 3_000)
    assert_receive {:mock_llm_waiting, ^mock, :slow_chat, worker}, 3_000
    monitor = Process.monitor(worker)
    assert {:error, _} = Jido.Exec.await(handle, 2_000)
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 3_000
    assert_script_done(mock)
  end

  test "capability binding ignores forged action and result targets", %{jido: jido} do
    {mock, context} = mock([%{reply: {:text, "Ready"}}])
    assert {:ok, definition} = Example.definition()
    server = start_agent(jido, definition)

    context =
      Map.put(context, :jido_ai_chat_capability, %{
        action: ExecuteTool,
        into: :case_id,
        key: :chat,
        defaults: %{}
      })

    assert {:ok, agent} =
             Server.call(
               server,
               Example.signal("simple", %{prompt: "Label", into: :case_id, action: ExecuteTool}),
               context: context
             )

    assert agent.state.result.text == "Ready" and agent.state.case_id == "case-17"
    assert {:ok, bad} = Example.definition(into: :missing)
    bad_server = start_agent(jido, bad)

    assert {:error, _} =
             Server.call(bad_server, Example.signal("simple", %{prompt: "Label"}),
               context: context
             )

    assert_script_done(mock)
  end

  test "default callback execution needs no global supervisor and keeps arbitrary return values" do
    alias Jido.AI.Validation

    for result <- [:ok, {:error, :domain_error}, {:ok, %{label: "ready"}}, "text", nil] do
      assert {:ok, callback} = Validation.validate_and_wrap_callback(fn _ -> result end)
      assert callback.(:input) == result
    end

    parent = self()

    assert {:ok, callback} =
             Validation.validate_and_wrap_callback(
               fn _ ->
                 send(parent, {:callback_worker, self()})

                 receive do
                   :never -> :never
                 end
               end,
               timeout: 30
             )

    assert {:error, :callback_timeout} = callback.(:input)
    assert_receive {:callback_worker, worker}
    refute Process.alive?(worker)
    assert {:ok, callback} = Validation.validate_and_wrap_callback(fn _ -> raise "failure" end)
    assert {:error, :callback_execution_failed} = callback.(:input)
  end

  test "the agent DSL combines all Chat routes with ordinary domain work", %{jido: jido} do
    {mock, context} = mock([%{reply: {:text, "Ready"}}])
    server = start_agent(jido, Example.Agent.new!())
    signal = Jido.Signal.new!("case.set", %{case_id: "case-42"}, source: "/examples/chat")
    assert {:ok, _} = Server.call(server, signal)

    assert {:ok, agent} =
             Server.call(server, Example.signal("simple", %{prompt: "Label"}), context: context)

    assert agent.state.case_id == "case-42" and agent.state.result.text == "Ready"

    assert {:ok,
            %{available_tools: ["label"], tools: %{"label" => Example.Echo}, auto_execute: true}} =
             Server.plugin_state(server, Jido.AI.Plugins.Chat)

    assert_script_done(mock)
  end

  test "all LLM Actions emit canonical telemetry with real decoded token counts" do
    script = [
      %{reply: {:text, "Ready"}},
      %{reply: {:text, "Ready"}},
      %{reply: {:object, %{label: "ready"}}},
      %{reply: {:embeddings, [[0.1]]}}
    ]

    {mock, context} = mock(script)
    id = "chat-observation-#{System.unique_integer([:positive])}"
    events = Enum.map([:start, :complete, :error], &Jido.AI.Observe.llm/1)

    :ok =
      :telemetry.attach_many(id, events, &Example.Telemetry.handle/4, %{observer: self(), id: id})

    on_exit(fn -> :telemetry.detach(id) end)
    context = Map.merge(context, %{request_id: id, run_id: id, observability: %{enabled: true}})

    for {kind, action, params, expected} <- [
          {:chat, Chat, %{prompt: "Label"}, 15},
          {:complete, Complete, %{prompt: "Label"}, 15},
          {:generate_object, GenerateObject,
           %{prompt: "Label", object_schema: Zoi.object(%{label: Zoi.string()})}, 15},
          {:embed, Embed, %{texts: "Label"}, 5}
        ] do
      scoped =
        if kind == :embed,
          do: %{
            context
            | model: "openai:text-embedding-3-small",
              model_options: MockLLM.options(mock, :embedding)
          },
          else: context

      assert {:ok, _} = action.run(params, scoped)

      assert_receive {:chat_telemetry, [:jido, :ai, :llm, :start], _,
                      %{operation: ^kind, origin: :action, request_id: ^id}}

      assert_receive {:chat_telemetry, [:jido, :ai, :llm, :complete], measurements, metadata}
      assert metadata.usage.total_tokens == expected
      assert measurements.total_tokens == expected and is_integer(measurements.duration)
      assert metadata.operation == kind and metadata.run_id == id and metadata.llm_call_id == nil
      if kind == :embed, do: assert(metadata.dimensions == 1)
    end

    assert {:error, "An error occurred"} = Chat.run(%{prompt: ""}, context)
    assert_receive {:chat_telemetry, [:jido, :ai, :llm, :start], _, _}
    assert_receive {:chat_telemetry, [:jido, :ai, :llm, :error], _, %{termination_reason: :error}}
    assert length(MockLLM.report(mock).requests) == 4
    assert_script_done(mock)
  end

  test "empty embedding responses retain an empty vector result and zero dimensions" do
    {mock, context} = mock([%{reply: {:embeddings, []}}])

    context = %{
      context
      | model: "openai:text-embedding-3-small",
        model_options: MockLLM.options(mock, :embedding)
    }

    assert {:ok, %{embeddings: [], count: 0, dimensions: 0}} =
             Embed.run(%{texts: "Label"}, context)

    assert_script_done(mock)
  end

  test "keyword object schemas retain provider validation and invalid output does not trigger hidden repair" do
    {mock, context} =
      mock([%{reply: {:object, %{label: "ready"}}}, %{reply: {:object, %{label: 17}}}])

    params = %{prompt: "Label", object_schema: [label: [type: :string, required: true]]}
    assert {:ok, %{object: %{"label" => "ready"}}} = GenerateObject.run(params, context)
    assert {:error, _} = GenerateObject.run(params, context)
    assert length(MockLLM.report(mock).requests) == 2
    assert_script_done(mock)
  end

  test "tool rounds retain decoded reasoning details and accumulate nested provider usage" do
    details = [%{signature: "synthetic", format: "openai", index: 0}]

    tool_message = %{
      role: "assistant",
      content: nil,
      reasoning_details: details,
      tool_calls: [
        %{
          id: "call_label",
          type: "function",
          function: %{name: "label", arguments: ~s({"label":"ready"})}
        }
      ]
    }

    raw = fn message, finish ->
      {:raw,
       %{
         id: "chat-response",
         object: "chat.completion",
         model: "gpt-4o-mini",
         choices: [%{index: 0, message: message, finish_reason: finish}],
         usage: %{
           prompt_tokens: 10,
           completion_tokens: 5,
           total_tokens: 15,
           completion_tokens_details: %{reasoning_tokens: 3}
         }
       }}
    end

    {mock, context} =
      mock([
        %{reply: raw.(tool_message, "tool_calls")},
        %{reply: raw.(%{role: "assistant", content: "Ready"}, "stop")}
      ])

    context = Map.put(context, :tools, %{"label" => Example.Echo})
    assert {:ok, result} = CallWithTools.run(%{prompt: "Label", auto_execute: true}, context)
    assert result.usage.total_tokens == 30 and result.usage.reasoning_tokens == 6
    [_, request] = MockLLM.report(mock).requests
    assistant = Enum.find(request.body["messages"], &(&1["role"] == "assistant"))
    assert [%{"signature" => "synthetic"}] = assistant["reasoning_details"]
    assert_script_done(mock)
  end

  test "Responses tool continuation retains the response identity in the actual next HTTP request" do
    raw = fn id, output ->
      {:raw,
       %{
         id: id,
         object: "response",
         model: "gpt-4o-mini",
         status: "completed",
         output: output,
         usage: %{input_tokens: 10, output_tokens: 5, total_tokens: 15}
       }}
    end

    first =
      raw.("resp_first", [
        %{
          type: "function_call",
          id: "item_first",
          call_id: "call_label",
          name: "label",
          arguments: ~s({"label":"ready"}),
          status: "completed"
        }
      ])

    final =
      raw.("resp_final", [
        %{
          type: "message",
          id: "message_final",
          role: "assistant",
          status: "completed",
          content: [%{type: "output_text", text: "Ready", annotations: []}]
        }
      ])

    {mock, context} = mock([%{reply: first}, %{reply: final}])

    model = %{
      context.model
      | extra: Map.put(context.model.extra, :wire, %{protocol: "openai_responses"})
    }

    context = context |> Map.put(:model, model) |> Map.put(:tools, %{"label" => Example.Echo})

    assert {:ok, %{text: "Ready", turns: 1, usage: %{total_tokens: 30}}} =
             CallWithTools.run(%{prompt: "Label", auto_execute: true}, context)

    [_, request] = MockLLM.report(mock).requests
    assert request.path == "/v1/responses"
    assert request.body["previous_response_id"] == "resp_first"

    assert Enum.any?(
             request.body["input"],
             &(&1["type"] == "function_call_output" and &1["call_id"] == "call_label")
           )

    assert_script_done(mock)
  end

  test "a registered core Flow can supply a tool result through the Chat capability", %{
    jido: jido
  } do
    {mock, context} = mock([%{reply: {:tools, [Example.tool()]}}, %{reply: {:text, "Ready"}}])
    assert {:ok, definition} = Example.definition(tools: %{"label" => Example.EchoFlow})
    server = start_agent(jido, definition)

    assert {:ok, agent} =
             Server.call(server, Example.signal("message", %{prompt: "Label"}), context: context)

    assert agent.state.result.text == "Ready"
    assert_receive {:chat_echo, %{label: "ready", count: 1}}
    assert_script_done(mock)
  end

  test "prompt validation accepts multiline code and JSON and retains single line detection" do
    code = "with attrs <- input do\n  system_group(attrs)\n  |> finish()\nend"
    json = "{\n  \"role\": \"system\",\n  \"name\": \"case\"\n}"
    {mock, context} = mock(List.duplicate(%{reply: {:text, "Reviewed"}}, 2))

    for prompt <- [code, json] do
      assert :ok = Jido.AI.Validation.validate_prompt(prompt)
      assert {:ok, %{text: "Reviewed"}} = Chat.run(%{prompt: prompt}, context)
    end

    for prompt <- [~s(<inject role="system">), ~s({"role":"system"})] do
      assert {:error, :prompt_injection_detected} = Jido.AI.Validation.validate_prompt(prompt)
    end

    assert Enum.map(MockLLM.report(mock).requests, &hd(&1.body["messages"])["content"]) == [
             code,
             json
           ]

    assert_script_done(mock)
  end

  test "object validation uses known nested schema keys and enum labels without changing the decoded result" do
    object = %{"items" => [%{"label" => "ready", "priority" => "high"}]}

    {mock, context} =
      mock([
        %{reply: {:object, object}},
        %{reply: {:object, %{"items" => [%{"label" => "ready", "priority" => "invalid"}]}}}
      ])

    schema =
      Zoi.object(%{
        items: Zoi.list(Zoi.object(%{label: Zoi.string(), priority: Zoi.enum([:low, :high])}))
      })

    params = %{prompt: "Prioritize labels", object_schema: schema}
    assert {:ok, %{object: ^object}} = GenerateObject.run(params, context)
    assert {:error, _} = GenerateObject.run(params, context)
    assert_script_done(mock)
  end

  test "a later model failure retains the callable error result through the live capability", %{
    jido: jido
  } do
    {mock, context} =
      mock([%{reply: {:tools, [Example.tool()]}}, %{reply: {:error, 503, "Unavailable"}}])

    assert {:ok, definition} = Example.definition()
    server = start_agent(jido, definition)

    assert {:ok, agent} =
             Server.call(server, Example.signal("message", %{prompt: "Label"}), context: context)

    assert %{type: :error, turns: 1, usage: %{total_tokens: 15}} = agent.state.result
    assert agent.state.case_id == "case-17"
    assert_script_done(mock)
  end

  test "invalid structured output retains completed provider usage in error telemetry", %{
    jido: jido
  } do
    {mock, context} = mock([%{reply: {:object, %{label: 17}}}])
    id = "chat-invalid-output-#{System.unique_integer([:positive])}"
    events = Enum.map([:start, :complete, :error], &Jido.AI.Observe.llm/1)

    :ok =
      :telemetry.attach_many(id, events, &Example.Telemetry.handle/4, %{observer: self(), id: id})

    on_exit(fn -> :telemetry.detach(id) end)
    context = Map.put(context, :request_id, id)
    assert {:ok, definition} = Example.definition()
    server = start_agent(jido, definition)
    params = %{prompt: "Label", object_schema: Zoi.object(%{label: Zoi.string()})}

    assert {:error, _} =
             Server.call(server, Example.signal("generate_object", params), context: context)

    assert_receive {:chat_telemetry, [:jido, :ai, :llm, :error], %{total_tokens: 15},
                    %{usage: %{total_tokens: 15}, termination_reason: :error}}

    refute_receive {:chat_telemetry, [:jido, :ai, :llm, :complete], _, _}, 20
    assert Server.agent(server).state.result == nil
    assert_script_done(mock)
  end
end
