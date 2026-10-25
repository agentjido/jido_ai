defmodule Jido.AI.RequestTest do
  use Jido.AI.Test.ReqLLMCase, async: false

  alias Jido.AI.{Event, Request, Result}

  defmodule Echo do
    use Jido.Action,
      name: "request_test_echo",
      description: "Echo one value",
      schema: Zoi.object(%{value: Zoi.string()})

    @impl Jido.Action
    def run(%{value: value}, _context), do: {:ok, %{value: value}}
  end

  defmodule Multiply do
    use Jido.Action,
      name: "request_test_multiply",
      description: "Multiply two values",
      schema: Zoi.object(%{left: Zoi.integer(), right: Zoi.integer()})

    @impl Jido.Action
    def run(%{left: left, right: right}, context) do
      if counter = context[:counter], do: Agent.update(counter, &(&1 + 1))
      {:ok, %{product: left * right}}
    end
  end

  defmodule Ask do
    use Jido.Action,
      name: "request_test_ask",
      description: "Ask one projected question",
      schema: Zoi.object(%{question: Zoi.string()}),
      output_schema: Zoi.object(%{answer: Zoi.string()})

    @impl Jido.Action
    def run(%{question: question}, _context), do: {:ok, %{answer: question}}
  end

  defmodule Agent do
    use Jido.AI.Agent, name: "request_contract_test_agent"

    ai do
      model "openai:gpt-4o-mini"
      instructions "Answer briefly."

      tools do
        action Echo, as: :echo
        action Multiply, as: :multiply
      end

      controls do
        timeout 10_000
        max_iterations 3
        max_model_calls 4
        max_tool_calls 5
      end
    end

    routes do
      signal_source "/test/request"

      route "test.request.ask", Ask, as: :ask do
        state(:unchanged)
        reply("test.request.answered", from: output())
      end
    end
  end

  test "preflight resolves one request without model work" do
    assert {:ok, %Request{} = request} =
             Agent.preflight("Hello",
               request_id: "request-1",
               run_id: "run-1",
               visible_tools: [:echo],
               temperature: 0.0
             )

    assert request.request_id == "request-1"
    assert request.run_id == "run-1"
    assert request.model == "openai:gpt-4o-mini"
    assert request.reasoning == Jido.AI.Flow.ReAct
    assert request.controls.timeout == 10_000
    assert Request.visible_tool_names(request) == ["echo"]
    assert Enum.map(request.tools, & &1.name) == ["echo"]
    assert request.request_options[:temperature] == 0.0
    assert Enum.map(Request.messages(request), & &1.role) == [:system, :user]

    assert {:ok, structured} =
             Agent.preflight("Hello", reply: {Agent, "test.request.ask"})

    assert %ReqLLM.Output{type: :object} = structured.output_descriptor
  end

  test "preflight projects complete Session turns without changing the Session" do
    first = Agent.ask_signal!(%{question: "My name is Ana."})
    assert {:ok, contract} = Jido.AI.Route.resolve({Agent, "test.request.ask"})
    assert {:ok, reply} = Jido.AI.Route.reply(contract, first, %{answer: "Hello Ana."})
    incomplete = Agent.ask_signal!(%{question: "Do not include this."})
    session = Jido.Session.new!()
    {:ok, session} = Jido.Session.append_many(session, [first, reply, incomplete])
    original = session

    assert {:ok, request} =
             Agent.preflight("What is my name?",
               context: session,
               projection: [
                 route: {Agent, "test.request.ask"},
                 input: :question,
                 output: :answer
               ]
             )

    assert Enum.map(Request.messages(request), &message_text/1) == [
             "Answer briefly.",
             "My name is Ana.",
             "Hello Ana.",
             "What is my name?"
           ]

    assert session == original
  end

  test "request tool selection rejects unknown, duplicate, and raw provider tools" do
    assert Agent.preflight("Hello", visible_tools: [:missing]) ==
             {:error, {:unknown_tools, ["missing"]}}

    duplicate = [visible_tools: [:echo, "echo"]]
    assert Agent.preflight("Hello", duplicate) == {:error, {:invalid_options, duplicate}}

    raw = [tools: []]
    assert Agent.preflight("Hello", raw) == {:error, {:invalid_options, raw}}
  end

  test "only selected tools are sent to the model" do
    expect(ReqLLM, :generate_text, fn model, context, options ->
      assert Enum.map(options[:tools], & &1.name) == ["echo"]
      {:ok, text_response(model, context, "Done", id: "request-test-response")}
    end)

    assert {:ok, %Result{output: "Done"} = result} =
             Agent.reason("Use one tool if needed", visible_tools: [:echo])

    assert hd(result.events).data.visible_tools == ["echo"]
  end

  test "a forged call to a hidden tool is rejected before execution" do
    {:ok, counter} = Elixir.Agent.start_link(fn -> 0 end)

    expect(ReqLLM, :generate_text, 2, fn model, context, options ->
      assert Enum.map(options[:tools], & &1.name) == ["echo"]

      case ReqLLM.Context.to_list(context) do
        [_system, _user] ->
          call = ReqLLM.ToolCall.new("hidden-1", "multiply", ~s({"left":2,"right":3}))
          {:ok, tool_response(model, context, [call], id: "hidden-tool-call")}

        [_system, _user, %{role: :assistant}, tool_result] ->
          assert tool_result.role == :tool
          assert tool_result.tool_call_id == "hidden-1"
          assert tool_result.metadata.is_error
          {:ok, text_response(model, context, "The hidden tool was not used.", id: "request-test-response")}
      end
    end)

    assert {:ok, result} =
             Agent.reason("Call multiply",
               visible_tools: [:echo],
               jido_context: %{counter: counter}
             )

    assert result.output == "The hidden tool was not used."
    assert result.usage.tool_calls == 1
    assert Elixir.Agent.get(counter, & &1) == 0
  end

  test "run returns an explicit failed result with one terminal event" do
    expect(ReqLLM, :generate_text, fn _model, _context, _options ->
      {:error, :provider_unavailable}
    end)

    assert {:error, %Result{} = result} =
             Agent.run("Fail", request_id: "failed-request", run_id: "failed-run")

    assert result.status == :failed
    assert result.error == :provider_unavailable
    assert result.output == nil
    assert result.request_id == "failed-request"
    assert result.run_id == "failed-run"
    assert Enum.map(result.events, & &1.type) == [:request_started, :request_failed]
    assert Enum.count(result.events, &Event.terminal?/1) == 1
    assert Result.validate(result) == :ok
  end

  defp message_text(message), do: message.content |> List.first() |> Map.fetch!(:text)
end
