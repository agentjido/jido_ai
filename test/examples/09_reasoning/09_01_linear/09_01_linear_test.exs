defmodule JidoAI.Examples.LinearTest do
  use JidoAI.Examples.Case
  alias Jido.AI.{Authoring, Request, Session}
  alias Jido.AI.Reasoning.Linear
  alias JidoAI.Examples.Linear.{CoT, CoD, PublicCoT, PublicCoD}

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

  defp source(module) do
    {_, opts} = Enum.find(module.definition().plugins, &(elem(&1, 0) == Jido.AI.Runtime.Plugin))
    Map.from_struct(opts[:profiles].assistant)
  end

  defp base(module),
    do: %{
      name: module.definition().name,
      module: module,
      vsn: module.vsn(),
      schema: module.domain_schema(),
      routes: [{"ai.ask", Authoring.ai(:assistant)}]
    }

  defp definition(module, changes \\ %{}) do
    assert {:ok, definition} = Authoring.lower(base(module), [Map.merge(source(module), changes)])
    definition
  end

  defp start(jido, module, changes \\ %{}) do
    assert {:ok, server} =
             Jido.start_agent(jido, Jido.Agent.instantiate!(definition(module, changes)),
               default_dispatch: {:pid, target: self()}
             )

    server
  end

  defp request(server, context, query \\ "What is 2 + 2?") do
    Request.create_and_send(server, query,
      signal_type: "ai.ask",
      source: "/examples/linear",
      context: context,
      stream_to: self()
    )
  end

  defp events(request),
    do: request |> Request.Stream.events(stream_event_timeout_ms: 1_000) |> Enum.to_list()

  defp record(server, request), do: Server.agent(server).state.requests[request.id]

  defp delivered(server, request) do
    eventually(fn ->
      match?({:ok, %{status: :delivered}}, Session.delivery_status(server, request.id))
    end)

    signals()
  end

  defp signals(acc \\ []) do
    receive do
      {:signal, signal} -> signals([signal | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp response(message) do
    {:raw,
     %{
       id: "linear-response",
       object: "chat.completion",
       model: "gpt-4o-mini",
       choices: [
         %{index: 0, message: Map.put(message, :role, "assistant"), finish_reason: "stop"}
       ],
       usage: %{prompt_tokens: 10, completion_tokens: 5, total_tokens: 15}
     }}
  end

  for {module, method, text} <- [
        {CoT, :chain_of_thought, "Step 1: Add.\nConclusion: 4"},
        {CoD, :chain_of_draft, "1. Add two pairs.\n#### 4"}
      ] do
    test "#{method} uses its default prompt and one shared model call", %{jido: jido} do
      module = unquote(module)
      method = unquote(method)
      text = unquote(text)
      {mock, context} = mock([%{reply: {:text, [text]}}])
      server = start(jido, module)
      assert {:ok, request} = request(server, Map.put(context, :expected, "4"))
      assert {:ok, "4"} = Request.await(request)
      assert_receive {:answer_checked, "4"}
      received = events(request)
      assert Enum.count(received, &(&1.kind == :llm_started)) == 1
      assert Enum.count(received, &(&1.kind == :llm_completed)) == 1
      assert Enum.all?(received, &(&1.method == method))
      assert Enum.map(received, & &1.seq) == Enum.to_list(1..length(received))
      rec = record(server, request)
      assert rec.method == method and rec.meta.model_calls == 1 and rec.meta.tool_calls == 0
      assert rec.meta.usage.total_tokens == 15

      assert rec.meta.reasoning == %{
               method: method,
               raw_response: text,
               conclusion: "4",
               steps_count: 1,
               steps: [
                 %{
                   number: 1,
                   content: unquote(if method == :chain_of_thought, do: "Add.", else: "Add two pairs.")
                 }
               ]
             }

      assert Server.agent(server).state.reply == "4"
      typed = delivered(server, request)
      assert List.last(typed).data.result == "4"

      assert Enum.all?(
               for %{data: %{metadata: metadata}} <- typed,
                   do: metadata.strategy == Linear.label(method)
             )

      [wire] = MockLLM.report(mock).requests
      assert hd(wire.body["messages"])["content"] == Linear.default_prompt(method)
      refute Map.has_key?(wire.body, "tools")
      assert_script_done(mock)
    end
  end

  test "the parser retains supported numbered bullet and conclusion formats without adjacent markers" do
    for prefix <- ["Step 1:", "1.", "1)", "1:"] do
      text = prefix <> " café ✓\nStep 2: 東京\n  Conclusion: 4"

      assert {[%{number: 1, content: "café ✓"}, %{number: 2, content: "東京"}], "4"} =
               Linear.extract_steps_and_conclusion(text)
    end

    assert {[%{number: 1, content: "one"}, %{number: 2, content: "two"}], "done"} =
             Linear.extract_steps_and_conclusion("- one\n• two\n#### done")

    for marker <- ["Conclusion:", "Answer:", "Therefore:", "Final Answer:", "Thus:", "Hence:"] do
      assert {[], "4"} = Linear.extract_steps_and_conclusion("#{marker} 4")
    end

    for text <- ["Something useful", "Solar panels", "Answerable query", "plain text", ""] do
      assert {[], nil} = Linear.extract_steps_and_conclusion(text)
    end

    assert {[], nil} = Linear.extract_steps_and_conclusion(nil)

    assert {[], "first #### second"} =
             Linear.extract_steps_and_conclusion("draft #### first #### second")
  end

  test "explicit prompt and unmarked output remain exact through the real provider", %{jido: jido} do
    {mock, context} = mock([%{reply: {:text, "Something useful"}}])
    server = start(jido, CoT, %{instructions: "Use this exact prompt."})
    assert {:ok, request} = request(server, context)
    assert {:ok, "Something useful"} = Request.await(request)
    rec = record(server, request)
    assert rec.meta.reasoning.conclusion == nil and rec.meta.reasoning.steps == []
    [wire] = MockLLM.report(mock).requests
    assert hd(wire.body["messages"])["content"] == "Use this exact prompt."
    assert_script_done(mock)
  end

  for {module, method, helper} <- [
        {PublicCoT, :chain_of_thought, :think},
        {PublicCoD, :chain_of_draft, :draft}
      ] do
    test "#{helper} and its synchronous helper preserve request identity and reset usage", %{
      jido: jido
    } do
      module = unquote(module)
      helper = unquote(helper)

      {mock, context} =
        mock([%{reply: {:text, "Conclusion: first"}}, %{reply: {:text, "Conclusion: next"}}])

      assert {:ok, server} =
               Jido.start_agent(jido, module, default_dispatch: {:pid, target: self()})

      assert {:ok, request} =
               apply(module, helper, [server, "First", [context: context, stream_to: self()]])

      assert {:ok, "first"} = module.await(request)

      assert %{last_prompt: "First", last_result: "first", completed: true} =
               Server.agent(server).state

      assert record(server, request).meta.usage.total_tokens == 15

      [{_, config}] =
        Enum.filter(module.definition().plugins, &(elem(&1, 0) == Jido.AI.Runtime.Plugin))

      refute Keyword.has_key?(config[:profiles].assistant.models.answer.generation, :max_tokens)
      assert hd(MockLLM.report(mock).requests).body["max_tokens"] == MockLLM.model().limits.output
      first_run = record(server, request).run_id
      delivered(server, request)

      assert {:ok, "next"} =
               apply(module, String.to_existing_atom("#{helper}_sync"), [
                 server,
                 "Next",
                 [context: context]
               ])

      agent = Server.agent(server)
      next = agent.state.requests[agent.state.last_request_id]
      assert next.method == unquote(method) and next.run_id != first_run
      assert next.meta.usage.total_tokens == 15 and next.meta.model_calls == 1
      assert agent.state.last_prompt == "Next" and agent.state.last_result == "next"
      [_, second] = MockLLM.report(mock).requests
      assert Enum.map(second.body["messages"], & &1["role"]) == ["system", "user"]
      assert_script_done(mock)
    end
  end

  test "DSL data Builder source JSON and direct Flow share the same linear recipe", %{jido: jido} do
    {mock, context} = mock(List.duplicate(%{reply: {:text, "1. Add.\n#### 4"}}, 10))

    for module <- [CoT, CoD] do
      source = source(module)
      definition = definition(module)
      assert module.definition() == definition
      attrs = definition |> Map.from_struct() |> Map.drop([:id, :state])
      assert {:ok, built} = attrs |> Jido.Agent.Builder.new() |> Jido.Agent.Builder.build()

      registry =
        source
        |> Map.put(:routes, [])
        |> atoms()
        |> Kernel.++(profile_atoms(source))
        |> Enum.uniq()
        |> Map.new(&{"atoms/#{&1}", {:atom, &1}})
        |> Map.put("models/answer", {:value, source.models.answer.model})

      assert {:ok, document} = Authoring.Codec.encode([source], registry)

      assert {:ok, decoded} =
               Authoring.Codec.decode(
                 base(module),
                 Jason.decode!(Jason.encode!(document)),
                 registry
               )

      assert built == definition and decoded == definition

      for definition <- [module.definition(), definition, built, decoded] do
        server = start_agent(jido, Jido.Agent.instantiate!(definition))
        assert {:ok, request} = request(server, context)
        assert {:ok, "4"} = Request.await(request)
        assert record(server, request).meta.reasoning.method == source.reasoning.method
      end

      assert {:ok, profile} = Jido.AI.Profile.new(source)
      assert {:ok, flow} = Authoring.reasoning_flow(profile)

      context =
        Map.merge(context, %{agent_state: %{reply: nil}, jido_ai_profiles: %{assistant: profile}})

      assert {:ok, output} = Jido.Exec.run(flow, %{query: "What is 2 + 2?"}, context)
      assert output.result == "4" and output.meta.model_calls == 1
      assert output.meta.reasoning.method == source.reasoning.method
    end

    assert_script_done(mock)
  end

  test "structured object repair retains usage and common output validation", %{jido: jido} do
    {mock, context} =
      mock([%{reply: {:object, %{answer: "wrong"}}}, %{reply: {:object, %{answer: 4}}}])

    schema = Zoi.object(%{answer: Zoi.integer()})
    server = start(jido, CoD, %{result: %{schema: schema, into: :reply, max_repairs: 1}})
    assert {:ok, request} = request(server, context)
    assert {:ok, %{answer: 4}} = Request.await(request)
    received = events(request)
    assert Enum.count(received, &(&1.kind == :llm_completed)) == 2
    assert Enum.count(received, &(&1.kind == :output_repair)) == 1
    assert record(server, request).meta.usage.total_tokens == 30
    assert record(server, request).meta.model_calls == 2
    assert record(server, request).meta.reasoning.conclusion == nil
    assert_script_done(mock)
  end

  test "a structured string field keeps its validated value without conclusion projection", %{
    jido: jido
  } do
    {mock, context} = mock([%{reply: {:object, %{answer: "Conclusion: keep this"}}}])
    schema = Zoi.object(%{answer: Zoi.string() |> Zoi.regex(~r/^Conclusion:/)})
    server = start(jido, CoT, %{result: %{schema: schema, into: :reply, max_repairs: 0}})
    assert {:ok, request} = request(server, context)
    assert {:ok, %{answer: "Conclusion: keep this"}} = Request.await(request)
    assert Server.agent(server).state.reply == %{answer: "Conclusion: keep this"}
    assert_script_done(mock)
  end

  test "linear profiles reject tools and steering before any model request", %{jido: jido} do
    {mock, context} = mock([])

    for module <- [CoT, CoD] do
      src = source(module)

      assert {:error, %{field: "reasoning"}} =
               Authoring.lower(base(module), [
                 %{src | tools: [%{target: JidoAI.Examples.TypedSignals.Echo, name: "echo"}]}
               ])

      assert {:error, %{field: "reasoning"}} =
               Authoring.lower(base(module), [%{src | requests: %{src.requests | steering: true}}])

      server = start(jido, module)

      assert {:error, _} =
               Request.create_and_send(server, "No tools",
                 signal_type: "ai.ask",
                 source: "/linear",
                 context: context,
                 tools: [JidoAI.Examples.TypedSignals.Echo]
               )

      assert Server.agent(server).state.requests == %{}
    end

    assert_script_done(mock)
  end

  test "an unsolicited model tool call fails without running the tool or a second model call", %{
    jido: jido
  } do
    {mock, context} =
      mock([
        %{reply: {:tools, [%{id: "unexpected", name: "echo", arguments: %{value: "wrong"}}]}}
      ])

    server = start(jido, CoT)
    assert {:ok, request} = request(server, context)
    assert {:error, {:unexpected_tool_calls, :chain_of_thought}} = Request.await(request)
    refute_receive {:echo_executed, _}, 0
    assert record(server, request).meta.usage.total_tokens == 15
    assert List.last(events(request)).kind == :request_failed
    assert_script_done(mock)
  end

  test "a rejected output returns the control error and preserves domain state", %{jido: jido} do
    {mock, context} = mock([%{reply: {:text, "Conclusion: wrong"}}])
    server = start(jido, CoT)
    assert {:ok, request} = request(server, Map.put(context, :expected, "right"))
    assert {:error, :wrong_answer} = Request.await(request)
    assert_receive {:answer_checked, "wrong"}
    assert Server.agent(server).state.reply == nil
    assert_script_done(mock)
  end

  for module <- [CoT, CoD] do
    test "#{inspect(module)} preserves real provider failure and cancellation", %{jido: jido} do
      {mock, context} =
        mock([
          %{reply: {:error, 500, %{error: %{message: "refused"}}}},
          %{
            reply: {:stream, [%{content: "Step 1: held"}, {:wait, :held}, %{content: "Conclusion: late"}], "stop"}
          }
        ])

      server = start(jido, unquote(module))
      assert {:ok, failed} = request(server, context)
      assert {:error, reason} = Request.await(failed)
      failed_signals = delivered(server, failed)
      assert Enum.find(failed_signals, &(&1.type == "ai.request.failed")).data.error == reason
      assert {:ok, cancelled} = request(server, context)
      assert_receive {:mock_llm_waiting, ^mock, :held, provider}, 2_000
      monitor = Process.monitor(provider)
      assert :ok = Session.cancel(cancelled, reason: :user_cancelled)
      assert {:error, {:cancelled, :user_cancelled}} = Request.await(cancelled)
      assert_receive {:DOWN, ^monitor, :process, ^provider, _}, 2_000
      cancelled_signals = delivered(server, cancelled)
      assert Enum.count(cancelled_signals, &(&1.type == "ai.request.failed")) == 1
      refute Enum.any?(cancelled_signals, &(&1.type == "ai.request.completed"))
      eventually(fn -> MockLLM.report(mock).waiting == [] end)
      assert_script_done(mock)
    end
  end

  test "early linear deltas retain method identity before the answer is committed", %{jido: jido} do
    {mock, context} =
      mock([
        %{
          reply: {:stream, [%{content: "Step 1: Add."}, {:wait, :held}, %{content: "\nConclusion: 4"}], "stop"}
        }
      ])

    server = start(jido, CoT)
    assert {:ok, request} = request(server, Map.put(context, :method, :react))
    assert_receive {:mock_llm_waiting, ^mock, :held, _}, 2_000

    assert_receive {:jido_ai_request_event, %{kind: :llm_delta, method: :chain_of_thought} = delta},
                   1_000

    assert record(server, request).status == :pending and Server.agent(server).state.reply == nil
    assert_receive {:signal, %{type: "ai.llm.delta"} = typed}, 1_000
    assert typed.data.seq == delta.seq and typed.data.run_id == delta.run_id
    assert typed.data.metadata.strategy == :cot
    assert :ok = MockLLM.release(mock, :held)
    assert {:ok, "4"} = Request.await(request)
    remaining = events(request)
    assert Enum.any?(remaining, &(&1.kind == :request_completed))
    assert record(server, request).meta.termination_reason == :success
    assert_script_done(mock)
  end

  for method <- [:chain_of_thought, :chain_of_draft, :react] do
    test "#{method} retains ordered generated media and never applies text conclusion parsing to a rich result",
         %{jido: jido} do
      content = [
        %{type: "text", text: "Conclusion: keep the image"},
        %{type: "image_url", image_url: %{url: "https://example.test/generated.png"}},
        %{type: "text", text: "after image"}
      ]

      {mock, context} = mock([%{reply: response(%{content: content})}])
      source = source(CoT)

      server =
        start(jido, CoT, %{
          reasoning: %{source.reasoning | method: unquote(method)},
          requests: %{source.requests | streaming: false}
        })

      assert {:ok, request} = request(server, context)
      assert {:ok, parts} = Request.await(request)
      assert Enum.map(parts, & &1.type) == [:text, :image_url, :text]
      assert Enum.at(parts, 0).text == "Conclusion: keep the image"
      assert Enum.at(parts, 1).url == "https://example.test/generated.png"
      assert Enum.at(parts, 2).text == "after image"
      assert Server.agent(server).state.reply == parts
      assert :ok = Jido.Action.validate_static_data(Server.agent(server).state)

      if unquote(method) != :react do
        assert record(server, request).meta.reasoning.steps == []
        assert record(server, request).meta.reasoning.conclusion == nil
      end

      typed = delivered(server, request)
      assert List.last(typed).data.result == parts
      assert_script_done(mock)
    end
  end

  for {module, method, helper} <- [
        {PublicCoT, :chain_of_thought, :think},
        {PublicCoD, :chain_of_draft, :draft}
      ] do
    test "#{method} streams complete image parts before committing its rich result", %{jido: jido} do
      image = ReqLLM.Message.ContentPart.image(<<1, 2, 3>>, "image/png")
      delta = %{images: [%{type: "image_url", image_url: %{url: "data:image/png;base64,AQID"}}]}
      {mock, context} = mock([%{reply: {:stream, [delta, {:wait, :image}], "stop"}}])
      module = unquote(module)
      assert {:ok, server} = Jido.start_agent(jido, module, default_dispatch: {:pid, target: self()})

      assert {:ok, request} =
               apply(module, unquote(helper), [server, "Generate", [context: context, stream_to: self()]])

      assert_receive {:mock_llm_waiting, ^mock, :image, _}, 2_000

      assert_receive {:jido_ai_request_event,
                      %{kind: :llm_delta, data: %{chunk_type: :content_part, delta: ^image}} = event},
                     1_000

      assert event.method == unquote(method) and event.request_id == request.id
      assert_receive {:signal, %{type: "ai.llm.delta", data: data}}, 1_000
      assert data.delta == image and data.chunk_type == :content_part
      assert data.seq == event.seq and data.run_id == event.run_id and data.call_id == event.llm_call_id
      assert {:ok, view} = Session.snapshot(server)
      assert view.details.streaming_text == "" and view.request.status == :pending
      assert Enum.find(view.details.trace.events, &(&1.id == event.id)).data.delta == image
      assert :ok = MockLLM.release(mock, :image)
      assert {:ok, [^image]} = module.await(request)
      assert record(server, request).result == [image]
      assert record(server, request).meta.reasoning.steps == []
      assert record(server, request).meta.reasoning.raw_response == ""
      typed = delivered(server, request)
      assert List.last(typed).data.result == [image]
      assert :ok = Jido.Action.validate_static_data(Server.agent(server).state)
      assert_script_done(mock)
    end
  end

  test "public linear queries retain media input and printable rich result fields", %{jido: jido} do
    content = [%{type: "image_url", image_url: %{url: "https://example.test/generated.png"}}]

    {mock, context} =
      mock([%{reply: response(%{content: content})}, %{reply: {:text, "#### Seen"}}])

    module = JidoAI.Examples.Linear.PublicMedia
    assert {:ok, server} = Jido.start_agent(jido, module)

    query = [
      ReqLLM.Message.ContentPart.text("Read"),
      ReqLLM.Message.ContentPart.image_url("https://example.test/input.png")
    ]

    assert {:ok, request} = module.think(server, query, context: context)
    assert {:ok, [image]} = module.await(request)
    assert image.type == :image_url
    assert is_binary(Server.agent(server).state.last_result)
    assert Server.agent(server).state.last_prompt == query
    assert record(server, request).result == [image]
    assert {:ok, next_server} = Jido.start_agent(jido, PublicCoD)
    assert {:ok, "Seen"} = PublicCoD.draft_sync(next_server, query, context: context)

    for wire <- MockLLM.report(mock).requests do
      assert Enum.any?(List.last(wire.body["messages"])["content"], &(&1["type"] == "image_url"))
    end

    assert_script_done(mock)
  end

  test "prompt attributes defaults and legacy option inspection use the same model request", %{
    jido: jido
  } do
    {mock, context} = mock(List.duplicate(%{reply: {:text, "Conclusion: ok"}}, 10))

    for {base, method, helper} <- [
          {Jido.AI.CoTAgent, :chain_of_thought, :think_sync},
          {Jido.AI.CoDAgent, :chain_of_draft, :draft_sync}
        ],
        value <- [nil, false, "", "Exact prompt", "Attribute prompt"] do
      module = Module.concat(__MODULE__, "Prompt#{System.unique_integer([:positive])}")

      code = """
      defmodule #{inspect(module)} do
        @prompt #{inspect(value)}
        use #{inspect(base)}, name: "linear_prompt", model: :example, system_prompt: @prompt
      end
      """

      Code.compile_string(code)
      assert {:ok, server} = Jido.start_agent(jido, module)
      assert {:ok, "ok"} = apply(module, helper, [server, "Query", [context: context]])
      expected = if value in [nil, false, ""], do: Linear.default_prompt(method), else: value
      wire = List.last(MockLLM.report(mock).requests)
      assert hd(wire.body["messages"])["content"] == expected
      opts = module.strategy_opts()
      assert opts[:model] == :example

      if method == :chain_of_thought and value in [nil, false, ""],
        do: refute(Keyword.has_key?(opts, :system_prompt)),
        else: assert(opts[:system_prompt] == expected)
    end

    assert_script_done(mock)
  end

  test "invalid public prompt and method values fail during authoring" do
    for base <- [Jido.AI.CoTAgent, Jido.AI.CoDAgent] do
      module = Module.concat(__MODULE__, "Invalid#{System.unique_integer([:positive])}")

      code = """
      defmodule #{inspect(module)} do
        @prompt 123
        use #{inspect(base)}, name: "invalid_linear_prompt", model: :example, system_prompt: @prompt
      end
      """

      assert_raise CompileError, ~r/system_prompt must be/, fn -> Code.compile_string(code) end
    end

    assert_raise ArgumentError, ~r/reasoning method is not yet ported/, fn ->
      Jido.AI.Agent.Options.lower!(name: "invalid", reasoning: :unknown)
    end

    for module <- [CoT, CoD] do
      assert {:error, _} = Authoring.lower(base(module), [%{source(module) | instructions: 123}])
    end
  end

  test "a linear deadline closes the real provider and leaves no successful answer", %{jido: jido} do
    {mock, context} =
      mock([%{reply: {:stream, [{:wait, :held}, %{content: "Conclusion: late"}], "stop"}}])

    source = source(CoT)
    server = start(jido, CoT, %{controls: %{source.controls | timeout: 300}})
    assert {:ok, request} = request(server, context)
    assert_receive {:mock_llm_waiting, ^mock, :held, provider}, 2_000
    monitor = Process.monitor(provider)
    assert {:error, reason} = Request.await(request)
    refute reason == :timeout
    assert_receive {:DOWN, ^monitor, :process, ^provider, _}, 2_000
    assert record(server, request).status == :failed and Server.agent(server).state.reply == nil
    assert List.last(events(request)).kind == :request_failed
    eventually(fn -> MockLLM.report(mock).waiting == [] end)
    assert_script_done(mock)
  end

  test "owner restart retains the method in the interrupted record and permits a fresh request",
       %{jido: jido} do
    {mock, context} =
      mock([
        %{reply: {:stream, [{:wait, :held}, %{content: "Conclusion: lost"}], "stop"}},
        %{reply: {:text, "#### next"}}
      ])

    server = start(jido, CoD)
    assert {:ok, request} = request(server, context)
    assert_receive {:mock_llm_waiting, ^mock, :held, provider}, 2_000
    monitor = Process.monitor(provider)
    runtime = Server.children(server)[{:plugin, Session.Plugin}].pid
    Process.exit(runtime, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^provider, _}, 2_000
    assert {:error, :stream_interrupted} = Request.await(request)
    assert record(server, request).method == :chain_of_draft
    assert {:ok, next} = request(server, context)
    assert {:ok, "next"} = Request.await(next)
    assert record(server, next).method == :chain_of_draft
    assert record(server, next).run_id != record(server, request).run_id
    eventually(fn -> MockLLM.report(mock).waiting == [] end)
    assert_script_done(mock)
  end

  test "shared namespace helpers retain CoT and CoD prompts parsers and call ID prefixes" do
    alias Jido.AI.Reasoning.{ChainOfThought, ChainOfDraft}
    assert ChainOfThought.default_system_prompt() == Linear.default_prompt(:chain_of_thought)
    assert ChainOfDraft.default_system_prompt() == Linear.default_prompt(:chain_of_draft)
    assert String.starts_with?(ChainOfThought.generate_call_id(), "cot_")
    assert String.starts_with?(ChainOfDraft.generate_call_id(), "cod_")

    assert ChainOfThought.extract_steps_and_conclusion("Step 1: Add.\nConclusion: 4") ==
             {[%{number: 1, content: "Add."}], "4"}

    assert ChainOfDraft.extract_steps_and_conclusion("draft #### 4") == {[], "4"}
  end

  test "linear telemetry records method identity and honors the independent observation flag", %{
    jido: jido
  } do
    observe()
    {mock, context} = mock(List.duplicate(%{reply: {:text, "Conclusion: 4"}}, 4))

    for module <- [CoT, CoD], enabled <- [true, false] do
      server = start(jido, module, %{observability: %{emit_telemetry?: enabled}})
      assert {:ok, request} = request(server, context)
      assert {:ok, "4"} = Request.await(request)
      typed = delivered(server, request)
      assert List.last(typed).type == "ai.request.completed"

      reports =
        telemetry() |> Enum.filter(fn {_, _, metadata} -> metadata.request_id == request.id end)

      if enabled do
        assert Enum.any?(reports, fn {event, _, _} ->
                 event == [:jido, :ai, :request, :complete]
               end)

        assert Enum.any?(reports, fn {event, _, _} -> event == [:jido, :ai, :llm, :complete] end)

        assert Enum.all?(reports, fn {_, _, metadata} ->
                 metadata.strategy == Linear.label(source(module).reasoning.method)
               end)
      else
        assert reports == []
      end
    end

    assert_script_done(mock)
  end

  test "known request error types survive linear request telemetry", %{jido: jido} do
    observe()
    {mock, context} = mock([%{reply: {:text, "Conclusion: 4"}}])
    server = start(jido, CoT)
    error = %{type: :domain_policy, message: "Denied"}
    assert {:ok, request} = request(server, Map.put(context, :rejection, error))
    assert {:error, ^error} = Request.await(request)
    delivered(server, request)

    assert Enum.any?(telemetry(), fn {event, _, metadata} ->
             event == [:jido, :ai, :request, :failed] and metadata.request_id == request.id and
               metadata.error_type == :domain_policy and metadata.strategy == :cot
           end)

    assert_script_done(mock)
  end

  test "ordinary Agent turns execute the same linear result without a session owner", %{
    jido: jido
  } do
    {mock, context} = mock(List.duplicate(%{reply: {:text, "Conclusion: 4"}}, 2))

    for module <- [CoT, CoD] do
      src = source(module)
      server = start(jido, module, %{requests: %{src.requests | mode: :turn}})

      assert {:ok, agent} =
               Server.call(server, Jido.Signal.new!("ai.ask", %{query: "Add"}, source: "/linear"), context: context)

      assert agent.state.reply == "4"
      refute Map.has_key?(agent.state, :requests)
      refute Map.has_key?(Server.children(server), {:plugin, Session.Plugin})
    end

    assert_script_done(mock)
  end

  test "the public cancellation helper retains its reason and closes CoD work", %{jido: jido} do
    {mock, context} = mock([%{reply: {:stream, [%{content: "draft"}, {:wait, :held}], "stop"}}])
    assert {:ok, server} = Jido.start_agent(jido, PublicCoD)
    assert {:ok, request} = PublicCoD.draft(server, "Draft", context: context)
    assert_receive {:mock_llm_waiting, ^mock, :held, provider}, 2_000
    monitor = Process.monitor(provider)
    assert :ok = PublicCoD.cancel(server, request_id: request.id, reason: :changed_plan)
    assert {:error, {:cancelled, :changed_plan}} = PublicCoD.await(request)
    assert_receive {:DOWN, ^monitor, :process, ^provider, _}, 2_000
    assert record(server, request).method == :chain_of_draft
    assert Server.agent(server).state.completed
    assert is_binary(Server.agent(server).state.last_result)
    eventually(fn -> MockLLM.report(mock).waiting == [] end)
    assert_script_done(mock)
  end

  test "a second linear request is refused while the first request owns the session", %{
    jido: jido
  } do
    {mock, context} =
      mock([%{reply: {:stream, [{:wait, :held}, %{content: "Conclusion: first"}], "stop"}}])

    server = start(jido, CoT)
    assert {:ok, request} = request(server, context)
    assert_receive {:mock_llm_waiting, ^mock, :held, _}, 2_000
    assert {:error, :busy} = request(server, context, "Second")
    assert map_size(Server.agent(server).state.requests) == 1
    assert :ok = MockLLM.release(mock, :held)
    assert {:ok, "first"} = Request.await(request)
    assert_script_done(mock)
  end

  test "ordinary structured output telemetry uses the selected method", %{jido: jido} do
    observe()
    {mock, context} = mock([%{reply: {:object, %{answer: 4}}}])
    source = source(CoD)

    server =
      start(jido, CoD, %{
        requests: %{source.requests | mode: :turn},
        result: %{into: :reply, schema: Zoi.object(%{answer: Zoi.integer()})}
      })

    assert {:ok, %{state: %{reply: %{answer: 4}}}} =
             Server.call(server, Jido.Signal.new!("ai.ask", %{query: "Add"}, source: "/linear"), context: context)

    output =
      Enum.filter(telemetry(), fn {event, _, _} ->
        Enum.take(event, 3) == [:jido, :ai, :output]
      end)

    assert Enum.map(output, &elem(&1, 0)) == [
             [:jido, :ai, :output, :start],
             [:jido, :ai, :output, :validated]
           ]

    assert Enum.all?(output, fn {_, _, metadata} -> metadata.strategy == :cod end)
    assert_script_done(mock)
  end

  test "public model options preserve precedence and a transport timeout closes only the model call",
       %{jido: jido} do
    alias JidoAI.Examples.Linear.PublicLimits

    {mock, context} =
      mock([
        %{reply: {:text, "Conclusion: 4"}},
        %{reply: {:stream, [{:wait, :held}, %{content: "Conclusion: late"}], "stop"}}
      ])

    context =
      put_in(
        context.ai.assistant.options,
        Keyword.delete(context.ai.assistant.options, :receive_timeout)
      )

    assert {:ok, server} = Jido.start_agent(jido, PublicLimits)
    assert {:ok, "4"} = PublicLimits.think_sync(server, "Add", context: context)
    assert hd(MockLLM.report(mock).requests).body["max_tokens"] == 23
    started = System.monotonic_time(:millisecond)
    assert {:ok, request} = PublicLimits.think(server, "Wait", context: context)
    assert_receive {:mock_llm_waiting, ^mock, :held, provider}, 2_000
    monitor = Process.monitor(provider)
    assert {:error, reason} = PublicLimits.await(request)
    refute reason == :timeout
    assert System.monotonic_time(:millisecond) - started < 1_500
    assert_receive {:DOWN, ^monitor, :process, ^provider, _}, 2_000
    assert Process.alive?(server)
    assert record(server, request).status == :failed
    eventually(fn -> MockLLM.report(mock).waiting == [] end)
    assert_script_done(mock)
  end

  test "the public whole-request deadline is separate from the provider timeout", %{jido: jido} do
    alias JidoAI.Examples.Linear.PublicDeadline

    {mock, context} =
      mock([%{reply: {:stream, [{:wait, :held}, %{content: "#### late"}], "stop"}}])

    assert {:ok, server} = Jido.start_agent(jido, PublicDeadline)
    assert {:ok, request} = PublicDeadline.draft(server, "Wait", context: context)
    assert_receive {:mock_llm_waiting, ^mock, :held, provider}, 2_000
    monitor = Process.monitor(provider)
    assert {:error, reason} = PublicDeadline.await(request)
    refute reason == :timeout
    assert_receive {:DOWN, ^monitor, :process, ^provider, _}, 2_000

    assert record(server, request).method == :chain_of_draft and
             record(server, request).status == :failed

    eventually(fn -> MockLLM.report(mock).waiting == [] end)
    assert_script_done(mock)
  end

  test "public transport and request timeout options reject invalid static values" do
    for value <- [-1, 0, "100"] do
      assert_raise ArgumentError, ~r/llm_timeout_ms must be/, fn ->
        Jido.AI.Agent.Options.lower!(
          name: "invalid_timeout",
          reasoning: :chain_of_thought,
          model: :example,
          llm_timeout_ms: value
        )
      end

      assert_raise Jido.AI.Error.Validation.Invalid, fn ->
        Jido.AI.Agent.Options.lower!(
          name: "invalid_timeout",
          reasoning: :chain_of_draft,
          model: :example,
          request_timeout_ms: value
        )
      end
    end
  end

  defp observe do
    id = "linear-#{Jido.Signal.ID.generate!()}"

    events =
      for {family, phases} <- [
            request: [:start, :complete, :failed, :cancelled],
            llm: [:start, :delta, :complete],
            output: [:start, :validated, :error, :repair]
          ],
          phase <- phases,
          do: [:jido, :ai, family, phase]

    :ok = :telemetry.attach_many(id, events, &JidoAI.Examples.Linear.Telemetry.handle/4, self())
    on_exit(fn -> :telemetry.detach(id) end)
  end

  defp telemetry(acc \\ []) do
    receive do
      {:linear_telemetry, event, measurements, metadata} ->
        telemetry([{event, measurements, metadata} | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp atoms(%_{}), do: []
  defp atoms(map) when is_map(map), do: Enum.flat_map(map, fn {k, v} -> atoms(k) ++ atoms(v) end)
  defp atoms(list) when is_list(list), do: Enum.flat_map(list, &atoms/1)
  defp atoms(value) when is_tuple(value), do: value |> Tuple.to_list() |> atoms()
  defp atoms(atom) when is_atom(atom), do: [atom]
  defp atoms(_), do: []
  defp eventually(fun, attempts \\ 300)
  defp eventually(fun, 0), do: assert(fun.())

  defp eventually(fun, attempts),
    do:
      if(fun.(),
        do: :ok,
        else:
          (
            Process.sleep(10)
            eventually(fun, attempts - 1)
          )
      )
end
