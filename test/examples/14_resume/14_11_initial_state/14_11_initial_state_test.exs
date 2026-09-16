defmodule JidoAI.Examples.InitialStateTest do
  use JidoAI.Examples.Case
  alias Jido.AI.{Agent, Configuration, Request}
  alias Jido.AI.Thread.Projection
  alias JidoAI.Examples.InitialState

  setup do
    JidoAI.Examples.ToolEvents.attach_action(InitialState.Echo)
  end

  alias ReqLLM.Message.ContentPart

  defp saved_context(prompt) do
    refs = %{request_id: "old-request", run_id: "old-run", source: "/saved", case_id: "one"}

    thread = Jido.Thread.new(metadata: %{system_prompt: prompt})
    call = ReqLLM.ToolCall.new("saved-tool", "import_echo", ~s({"value":5}))

    {:ok, session} =
      Projection.append(
        Jido.Session.new(id: "old-session", thread: thread),
        [
          ReqLLM.Context.user([ContentPart.text("Previous question"), ContentPart.image(<<1, 2, 3>>, "image/png")]),
          %ReqLLM.Message{role: :assistant, content: [], tool_calls: [call]},
          ReqLLM.Context.tool_result("saved-tool", "import_echo", ~s({"ok":true,"result":{"value":5}})),
          ReqLLM.Context.assistant("Previous answer")
        ],
        refs
      )

    session
  end

  defp submit(server, context, query, route \\ "ai.react.query") do
    Request.create_and_send(server, query,
      signal_type: route,
      source: "/examples/initial-state",
      model: MockLLM.model(),
      context: context
    )
  end

  for {module, streaming?} <- [
        {InitialState.Buffered, false},
        {InitialState.Streamed, true}
      ] do
    test "#{module} imports history before startup and restores later native state without tool replay", %{jido: jido} do
      old = saved_context("Saved prompt")

      state = %{messages: old, count: 9, thread: %{id: "application-thread", rev: 2}}

      assert {:ok, agent} = Agent.from_initial_state(unquote(module), state, id: "imported")
      assert {:ok, profile} = Configuration.profile(agent, :assistant)
      assert {:ok, messages} = Jido.AI.Orchestration.Transcript.read(agent.state, profile)
      assert Enum.map(messages, & &1.role) == [:user, :assistant, :tool, :assistant]
      imported = agent.state.messages.thread.entries
      assert agent.state.messages.id == old.id

      for entry <- imported do
        assert entry.refs.request_id == "old-request"
        assert entry.refs.run_id == "old-run"
        assert entry.refs.case_id == "one"
      end

      assert profile.instructions == "Saved prompt"
      assert agent.id == "imported" and profile.id == :assistant
      assert agent.state.requests == %{}
      refute Map.has_key?(agent.state, :context)
      assert agent.state.count == 9 and agent.state.thread == state.thread
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
      assert Enum.take(saved.state.messages.thread.entries, 4) == imported
      assert :ok = Jido.Action.validate_static_data(saved.state)
      copy = saved.state |> :erlang.term_to_binary() |> :erlang.binary_to_term([:safe])
      assert :ok = Server.stop(server, :normal)
      restored = start_agent(jido, unquote(module).new!(id: saved.id, state: copy))
      assert {:ok, next} = submit(restored, context, "Continue again")
      assert {:ok, "Again"} = Request.await(next)
      [_, wire] = MockLLM.report(mock).requests
      assert Enum.count(wire.body["messages"], &(&1["role"] == "tool")) == 1
      assert Enum.all?(MockLLM.report(mock).requests, &(&1.body["stream"] == unquote(streaming?)))
      assert Jido.Thread.entry_count(Server.agent(restored).state.messages.thread) == 10
      refute_received {:example_action_started, "import_echo"}
      assert_script_done(mock)
    end
  end

  for {prompt, expected} <- [{nil, "Review prompt"}, {"Saved review", "Saved review"}] do
    test "profile selection keeps unrelated history and uses #{inspect(prompt)} prompt", %{jido: jido} do
      thread = Jido.Thread.new(metadata: %{system_prompt: unquote(prompt)})
      {:ok, old} = Projection.append(Jido.Session.new(thread: thread), [ReqLLM.Context.user("Old review")])
      {:ok, primary} = Jido.AI.Thread.Projection.append(Jido.Session.new(), [ReqLLM.Context.user("Old primary")])
      source = InitialState.Profiles.definition()

      assert {:ok, agent} =
               Agent.from_initial_state(source, %{review_messages: old, primary_messages: primary}, profile: :review)

      assert agent.state.primary_messages == primary
      assert {:ok, review_profile} = Configuration.profile(agent, :review)
      assert {:ok, messages} = Jido.AI.Orchestration.Transcript.read(agent.state, review_profile)
      assert [%{role: :user, content: content}] = messages
      assert Jido.AI.Query.summarize(content) == "Old review"
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
    source = InitialState.Profiles.definition()
    old = saved_context(nil)
    assert {:error, _} = Agent.from_initial_state(source, %{context: old})
    assert {:error, _} = Agent.from_initial_state(source, %{context: old}, profile: :absent)
    assert {:error, _} = Agent.from_initial_state(source, %{context: old, review_messages: []}, profile: :review)
    assert {:error, _} = Agent.from_initial_state(source, %{__strategy__: %{context: old}}, profile: :review)
    assert {:error, _} = Agent.from_initial_state(source, %{requests: %{}}, profile: :review)
    assert source == InitialState.Profiles.definition() and source.state == nil
    assert MockLLM.report(mock).requests == []
    assert_script_done(mock)
  end
end
