defmodule JidoAI.Examples.MethodAPITest do
  use JidoAI.Examples.Case
  alias Jido.AI.{Request, Session}
  alias Jido.AI.Reasoning.{ChainOfThought, ChainOfDraft}
  alias Jido.AI.Reasoning.ChainOfThought.Machine

  defp start(jido) do
    assert {:ok, definition} = JidoAI.Examples.MethodAPI.definition()
    start_agent(jido, Jido.Agent.instantiate!(definition))
  end

  defp context(mock),
    do: %{ai: Map.new([:cot, :cod], &{&1, %{options: MockLLM.options(mock)}})}

  defp request(server, mock, method) do
    Request.create_and_send(server, "Solve",
      signal_type: "ai.#{method}.query",
      source: "/examples/method-api",
      context: context(mock)
    )
  end

  test "namespace method selection runs both profiles and reads their separate stored results", %{
    jido: jido
  } do
    {mock, _} =
      mock([
        %{reply: {:text, "Step 1: Add.\nConclusion: 4"}},
        %{reply: {:text, "1. Sum.\n#### 5"}}
      ])

    server = start(jido)
    assert ChainOfThought.get_steps(Server.agent(server)) == []
    assert ChainOfDraft.get_conclusion(Server.agent(server)) == nil
    assert {:ok, cot} = request(server, mock, :cot)
    assert {:ok, "4"} = Request.await(cot)
    assert {:ok, cod} = request(server, mock, :cod)
    assert {:ok, "5"} = Request.await(cod)
    agent = Server.agent(server)
    assert ChainOfThought.get_steps(agent) == [%{number: 1, content: "Add."}]
    assert ChainOfDraft.get_steps(agent) == [%{number: 1, content: "Sum."}]
    assert ChainOfThought.get_conclusion(agent, cot.id) == "4"
    assert ChainOfDraft.get_conclusion(agent, cod.id) == "5"
    assert ChainOfThought.get_raw_response(agent) == "Step 1: Add.\nConclusion: 4"
    assert ChainOfDraft.get_raw_response(agent) == "1. Sum.\n#### 5"
    assert ChainOfThought.get_steps(agent, cod.id) == []
    assert ChainOfDraft.get_raw_response(agent, "missing") == nil
    [first, second] = MockLLM.report(mock).requests
    assert hd(first.body["messages"])["content"] == ChainOfThought.default_system_prompt()
    assert hd(second.body["messages"])["content"] == ChainOfDraft.default_system_prompt()
    assert_script_done(mock)
  end

  test "legacy namespace modules remain loadable result adapters without old core execution", %{
    jido: jido
  } do
    {mock, _} =
      mock([%{reply: {:text, "Step 1: Add.\nConclusion: 4"}}, %{reply: {:text, "#### 5"}}])

    server = start(jido)

    for {namespace, method, answer} <- [{ChainOfThought, :cot, "4"}, {ChainOfDraft, :cod, "5"}] do
      assert {:ok, handle} = request(server, mock, method)
      assert {:ok, ^answer} = Request.await(handle)
      adapter = apply(namespace, :strategy_module, [])
      assert Code.ensure_loaded?(adapter)
      agent = Server.agent(server)
      assert apply(adapter, :get_steps, [agent]) == namespace.get_steps(agent)
      assert apply(adapter, :get_conclusion, [agent]) == answer
      assert apply(adapter, :get_raw_response, [agent]) == namespace.get_raw_response(agent)
      refute function_exported?(adapter, :cmd, 3)
      refute function_exported?(adapter, :init, 2)
    end

    assert_script_done(mock)
  end

  test "a new pending or cancelled request cannot expose an earlier result as current", %{
    jido: jido
  } do
    {mock, _} =
      mock([
        %{reply: {:text, "Conclusion: first"}},
        %{reply: {:stream, [{:wait, :held}, %{content: "Conclusion: late"}], "stop"}}
      ])

    server = start(jido)
    assert {:ok, first} = request(server, mock, :cot)
    assert {:ok, "first"} = Request.await(first)
    assert {:ok, next} = request(server, mock, :cot)
    assert_receive {:mock_llm_waiting, ^mock, :held, provider}, 2_000
    monitor = Process.monitor(provider)
    agent = Server.agent(server)
    assert ChainOfThought.get_conclusion(agent) == nil
    assert ChainOfThought.get_steps(agent) == []
    assert ChainOfThought.get_conclusion(agent, first.id) == "first"
    assert :ok = Session.cancel(next)
    assert {:error, :cancelled} = Request.await(next)
    assert_receive {:DOWN, ^monitor, :process, ^provider, _}, 2_000
    assert ChainOfThought.get_raw_response(Server.agent(server)) == nil
    assert_script_done(mock)
  end

  test "the retained Machine reads an actual provider result and restores its data shape" do
    {mock, _} = mock([%{reply: {:text, "Step 1: café ✓\nStep 2: Sum.\nConclusion: 4"}}])

    {machine, [{:call_llm_stream, id, conversation}]} =
      Machine.update(Machine.new(), {:start, "Add", "cot_api"})

    opts = Keyword.put(MockLLM.options(mock), :model, MockLLM.model())
    assert {:ok, response} = Jido.AI.Models.generate_text(conversation, opts)
    legacy_result = %{text: ReqLLM.Response.text(response), usage: response.usage}
    assert {completed, []} = Machine.update(machine, {:llm_result, id, {:ok, legacy_result, []}})
    assert completed.result == "4" and completed.termination_reason == :success
    assert completed.steps == [%{number: 1, content: "café ✓"}, %{number: 2, content: "Sum."}]
    assert completed.usage.total_tokens == 15
    assert Machine.from_map(Machine.to_map(completed)) == completed
    assert Machine.to_map(completed).status == :completed
    assert_script_done(mock)
  end

  test "the retained Machine keeps busy rejection stale-call checks raw errors and terminal closure" do
    {running, [_]} = Machine.update(Machine.new(), {:start, "Add", "one"})

    assert {^running, [{:request_error, "two", :busy, _}]} =
             Machine.update(running, {:start, "Again", "two"})

    assert {^running, []} = Machine.update(running, {:llm_result, "stale", {:error, :wrong}})
    assert {^running, []} = Machine.update(running, {:llm_partial, "stale", "lost", :content})
    {partial, []} = Machine.update(running, {:llm_partial, "one", "kept", :content})
    error = %{type: :rate_limit, retryable?: true, details: %{request: "one"}}
    assert {failed, []} = Machine.update(partial, {:llm_result, "one", {:error, error, []}})
    assert failed.result == error and failed.streaming_text == "kept"
    assert failed.status == "error" and failed.termination_reason == :error
    assert {^failed, []} = Machine.update(failed, {:start, "No restart", "two"})
  end

  test "the retained Machine uses the common nested usage merge without losing provider metadata" do
    {machine, [_]} = Machine.update(Machine.new(), {:start, "Add", "one"})

    machine = %{
      machine
      | usage: %{"details" => %{"cached_tokens" => 3}, "provider" => "old", :input_tokens => 2}
    }

    result = %{
      text: "Conclusion: 4",
      usage: %{"input_tokens" => "5", "details" => %{"cached_tokens" => 4}, "provider" => "new"}
    }

    assert {completed, []} = Machine.update(machine, {:llm_result, "one", {:ok, result}})
    assert completed.usage.input_tokens == 7
    assert completed.usage["details"]["cached_tokens"] == 7
    assert completed.usage["provider"] == "new"
  end

  test "the retained Machine emits its legacy start and completion telemetry with usage" do
    id = "machine_api_#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach_many(
        id,
        [[:jido, :ai, :cot, :start], [:jido, :ai, :cot, :complete]],
        &JidoAI.Examples.Linear.Telemetry.handle/4,
        self()
      )

    on_exit(fn -> :telemetry.detach(id) end)
    {running, [_]} = Machine.update(Machine.new(), {:start, "Add", "one"})

    assert_receive {:linear_telemetry, [:jido, :ai, :cot, :start], %{system_time: time},
                    %{call_id: "one", prompt_length: 3}}

    assert is_integer(time)

    {completed, []} =
      Machine.update(
        running,
        {:llm_result, "one", {:ok, %{text: "#### 4", usage: %{total_tokens: 15}}}}
      )

    assert_receive {:linear_telemetry, [:jido, :ai, :cot, :complete], %{duration: duration},
                    %{termination_reason: :success, steps_count: 0, usage: %{total_tokens: 15}}}

    assert duration >= 0 and completed.result == "4"
  end
end
