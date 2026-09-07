defmodule JidoAI.Examples.InitialStateTest do
  use JidoAI.Examples.Case
  alias Jido.AI.{Agent, Configuration, Context, Request}
  alias JidoAI.Examples.InitialState
  alias ReqLLM.Message.ContentPart

  defp saved_context(prompt) do
    refs = %{request_id: "old-request", run_id: "old-run", source: "/saved", case_id: "one"}

    Context.new(id: "old-context", system_prompt: prompt)
    |> Context.append_user([ContentPart.text("Previous question"), ContentPart.image(<<1, 2, 3>>, "image/png")],
      refs: refs
    )
    |> Context.append_assistant(nil, [%{id: "saved-tool", name: "import_echo", arguments: %{value: 5}}], refs: refs)
    |> Context.append_tool_result("saved-tool", "import_echo", ~s({"ok":true,"result":{"value":5}}), refs: refs)
    |> Context.append_assistant("Previous answer", nil, refs: refs)
  end

  defp submit(server, context, query, route \\ "ai.react.query") do
    Request.create_and_send(server, query,
      signal_type: route,
      source: "/examples/initial-state",
      model: MockLLM.model(),
      context: context
    )
  end

  for {module, streaming?, native?} <- [
        {InitialState.Buffered, false, true},
        {InitialState.Streamed, true, true},
        {InitialState.PublicBuffered, false, false},
        {InitialState.PublicStreamed, true, false}
      ] do
    test "#{module} imports history before startup and restores later native state without tool replay", %{jido: jido} do
      old = saved_context("Saved prompt")

      state =
        if unquote(native?),
          do: %{context: old, count: 9, thread: %{id: "application-thread", rev: 2}},
          else: %{context: old}

      assert {:ok, agent} = Agent.from_initial_state(unquote(module), state, id: "imported")
      assert Jido.AI.get_strategy_context(agent).entries == old.entries
      assert Jido.AI.get_strategy_context(agent).system_prompt == "Saved prompt"
      assert Jido.AI.get_strategy_context(agent).id == "imported:assistant"
      assert agent.state.requests == %{}
      refute Map.has_key?(agent.state, :context)
      if unquote(native?), do: assert(agent.state.count == 9 and agent.state.thread == state.thread)
      {mock, context} = mock([%{reply: {:text, "Continued"}}, %{reply: {:text, "Again"}}])
      assert MockLLM.report(mock).requests == []
      server = start_agent(jido, agent)
      assert {:ok, first} = submit(server, context, "Continue")
      assert {:ok, "Continued"} = Request.await(first)
      [wire] = MockLLM.report(mock).requests

      assert Enum.map(wire.body["messages"], & &1["role"]) == [
               "system",
               "user",
               "assistant",
               "tool",
               "assistant",
               "user"
             ]

      assert hd(wire.body["messages"])["content"] == "Saved prompt"

      assert Enum.at(wire.body["messages"], 1)["content"] == [
               %{"type" => "text", "text" => "Previous question"},
               %{"type" => "image_url", "image_url" => %{"url" => "data:image/png;base64,AQID"}}
             ]

      assert Enum.at(wire.body["messages"], 2)["tool_calls"] |> hd() |> Map.fetch!("id") == "saved-tool"
      assert Enum.at(wire.body["messages"], 3)["tool_call_id"] == "saved-tool"
      saved = Server.agent(server)
      assert Enum.take(saved.state.messages, 4) == Enum.reverse(old.entries) |> Enum.map(&Map.from_struct/1)
      assert :ok = Jido.Action.validate_static_data(saved.state)
      copy = saved.state |> :erlang.term_to_binary() |> :erlang.binary_to_term([:safe])
      assert :ok = Server.stop(server, :normal)
      restored = start_agent(jido, unquote(module).new!(id: saved.id, state: copy))
      assert {:ok, next} = submit(restored, context, "Continue again")
      assert {:ok, "Again"} = Request.await(next)
      [_, wire] = MockLLM.report(mock).requests
      assert Enum.count(wire.body["messages"], &(&1["role"] == "tool")) == 1
      assert Enum.all?(MockLLM.report(mock).requests, &(&1.body["stream"] == unquote(streaming?)))
      assert length(Server.agent(restored).state.messages) == 8
      refute_receive {:import_tool_ran, _}, 30
      assert_script_done(mock)
    end
  end

  for {prompt, expected} <- [{nil, "Review prompt"}, {"Saved review", "Saved review"}] do
    test "profile selection keeps unrelated history and uses #{inspect(prompt)} prompt", %{jido: jido} do
      old = Context.new(system_prompt: unquote(prompt)) |> Context.append_user("Old review")
      primary = Jido.AI.History.query("Old primary", %{})
      source = InitialState.Profiles.agent()

      assert {:ok, agent} =
               Agent.from_initial_state(source, %{context: old, primary_messages: primary}, profile: :review)

      assert agent.state.primary_messages == primary
      assert Jido.AI.get_strategy_context(agent, :review).entries == old.entries
      assert {:ok, %{instructions: "Primary prompt"}} = Configuration.profile(agent, :primary)
      assert {:ok, %{instructions: unquote(expected)}} = Configuration.profile(agent, :review)
      {mock, context} = mock([%{reply: {:text, "Reviewed"}}, %{reply: {:text, "Primary"}}])

      context =
        Map.put(context, :ai, %{review: %{options: MockLLM.options(mock)}, primary: %{options: MockLLM.options(mock)}})

      server = start_agent(jido, agent)
      assert {:ok, review} = submit(server, context, "Review again", "review.ask")
      assert {:ok, "Reviewed"} = Request.await(review)
      assert {:ok, primary} = submit(server, context, "Primary again", "primary.ask")
      assert {:ok, "Primary"} = Request.await(primary)
      [review, primary] = MockLLM.report(mock).requests
      assert Enum.map(review.body["messages"], & &1["content"]) == [unquote(expected), "Old review", "Review again"]
      assert Enum.map(primary.body["messages"], & &1["content"]) == ["Primary prompt", "Old primary", "Primary again"]
      assert_script_done(mock)
    end
  end

  test "invalid and ambiguous imports leave the source definition unchanged" do
    {mock, _} = mock([])
    source = InitialState.Profiles.agent()
    old = Context.new() |> Context.append_user("Saved")
    assert {:error, _} = Agent.from_initial_state(source, %{context: old})
    assert {:error, _} = Agent.from_initial_state(source, %{context: old}, profile: :absent)
    assert {:error, _} = Agent.from_initial_state(source, %{context: old, review_messages: []}, profile: :review)
    assert {:error, _} = Agent.from_initial_state(source, %{__strategy__: %{context: old}}, profile: :review)
    assert {:error, _} = Agent.from_initial_state(source, %{requests: %{}}, profile: :review)
    assert source == InitialState.Profiles.agent() and source.state == nil
    assert MockLLM.report(mock).requests == []
    assert_script_done(mock)
  end
end
