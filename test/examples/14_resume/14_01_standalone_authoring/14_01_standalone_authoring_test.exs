defmodule JidoAI.Examples.StandaloneAuthoringTest do
  use JidoAI.Examples.Case
  alias Jido.AI.{Configuration, Request, Orchestration}
  alias Jido.AI.Reasoning.ReAct.{Config, State, Token}
  alias JidoAI.Examples.StandaloneAuthoring.{Agent, Add, Change, Transform, Repair}

  test "standalone Config lowers into aliased real tools and exact generation options", %{
    jido: jido
  } do
    {mock, _} =
      mock([
        %{reply: {:tools, [%{id: "add-1", name: "sum_case", arguments: %{a: 2, b: 3}}]}},
        %{reply: {:text, "Five"}}
      ])

    config =
      config(mock,
        tools: %{"sum_case" => Add},
        system_prompt: "Add case values.",
        max_tokens: 321,
        temperature: 0.4,
        tool_concurrency: 2,
        tool_timeout_ms: 900,
        tool_max_retries: 0
      )

    assert {:ok, definition, context} = Agent.build(config)
    assert definition.state == nil
    assert :ok = Jido.Action.validate_static_data(definition)
    assert {:ok, profile} = Configuration.profile(definition)
    assert profile.reasoning.tool_concurrency == 2
    assert [%{name: "sum_case", target: Add, timeout: 900, max_retries: 0}] = profile.tools
    server = start_agent(jido, Jido.Agent.instantiate!(definition))
    assert {:ok, request} = submit(server, context, "Sum")
    assert {:ok, "Five"} = Request.await(request)
    assert_receive {:standalone_add, _, 2, 3}
    [first, last] = MockLLM.report(mock).requests
    assert hd(first.body["messages"])["content"] == "Add case values."
    assert hd(first.body["tools"])["function"]["name"] == "sum_case"
    assert first.body["max_tokens"] == 321 and first.body["temperature"] == 0.4
    assert List.last(last.body["messages"])["tool_call_id"] == "add-1"
    assert Server.agent(server).state.requests[request.id].meta.usage.total_tokens == 30
    assert_script_done(mock)
  end

  test "runtime credentials and HTTP callbacks stay outside the portable definition", %{
    jido: jido
  } do
    {mock, _} = mock([%{reply: {:text, "Bound"}}])
    parent = self()

    callback = fn request ->
      send(parent, :standalone_http_callback)
      Req.Request.put_header(request, "x-case", "one")
    end

    config =
      config(mock,
        token_secret: "standalone-secret-a",
        llm_opts: [
          api_key: "transport-secret-a",
          req_http_options: [
            retry: false,
            adapter: JidoAI.Examples.ModelOptions.HttpAdapter,
            finch_private: [example_callback: callback]
          ]
        ]
      )

    assert {:ok, definition, context} = Agent.build(config)

    other = %{
      config
      | token: %{config.token | secret: "standalone-secret-b"},
        llm: %{config.llm | llm_opts: []}
    }

    assert {:ok, ^definition, _} = Agent.build(other)
    assert :ok = Jido.Action.validate_static_data(definition)
    refute inspect(definition, limit: :infinity) =~ "transport-secret"
    server = start_agent(jido, Jido.Agent.instantiate!(definition))
    assert {:ok, request} = submit(server, context, "Bind")
    assert {:ok, "Bound"} = Request.await(request)
    assert_receive :standalone_http_callback
    assert :ok = Jido.Action.validate_static_data(Server.agent(server).state)
    [wire] = MockLLM.report(mock).requests
    assert wire.headers["x-case"] == "one"
    assert_script_done(mock)
  end

  test "native Builder and Codec forms run the same lowered standalone configuration", %{
    jido: jido
  } do
    {mock, _} = mock(List.duplicate(%{reply: {:text, "Same"}}, 3))
    assert {:ok, definition, context} = Agent.build(config(mock))
    attrs = definition |> Map.from_struct() |> Map.drop([:id, :state])
    assert {:ok, built} = attrs |> Jido.Agent.Builder.new() |> Jido.Agent.Builder.build()
    assert {:ok, document, registry} = Jido.Agent.Codec.encode(definition)

    assert {:ok, decoded} =
             Jido.Agent.Codec.decode(Jason.decode!(Jason.encode!(document)), registry)

    assert definition == built and built == decoded

    for form <- [definition, built, decoded] do
      server = start_agent(jido, Jido.Agent.instantiate!(form))
      assert {:ok, request} = submit(server, context, "Same")
      assert {:ok, "Same"} = Request.await(request)
    end

    assert_script_done(mock)
  end

  test "typed output uses the shared repair callback and preserves explicit model budgets", %{
    jido: jido
  } do
    {mock, _} = mock([%{reply: {:text, "Invalid JSON"}}])

    config =
      config(mock,
        max_iterations: 2,
        output: [
          schema: Zoi.object(%{answer: Zoi.string()}),
          retries: 1,
          repair_fun: {Repair, :fix}
        ]
      )

    assert {:ok, definition, context} = Agent.build(config)
    assert {:ok, profile} = Configuration.profile(definition)
    assert profile.controls.max_iterations == 2
    assert profile.controls.max_model_calls == 3
    server = start_agent(jido, Jido.Agent.instantiate!(definition))
    assert {:ok, request} = submit(server, context, "Typed")
    assert {:ok, %{answer: "Repaired"}} = Request.await(request)
    assert_receive :standalone_repair
    assert_script_done(mock)
  end

  test "state effects are visible to the next transform and commit through core", %{jido: jido} do
    {mock, _} =
      mock([
        %{reply: {:tools, [%{id: "change-1", name: "change", arguments: %{count: 7}}]}},
        %{reply: {:text, "Changed"}}
      ])

    assert {:ok, definition, context} =
             Agent.build(config(mock, tools: [Change], request_transformer: Transform))

    server = start_agent(jido, Jido.Agent.instantiate!(definition))
    assert {:ok, request} = submit(server, context, "Change")
    assert {:ok, "Changed"} = Request.await(request)
    assert_receive {:standalone_count, 0}
    assert_receive {:standalone_count, 7}
    assert Server.agent(server).state.count == 7
    assert_script_done(mock)
  end

  test "explicit native tool limits refuse a complete oversized batch before tool work", %{
    jido: jido
  } do
    calls = for i <- 1..2, do: %{id: "add-#{i}", name: "add", arguments: %{a: i, b: 1}}
    {mock, _} = mock([%{reply: {:tools, calls}}])

    assert {:ok, definition, context} =
             Agent.build(config(mock, tools: [Add]), %{timeout: 5_000, max_tool_calls: 1})

    server = start_agent(jido, Jido.Agent.instantiate!(definition))
    assert {:ok, request} = submit(server, context, "Bounded")
    assert {:error, _} = Request.await(request)
    refute_receive {:standalone_add, _, _, _}, 20
    assert_script_done(mock)
  end

  test "streaming configuration retains real deltas and cancellation stops the held provider", %{
    jido: jido
  } do
    {mock, _} =
      mock([
        %{
          reply: {:stream, [%{content: "Part"}, {:wait, :standalone_stream}, %{content: "Unused"}]}
        }
      ])

    assert {:ok, definition, context} =
             Agent.build(config(mock, streaming: true, tool_heartbeat_ms: 10))

    assert {:ok, profile} = Configuration.profile(definition)
    assert profile.requests.tool_heartbeat == 10
    server = start_agent(jido, Jido.Agent.instantiate!(definition))
    assert {:ok, request} = submit(server, context, "Stream", stream_to: self())
    assert_receive {:mock_llm_waiting, ^mock, :standalone_stream, provider}, 2_000
    ref = Process.monitor(provider)
    assert :ok = Orchestration.cancel(request)
    events = request |> Request.Stream.events() |> Enum.to_list()
    assert Enum.any?(events, &(&1.kind == :llm_delta and &1.data.delta == "Part"))
    assert List.last(events).kind == :request_cancelled
    assert_receive {:DOWN, ^ref, :process, ^provider, _}, 2_000
    assert_script_done(mock)
  end

  test "missing limits and invalid native tool concurrency fail before admission" do
    {mock, _} = mock([])
    config = config(mock)

    for limits <- [
          %{},
          %{timeout: 100},
          %{timeout: 0, max_tool_calls: 3},
          %{timeout: 100, max_tool_calls: 0}
        ] do
      assert {:error, _} = Agent.build(config, limits)
    end

    assert {:error, _} = Agent.build(%{config | tool_exec: %{config.tool_exec | concurrency: 65}})
    assert_script_done(mock)
  end

  test "two public aliases for one Action keep distinct provider names and execute twice", %{
    jido: jido
  } do
    calls =
      for name <- ["first_sum", "second_sum"],
          do: %{id: name, name: name, arguments: %{a: 1, b: 2}}

    {mock, _} = mock([%{reply: {:tools, calls}}, %{reply: {:text, "Both"}}])
    config = config(mock, tools: %{"first_sum" => Add, "second_sum" => Add})

    assert Enum.sort(Enum.map(Config.reqllm_tools(config), & &1.name)) == [
             "first_sum",
             "second_sum"
           ]

    assert {:ok, definition, context} = Agent.build(config)
    server = start_agent(jido, Jido.Agent.instantiate!(definition))
    assert {:ok, request} = submit(server, context, "Both")
    assert {:ok, "Both"} = Request.await(request)
    assert_receive {:standalone_add, _, 1, 2}
    assert_receive {:standalone_add, _, 1, 2}
    [wire, _] = MockLLM.report(mock).requests

    assert Enum.sort(Enum.map(wire.body["tools"], & &1["function"]["name"])) == [
             "first_sum",
             "second_sum"
           ]

    assert_script_done(mock)
  end

  test "the retained token codec restores State data in another process without executing a model" do
    {mock, _} = mock([])
    config = config(mock, token_compress?: true)

    original =
      State.new("Saved", config.system_prompt, request_id: "saved-request", run_id: "saved-run")

    token = Token.issue(original, config)

    assert {:ok, ^original, payload} =
             Task.async(fn -> Token.decode_state(token, config) end) |> Task.await()

    assert payload.v == 2
    assert {:ok, cancelled} = Token.mark_cancelled(token, config, :stopped)

    assert {:ok,
            %{
              status: :cancelled,
              result: nil,
              error: :stopped,
              pending_tool_calls: [],
              termination_reason: :cancelled
            }, _} = Token.decode_state(cancelled, config)

    assert {:error, :token_config_mismatch} = Token.decode(token, %{config | max_iterations: 20})
    assert {:error, :invalid_token_signature} = Token.decode(token <> "x", config)
    assert_script_done(mock)
  end

  test "token issuance rejects process handles and callbacks in saved state" do
    {mock, _} = mock([])
    config = config(mock)
    state = State.new("Saved", nil)

    for value <- [self(), make_ref(), fn -> :live end] do
      assert_raise ArgumentError, ~r/nonportable_token_state/, fn ->
        Token.issue(%{state | result: %{live: value}}, config)
      end
    end

    assert_script_done(mock)
  end

  test "signed token decoding rejects live state and mismatched request identity" do
    {mock, _} = mock([])
    config = config(mock)
    state = State.new("Saved", nil)
    assert {:ok, payload} = Token.decode(Token.issue(state, config), config)
    live = %{payload | state: Map.put(payload.state, :result, self())}
    assert {:error, :nonportable_token_state} = Token.decode(forge(live, config), config)
    wrong = %{payload | request_id: "different-request"}
    assert {:error, :token_identity_mismatch} = Token.decode(forge(wrong, config), config)
    assert_script_done(mock)
  end

  defp forge(payload, config) do
    bytes = :erlang.term_to_binary(payload)
    signature = :crypto.mac(:hmac, :sha256, config.token.secret, bytes)

    "rt2." <>
      Base.url_encode64(bytes, padding: false) <>
      "." <> Base.url_encode64(signature, padding: false)
  end

  defp config(mock, opts \\ []) do
    opts =
      Keyword.put(
        opts,
        :llm_opts,
        Keyword.merge(MockLLM.options(mock), Keyword.get(opts, :llm_opts, []))
      )

    assert URI.parse(opts[:llm_opts][:base_url]).host == "127.0.0.1"

    Config.new(
      Keyword.merge(
        [
          model: MockLLM.model(),
          tools: [],
          streaming: false,
          token_secret: "standalone-fixture-secret",
          llm_opts: MockLLM.options(mock)
        ],
        opts
      )
    )
  end

  defp submit(server, context, query, opts \\ []) do
    Request.create_and_send(
      server,
      query,
      Keyword.merge(
        [
          signal_type: "ai.react.query",
          source: "/examples/standalone",
          context: Map.put(context, :observer, self())
        ],
        opts
      )
    )
  end
end
