defmodule Jido.AI.InitialStateTest do
  use Jido.AI.Test.ReasoningCase, async: false
  alias Jido.AI.{Agent, Context}

  defp source do
    definition(:react, tools: [], model: MockLLM.model(), system_prompt: "Configured")
  end

  defp context, do: Context.new(system_prompt: "Saved") |> Context.append_user("Previous")

  test "import supplies a required history field and retains required domain data" do
    source = source()
    fields = source.schema.fields |> Keyword.put(:messages, Zoi.list(Zoi.map())) |> Keyword.put(:count, Zoi.integer())
    source = %{source | schema: %{source.schema | fields: fields}}
    assert {:ok, agent} = Agent.from_initial_state(source, %{context: context(), count: 7}, id: "restored")
    assert agent.id == "restored" and agent.state.count == 7
    assert [%{role: :user, content: "Previous"}] = agent.state.messages
    assert source.state == nil
    assert {:error, _} = Agent.from_initial_state(source, %{context: context(), count: "invalid"})
  end

  test "missing Context uses core domain defaults and an empty prompt remains explicit" do
    source = source()
    assert {:ok, agent} = Agent.from_initial_state(source, %{})
    assert agent.state.messages == []
    assert Jido.AI.get_strategy_context(agent).system_prompt == "Configured"
    assert {:ok, empty} = Agent.from_initial_state(source, %{context: %{context() | system_prompt: ""}})
    assert Jido.AI.get_strategy_context(empty).system_prompt == ""
  end

  test "import rejects old runtime state, Plugin state, unknown fields and duplicate field aliases" do
    for state <- [
          %{__strategy__: %{}},
          %{requests: %{}},
          %{jido_ai_config: %{}},
          %{unknown: 1},
          %{:context => context(), "context" => context()}
        ] do
      assert {:error, _} = Agent.from_initial_state(source(), state)
    end
  end

  test "import rejects ambiguous history and a profile without history" do
    assert {:error, _} = Agent.from_initial_state(source(), %{context: context(), messages: []})
    source = definition(:tree_of_thoughts, tools: [], model: MockLLM.model())
    assert {:error, _} = Agent.from_initial_state(source, %{context: context()})
  end

  test "import rejects invalid options, unknown profiles and an existing instance" do
    for opts <- [[profile: :absent], [id: "a", id: "b"], [unknown: true], %{}] do
      assert {:error, _} = Agent.from_initial_state(source(), %{context: context()}, opts)
    end

    assert {:error, _} = Agent.from_initial_state(Jido.Agent.instantiate!(source()), %{context: context()})
    assert {:error, _} = Agent.from_initial_state(:not_an_agent, %{})
  end

  test "malformed and process-local Context data cannot enter stored state" do
    for context <- [
          nil,
          %{context() | id: nil},
          %{context() | system_prompt: false},
          %{context() | entries: [42]},
          Context.append_user(Context.new(), "live", refs: %{pid: self()})
        ] do
      assert {:error, _} = Agent.from_initial_state(source(), %{context: context})
    end
  end

  test "import rejects an open, orphaned, duplicate or interrupted tool exchange" do
    call = %{id: "one", name: "echo", arguments: %{value: 5}}
    open = Context.new() |> Context.append_assistant(nil, [call])
    complete = Context.append_tool_result(open, "one", "echo", "5")

    for context <- [
          open,
          Context.new() |> Context.append_tool_result("one", "echo", "5"),
          Context.append_tool_result(complete, "one", "echo", "5"),
          Context.append_user(open, "Interrupted")
        ] do
      assert {:error, _} = Agent.from_initial_state(source(), %{context: context})
    end

    assert {:ok, agent} = Agent.from_initial_state(source(), %{context: complete})
    assert length(agent.state.messages) == 2
  end

  test "decoded Context maps retain chronological data and reject unknown format fields" do
    input = %{
      "id" => "saved",
      "system_prompt" => "Imported",
      "entries" => [
        %{"role" => "assistant", "content" => "Old answer", "refs" => %{"case" => "one"}},
        %{"role" => "user", "content" => "Old question"}
      ]
    }

    assert {:ok, agent} = Agent.from_initial_state(source(), %{"context" => input})
    assert Enum.map(agent.state.messages, & &1.content) == ["Old question", "Old answer"]
    assert List.last(agent.state.messages).refs == %{"case" => "one"}
    assert Jido.AI.get_strategy_context(agent).system_prompt == "Imported"
    assert {:error, _} = Agent.from_initial_state(source(), %{context: Map.put(input, "version", 999)})
    assert {:error, _} = Agent.from_initial_state(source(), %{context: Map.put(input, :id, "conflicting")})
  end

  test "the final state size limit includes the imported prompt" do
    source = %{source() | max_state_size: 8_000}
    assert {:ok, _} = Agent.from_initial_state(source, %{context: context()})
    large = %{context() | system_prompt: String.duplicate("x", 9_000)}
    assert {:error, _} = Agent.from_initial_state(source, %{context: large})
  end
end
