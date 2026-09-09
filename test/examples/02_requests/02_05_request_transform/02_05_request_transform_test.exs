defmodule JidoAI.Examples.RequestTransformTest do
  use JidoAI.Examples.Case
  alias JidoAI.Examples.RequestTransform.{Agent, CallbackAgent, Transform, Repair}
  alias JidoAI.Examples.RequestTransform.{NativeAgent, ModelControl}

  setup do
    old = Application.fetch_env(:jido_ai, :model_aliases)
    Application.put_env(:jido_ai, :model_aliases, %{example: MockLLM.model()})

    on_exit(fn ->
      case old do
        {:ok, value} -> Application.put_env(:jido_ai, :model_aliases, value)
        :error -> Application.delete_env(:jido_ai, :model_aliases)
      end
    end)

    calls = start_supervised!({Elixir.Agent, fn -> 0 end})
    {:ok, calls: calls}
  end

  defp context(context, calls, mode \\ :refresh),
    do: Map.merge(context, %{calls: calls, transform_mode: mode})

  @tag history_case: "HIST-10/per-attempt-refresh"
  test "each repair receives fresh credentials and its exact model request", %{
    jido: jido,
    calls: calls
  } do
    {mock, ctx} =
      mock([
        %{reply: {:text, ["Not", " JSON"]}},
        %{reply: {:object, %{answer: ""}}},
        %{reply: {:object, %{answer: "Repaired"}}}
      ])

    server = start_agent(jido, Agent.new!())

    assert {:ok, request} =
             Agent.ask(server, "Ticket 42", context: context(ctx, calls), stream_to: self())

    assert {:ok, %{answer: "Repaired"}} = Agent.await(request)
    id = request.id
    assert_receive {:transformed, 1, normal, ^id, run_id, "Ticket 42"}
    assert normal.tools != %{}
    assert_receive {:transformed, 2, repair, ^id, ^run_id, _}
    assert repair.tools == %{}
    assert List.last(repair.messages).content =~ "Ticket 42"
    assert List.last(repair.messages).content =~ "Not JSON"
    assert_receive {:transformed, 3, again, ^id, ^run_id, _}
    assert again.tools == %{}
    assert_receive {:transform_state, 1, initial}
    assert_receive {:transform_state, 2, first_repair}
    assert_receive {:transform_state, 3, next_repair}
    assert initial.iteration == 1
    assert initial.seq == 1
    assert is_binary(initial.llm_call_id)
    assert initial.llm_response_id == nil
    assert initial.active_tools == %{}
    assert_receive {:jido_ai_request_event, %{kind: :llm_started, llm_call_id: call_id}}
    assert initial.llm_call_id == call_id
    assert first_repair.status == :completed
    assert first_repair.iteration == 1
    assert first_repair.llm_call_id == call_id
    assert is_binary(first_repair.llm_response_id)
    assert first_repair.context.id == next_repair.context.id

    assert Jido.AI.Context.to_messages(first_repair.context) ==
             Jido.AI.Context.to_messages(next_repair.context)

    assert first_repair.result == next_repair.result
    assert first_repair.streaming_text == "Not JSON"
    assert next_repair.active_tools == first_repair.active_tools
    assert next_repair.seq > first_repair.seq
    [first, second, third] = MockLLM.report(mock).requests
    assert first.body["stream"] == true

    for {req, version} <- Enum.zip([first, second, third], ["1", "2", "3"]) do
      assert req.headers["x-credential-version"] == version
    end

    for {req, n} <- [{second, 2}, {third, 3}] do
      refute req.body["stream"] == true
      refute Enum.any?(req.body["tools"] || [], &(&1["function"]["name"] == "scope_echo"))
      assert req.body["model"] == "gpt-4.1-mini"
      assert List.last(req.body["messages"])["content"] == "Normalize ticket #{n}."
    end

    assert Server.agent(server).state.requests[id].meta.model_calls == 3
    assert Server.agent(server).state.requests[id].meta.usage.total_tokens > 15
    assert_script_done(mock)
  end

  @tag history_case: "HIST-10/transform-failure"
  test "repair transformer failure prevents another provider call", %{jido: jido, calls: calls} do
    {mock, ctx} = mock([%{reply: {:text, "Invalid"}}])
    server = start_agent(jido, Agent.new!())
    assert {:ok, request} = Agent.ask(server, "Ticket", context: context(ctx, calls, :error))
    assert {:error, _} = Agent.await(request)
    assert Server.agent(server).state.last_result == nil
    assert Elixir.Agent.get(calls, & &1) == 2
    assert length(MockLLM.report(mock).requests) == 1
    assert_script_done(mock)
  end

  test "invalid transformed messages prevent provider work", %{jido: jido, calls: calls} do
    {mock, ctx} = mock([%{reply: {:text, "Invalid"}}])
    server = start_agent(jido, Agent.new!())
    assert {:error, _} = Agent.ask_sync(server, "Ticket", context: context(ctx, calls, :invalid))
    assert length(MockLLM.report(mock).requests) == 1
    assert_script_done(mock)
  end

  test "a valid initial answer has no repair transformation", %{jido: jido, calls: calls} do
    {mock, ctx} = mock([%{reply: {:text, ~s({"answer":"Valid"})}}])
    server = start_agent(jido, Agent.new!())

    assert {:ok, %{answer: "Valid"}} =
             Agent.ask_sync(server, "Ticket", context: context(ctx, calls))

    assert Elixir.Agent.get(calls, & &1) == 1
    assert_script_done(mock)
  end

  test "request tool transformation controls advertisement and the execution catalog", %{
    jido: jido,
    calls: calls
  } do
    alias JidoAI.Examples.RequestScope.Agent, as: ScopeAgent

    {mock, ctx} =
      mock([
        %{reply: {:tools, [%{id: "echo", name: "scope_echo", arguments: %{value: 9}}]}},
        %{reply: {:text, "Gated"}}
      ])

    server = start_agent(jido, ScopeAgent.new!())

    assert {:ok, "Gated"} =
             ScopeAgent.ask_sync(server, "Gate",
               context: context(ctx, calls, :gate),
               request_transformer: Transform,
               max_iterations: 2
             )

    [first, second] = MockLLM.report(mock).requests
    assert length(first.body["tools"]) == 1
    refute second.body["tools"]

    tool = Enum.find(second.body["messages"], &(&1["role"] == "tool"))
    assert Jason.decode!(tool["content"]) == %{"ok" => true, "result" => %{"value" => 9}}

    assert_script_done(mock)
  end

  @tag history_case: "HIST-11/configured-repair"
  test "a configured callback receives transformed bindings and its value is validated", %{
    jido: jido,
    calls: calls
  } do
    {mock, ctx} = mock([%{reply: {:text, "Invalid"}}])
    {:ok, repairs} = Elixir.Agent.start_link(fn -> 0 end)

    try do
      server = start_agent(jido, CallbackAgent.new!())
      ctx = context(ctx, calls) |> Map.put(:repairs, repairs)
      assert {:ok, request} = CallbackAgent.ask(server, "Ticket 73", context: ctx)
      assert {:ok, %{answer: "Callback result"}} = CallbackAgent.await(request)
      assert_receive {:repaired, 1, {Repair, :repair}, "Invalid", _, repair_context}
      assert repair_context.user_message == "Ticket 73"
      assert repair_context.request_id == request.id
      assert repair_context.model.id == "gpt-4.1-mini"

      assert repair_context.llm_opts[:req_http_options][:headers] == [
               {"x-credential-version", "2"}
             ]

      refute repair_context.llm_opts[:tools]
      refute repair_context.llm_opts[:tool_choice]
      assert repair_context.llm_opts[:stream] == false
      assert Server.agent(server).state.requests[request.id].meta.model_calls == 1
      assert Elixir.Agent.get(calls, & &1) == 2
      assert_script_done(mock)
    after
      Elixir.Agent.stop(repairs)
    end
  end

  test "invalid callback results retry within the output bound and then fail", %{
    jido: jido,
    calls: calls
  } do
    {mock, ctx} = mock([%{reply: {:text, "Invalid"}}])
    {:ok, repairs} = Elixir.Agent.start_link(fn -> 0 end)

    try do
      server = start_agent(jido, CallbackAgent.new!())
      ctx = context(ctx, calls) |> Map.merge(%{repairs: repairs, invalid_repair: true})
      assert {:error, _} = CallbackAgent.ask_sync(server, "Ticket", context: ctx)
      assert Elixir.Agent.get(repairs, & &1) == 2
      assert Elixir.Agent.get(calls, & &1) == 3
      assert Server.agent(server).state.last_result == nil
      assert_script_done(mock)
    after
      Elixir.Agent.stop(repairs)
    end
  end

  test "a missing transformer fails before admission", %{jido: jido, calls: calls} do
    {mock, ctx} = mock([])
    server = start_agent(jido, Agent.new!())
    before = Server.agent(server)

    assert {:error, _} =
             Agent.ask(server, "Invalid",
               context: context(ctx, calls),
               request_transformer: String
             )

    assert Server.agent(server) == before
    assert_script_done(mock)
  end

  @tag history_case: "HIST-11/callback-identity"
  test "DSL, data, Builder and source JSON execute the same callback references", %{
    jido: jido,
    calls: calls
  } do
    profile = NativeAgent.source()
    assert {:ok, direct} = Jido.AI.Authoring.lower(NativeAgent.base(), [profile])
    dsl = NativeAgent.definition()
    assert direct == dsl
    attrs = direct |> Map.from_struct() |> Map.drop([:id, :state])
    built = Jido.Agent.Builder.new(attrs) |> Jido.Agent.Builder.build!()
    registry = source_registry(profile)
    assert {:ok, document} = Jido.AI.Authoring.Codec.encode([profile], registry)
    document = document |> Jason.encode!() |> Jason.decode!()
    assert {:ok, decoded} = Jido.AI.Authoring.Codec.decode(NativeAgent.base(), document, registry)
    assert decoded == direct
    assert {:error, _} = Jido.AI.Authoring.Codec.decode(NativeAgent.base(), document, %{})
    {mock, ctx} = mock(List.duplicate(%{reply: {:text, "Invalid"}}, 4))
    repairs = start_supervised!(Supervisor.child_spec({Elixir.Agent, fn -> 0 end}, id: :repairs))
    ctx = context(ctx, calls, :keep_model) |> Map.put(:repairs, repairs)

    for {definition, n} <- Enum.with_index([dsl, direct, built, decoded], 1) do
      server = start_agent(jido, Jido.Agent.instantiate!(definition))
      assert {:ok, %{state: %{reply: %{answer: "Callback result"}}}} = ask(server, ctx)
      assert_receive {:repaired, ^n, {Repair, :repair}, "Invalid", _, callback_context}
      assert callback_context.user_message == "Help with this case"
    end

    assert Elixir.Agent.get(calls, & &1) == 8
    assert_script_done(mock)
  end

  test "the model budget stops repair before another transformation or HTTP request", %{
    jido: jido,
    calls: calls
  } do
    profile = put_in(NativeAgent.source(), [:result, :repair_fun], nil)
    {mock, ctx} = mock([%{reply: {:text, "Invalid"}}, %{reply: {:object, %{answer: 42}}}])
    assert {:ok, definition} = Jido.AI.Authoring.lower(NativeAgent.base(), [profile])
    server = start_agent(jido, Jido.Agent.instantiate!(definition))
    before = Server.agent(server)
    assert {:error, _} = ask(server, context(ctx, calls))
    assert Server.agent(server) == before
    assert Elixir.Agent.get(calls, & &1) == 2
    assert_script_done(mock)
  end

  test "model controls see and can reject the transformed repair model", %{
    jido: jido,
    calls: calls
  } do
    profile = put_in(NativeAgent.source(), [:result, :repair_fun], nil)
    {mock, ctx} = mock([%{reply: {:text, "Invalid"}}])
    assert {:ok, definition} = Jido.AI.Authoring.lower(NativeAgent.base(), [profile])
    server = start_agent(jido, Jido.Agent.instantiate!(definition))
    ctx = context(ctx, calls) |> Map.put(:reject_alternate, true)
    assert {:error, _} = ask(server, ctx)
    assert_receive {:model_checked, "gpt-4o-mini"}
    assert_receive {:model_checked, "gpt-4.1-mini"}
    assert Server.agent(server).state.reply == %{}
    assert_script_done(mock)
  end

  @tag history_case: "HIST-11/direct-override"
  test "a direct repair override takes precedence and does not change the stored callback" do
    assert {:ok, output} =
             Jido.AI.Output.new(
               schema: Zoi.object(%{answer: Zoi.string()}),
               repair_fun: &Repair.repair/4
             )

    override = fn _, raw, reason ->
      assert raw == "Invalid"
      assert reason == :invalid
      {:ok, %{answer: "Direct override"}}
    end

    assert {:ok, %{answer: "Direct override"}} =
             Jido.AI.Output.repair(output, "Invalid", :invalid, %{}, repair_fun: override)

    assert output.repair_fun == {Repair, :repair}
    override4 = fn _, _, _, context -> {:ok, %{answer: context.answer}} end

    assert {:ok, %{answer: "Four arguments"}} =
             Jido.AI.Output.repair(output, "Invalid", :invalid, %{answer: "Four arguments"}, repair_fun: override4)

    assert :erlang.binary_to_term(:erlang.term_to_binary(output), [:safe]) == output
  end

  @tag history_case: "HIST-10/repair-context"
  test "repair uses the summary of the original content-part query", %{jido: jido, calls: calls} do
    alias ReqLLM.Message.ContentPart
    {mock, ctx} = mock([%{reply: {:text, "Invalid"}}])
    repairs = start_supervised!(Supervisor.child_spec({Elixir.Agent, fn -> 0 end}, id: :repairs))
    ctx = context(ctx, calls) |> Map.put(:repairs, repairs)
    server = start_agent(jido, CallbackAgent.new!())

    query = [
      ContentPart.text("Ticket image"),
      ContentPart.image_url("https://example.test/ticket.png")
    ]

    assert {:ok, %{answer: "Callback result"}} =
             CallbackAgent.ask_sync(server, query, context: ctx)

    assert_receive {:repaired, 1, _, _, _, repair_context}
    assert repair_context.user_message =~ "Ticket image"
    assert repair_context.user_message =~ "[Image]"
    assert [request] = MockLLM.report(mock).requests
    assert Enum.any?(List.last(request.body["messages"])["content"], &(&1["type"] == "image_url"))
    assert_script_done(mock)
  end

  test "stored callbacks reject closures and invalid arities before provider work" do
    {mock, _} = mock([])

    for callback <- [fn _, _, _ -> {:ok, %{}} end, {String, :trim}, &String.trim/1] do
      profile = put_in(NativeAgent.source(), [:result, :repair_fun], callback)
      assert {:error, _} = Jido.AI.Authoring.lower(NativeAgent.base(), [profile])
    end

    assert {:ok, with_callback} = Jido.AI.Profile.output_contract(NativeAgent.source().result)

    assert {:ok, without_callback} =
             Jido.AI.Profile.output_contract(%{NativeAgent.source().result | repair_fun: nil})

    refute Jido.AI.Output.fingerprint(with_callback) ==
             Jido.AI.Output.fingerprint(without_callback)

    assert_script_done(mock)
  end

  defp source_registry(profile) do
    atoms = [
      :id,
      :instructions,
      :models,
      :answer,
      :example,
      :model,
      :generation,
      :reasoning,
      :method,
      :react,
      :tool_concurrency,
      :request_transformer,
      Transform,
      :controls,
      :max_iterations,
      :max_model_calls,
      :max_tool_calls,
      :timeout,
      :input,
      :operation,
      :output,
      ModelControl,
      :tools,
      :name,
      :target,
      :description,
      :forward_context,
      JidoAI.Examples.RequestScope.Echo,
      :result,
      :schema,
      :into,
      :reply,
      :max_repairs,
      :repair_fun,
      :repair,
      Repair,
      :requests,
      :mode,
      :turn,
      :on_busy,
      :reject,
      :max_requests,
      :streaming,
      :steering,
      :memory,
      :observability,
      :effect_policy,
      :history,
      :routes,
      :assistant
    ]

    entries =
      atoms
      |> Kernel.++(profile_atoms(profile))
      |> Enum.uniq()
      |> Map.new(&{"atoms/#{&1}", {:atom, &1}})
      |> Map.put("schema/reply", {:value, profile.result.schema})

    Jido.Agent.Codec.Registry.new!(entries)
  end
end
