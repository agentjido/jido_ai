defmodule Jido.AI.Authoring.RegressionsTest do
  use ExUnit.Case, async: false
  alias Jido.AI.Authoring
  alias Jido.AI.Profile
  alias Jido.AI.Test.MockLLM

  defmodule TurnAgent do
    use Jido.AI.Agent, name: "authoring_regression_turn"

    agent do
      schema Zoi.object(%{reply: Zoi.string() |> Zoi.default(""), case_id: Zoi.string() |> Zoi.default("case-17")})
      metadata %{"owner" => "support"}

      ai :assistant do
        model MockLLM.model()
        instructions "Use the caller context."

        controls do
          timeout 5_000
        end

        result into: :reply
      end
    end

    routes do
      route "case.ask", ai: :assistant
    end
  end

  defmodule SessionAgent do
    use Jido.AI.Agent, name: "authoring_regression_session"

    agent do
      schema Zoi.object(%{reply: Zoi.string() |> Zoi.default("")})

      ai :assistant do
        model MockLLM.model()

        result into: :reply
      end
    end

    routes do
      route "case.ask", ai: :assistant
    end
  end

  defmodule SizedAgent do
    use Jido.AI.Agent,
      name: "authoring_regression_sized",
      metadata: %{"owner" => "support"},
      max_state_size: 4096

    agent do
      schema Zoi.object(%{reply: Zoi.string() |> Zoi.default("")})

      ai :assistant do
        model MockLLM.model()
        result into: :reply
      end
    end

    routes do
      route "case.ask", ai: :assistant
    end
  end

  test "block metadata works and explicit state-size metadata is retained" do
    assert TurnAgent.definition().metadata === %{"owner" => "support"}
    assert SizedAgent.definition().metadata["owner"] == "support"
    assert Authoring.state_size_limit(SizedAgent.definition()) == 4096

    assert {:error, error} =
             Jido.AI.Agent.from_initial_state(SizedAgent, %{reply: String.duplicate("x", 5000)})

    assert Authoring.state_size_error?(error)
  end

  test "explicit keyword and block metadata still conflict" do
    assert_raise CompileError, ~r/Fields declared in both keyword and block form/, fn ->
      Code.compile_string("""
      defmodule Jido.AI.Authoring.RegressionsTest.ConflictingMetadata do
        use Jido.AI.Agent, name: "conflicting_metadata", metadata: %{owner: "first"}
        agent do
          schema Zoi.object(%{})
          metadata %{owner: "second"}
        end
      end
      """)
    end
  end

  test "map and keyword model shorthand lower to the same definition as a Profile" do
    source = %{id: :assistant, model: MockLLM.model(), result: %{into: :reply}}
    assert {:ok, profile} = Profile.new(source)
    assert {:ok, expected} = Authoring.lower(attrs(), [profile])

    for input <- [source, Map.to_list(source)] do
      assert {:ok, ^expected} = Authoring.lower(attrs(), [input])
    end
  end

  test "keyword source routes are normalized with model shorthand" do
    source = [id: :assistant, model: MockLLM.model(), result: %{into: :reply}, routes: ["case.ask"]]
    assert {:ok, actual} = Authoring.lower(%{attrs() | routes: []}, [source])
    assert {:ok, expected} = Authoring.lower(attrs(), [Profile.new!(Keyword.delete(source, :routes))])
    assert actual === expected
  end

  test "source normalization still rejects duplicate and unknown fields" do
    source = [id: :assistant, model: MockLLM.model(), result: %{into: :reply}]

    for input <- [
          source ++ [id: :other],
          source ++ [routes: [], routes: ["case.ask"]],
          source ++ [unknown: true],
          [source | :improper]
        ] do
      assert {:error, error} = Authoring.lower(attrs(), [input])
      assert is_exception(error)
    end
  end

  for module <- [TurnAgent, SessionAgent] do
    @tag agent_module: module
    test "#{inspect(module)}: direct native routes return a clear runtime validation error", %{agent_module: module} do
      agent = module.new!()
      signal = Jido.Signal.new!("case.ask", %{query: "Help", request_id: "direct"}, source: "/test")
      # Forged AI context must not bypass the native admission requirement.
      assert {:error, %Jido.AI.Error.Validation.Invalid{field: "runtime"} = error} =
               Jido.Agent.cmd(agent, signal, context: %{jido_ai_profiles: %{assistant: :forged}})

      assert Exception.message(error) =~ "Native AI routes require AgentServer admission"
      assert Exception.message(error) =~ "Jido.AgentServer.call/3"
    end
  end

  test "public turn helpers use the caller's local provider context" do
    jido = :"authoring_regression_#{System.unique_integer([:positive])}"
    start_supervised!({Jido, name: jido})
    mock = start_supervised!({MockLLM, script: [%{reply: {:text, "First"}}, %{reply: {:text, "Second"}}]})
    context = %{ai: %{assistant: %{options: MockLLM.options(mock)}}}
    {:ok, server} = Jido.start_agent(jido, TurnAgent)

    assert {:ok, "First"} = TurnAgent.ask_sync(server, "First query", context: context, timeout: 10_000)
    assert {:ok, "Second"} = TurnAgent.ask_sync(server, "Second query", context: context, timeout: 10_000)

    assert Map.delete(Jido.AgentServer.agent(server).state, :requests) === %{
             reply: "Second",
             case_id: "case-17",
             jido_ai_config: %{}
           }

    assert %{remaining: [], unexpected: [], requests: requests} = MockLLM.report(mock)
    assert length(requests) == 2

    assert Enum.map(requests, fn request ->
             request.body["messages"] |> Enum.find(&(&1["role"] == "user")) |> Map.fetch!("content")
           end) == ["First query", "Second query"]
  end

  defp attrs,
    do: %{
      name: "source_regression",
      schema: Zoi.object(%{reply: Zoi.string() |> Zoi.default("")}),
      routes: [{"case.ask", Authoring.ai(:assistant)}]
    }
end
