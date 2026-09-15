defmodule Jido.AI.Session.InspectionTest do
  use Jido.AI.Test.ReasoningCase, async: false

  alias Jido.AI.{Agent, Authoring, Context, History, Profile}
  alias ReqLLM.Message.ContentPart

  defp profile(id, history, attrs \\ %{}) do
    Profile.new!(
      Map.merge(
        %{
          id: id,
          model: MockLLM.model(),
          instructions: "#{id} prompt",
          requests: %{mode: :session},
          memory: %{history: history},
          result: %{into: id}
        },
        attrs
      )
    )
  end

  defp source(profiles) do
    assert {:ok, source} =
             Authoring.lower(
               %{
                 name: "session_inspection",
                 schema:
                   Zoi.object(%{
                     assistant: Zoi.any() |> Zoi.default(nil),
                     primary: Zoi.any() |> Zoi.default(nil),
                     review: Zoi.any() |> Zoi.default(nil),
                     messages: Jido.AI.Conversation.schema(),
                     review_messages: Jido.AI.Conversation.schema()
                   }),
                 routes: Enum.map(profiles, &{"#{&1.id}.ask", Authoring.ai(&1.id)})
               },
               profiles
             )

    source
  end

  defp ask(server, mock, profile, query) do
    request(server, mock, :react, query, signal_type: "#{profile}.ask")
  end

  for prompt <- [nil, "", "Saved prompt"] do
    test "idle history preserves the #{inspect(prompt)} prompt before the first request", %{jido: jido} do
      profile = profile(:review, :review_messages, %{instructions: unquote(prompt)})
      source = source([profile])
      assert source.state == nil
      assert Agent.profile(source, :review) == profile
      assert {:error, _} = History.read(source.state, profile)
      server = start_agent(jido, Jido.Agent.instantiate!(source))
      assert {:ok, view} = Session.snapshot(server)
      assert view.request == nil and view.live == nil
      assert view.details.phase == :idle
      assert view.details.config.system_prompt == unquote(prompt)
      expected = if is_nil(unquote(prompt)), do: [], else: [%{role: :system, content: unquote(prompt)}]
      assert view.details.conversation == expected
      assert view.details.active_context_ref == "default"
      assert view.details.pending_context_op == nil
      assert view.details.trace == %{events: [], truncated?: false, seq: 0, scope: :observed_prefix}
      assert view.details.trace_summary == %{}
      assert {:ok, []} = History.read(view.agent.state, profile)
      assert view.agent.state.requests == %{}
      assert {:error, :request_not_found} = Session.snapshot(server, request_id: "absent")
    end
  end

  test "a profile without history keeps configuration and has no conversation or context reference", %{jido: jido} do
    profile = profile(:assistant, nil)
    server = start_agent(jido, Jido.Agent.instantiate!(source([profile])))
    assert {:ok, view} = Session.snapshot(server)
    assert view.details.config.system_prompt == "assistant prompt"
    assert view.details.conversation == []
    assert view.details.active_context_ref == nil
    assert view.details.phase == :idle
  end

  test "an Agent without AI profiles has an empty idle snapshot", %{jido: jido} do
    source = Jido.Agent.new!(%{name: "plain_snapshot", schema: Zoi.object(%{})})
    assert Agent.profiles(source) == %{}
    server = start_agent(jido, Jido.Agent.instantiate!(source))
    assert {:ok, view} = Session.snapshot(server)
    assert view.details.config == %{} and view.details.conversation == []
    assert view.details.active_context_ref == nil
    assert view.details.phase == :idle and view.request == nil and view.live == nil
  end

  test "snapshot retains method options and selected model generation fields", %{jido: jido} do
    profile =
      profile(:assistant, nil, %{
        models: %{
          unused: "openai:gpt-4.1",
          answer: %{model: MockLLM.model(), generation: [temperature: 0.2, max_tokens: 40]}
        },
        reasoning: %{method: :tree_of_thoughts, model: :answer, options: %{max_depth: 3}},
        controls: %{max_iterations: 7, max_tool_calls: 9},
        tool_context: %{tenant: "one"},
        requests: %{mode: :session, on_busy: :reject, streaming: true}
      })

    server = start_agent(jido, Jido.Agent.instantiate!(source([profile])))
    assert {:ok, view} = Session.snapshot(server)

    assert view.details.config ==
             Map.merge(profile.reasoning.options, %{
               model: MockLLM.model(),
               temperature: 0.2,
               max_tokens: 40,
               system_prompt: "assistant prompt",
               base_tool_context: %{tenant: "one"},
               tools: [],
               actions_by_name: %{},
               reqllm_tools: [],
               max_iterations: 7,
               max_tool_calls: 9,
               request_policy: :reject,
               streaming: true
             })

    assert view.details.config.max_depth == 3
    assert view.details.conversation == []
  end

  test "an idle Agent selects assistant from multiple profiles", %{jido: jido} do
    profiles = [profile(:review, :review_messages), profile(:assistant, :messages)]
    server = start_agent(jido, Jido.Agent.instantiate!(source(profiles)))
    assert {:ok, view} = Session.snapshot(server)
    assert view.details.config.system_prompt == "assistant prompt"
    assert view.details.conversation == [%{role: :system, content: "assistant prompt"}]
    assert view.details.active_context_ref == "default"
  end

  test "requests select their own profile and committed history on an otherwise ambiguous Agent", %{jido: jido} do
    primary = profile(:primary, :messages)
    review = profile(:review, :review_messages)
    source = source([primary, review])
    assert Map.keys(Agent.profiles(source)) |> Enum.sort() == [:primary, :review]
    server = start_agent(jido, Jido.Agent.instantiate!(source))
    assert {:ok, idle} = Session.snapshot(server)
    assert idle.details.config == %{} and idle.details.conversation == []
    assert idle.details.active_context_ref == nil
    mock = mock([%{reply: {:text, "Reviewed"}}, %{reply: {:wait, :primary, {:text, "Primary answer"}}}])
    assert {:ok, first} = ask(server, mock, :review, "Review query")
    assert {:ok, "Reviewed"} = Request.await(first)
    assert {:ok, next} = ask(server, mock, :primary, "Primary query")
    assert_receive {:mock_llm_waiting, ^mock, :primary, _}, 2_000
    assert {:ok, active} = Session.snapshot(server)
    assert active.request.id == next.id and active.request.profile_id == :primary
    assert active.details.config.system_prompt == "primary prompt"

    assert Enum.map(active.details.conversation, &Jido.AI.Query.summarize(&1.content)) == [
             "primary prompt",
             "Primary query"
           ]

    assert {:ok, retained} = Session.snapshot(server, request_id: first.id)
    assert retained.request.profile_id == :review and retained.live == nil
    assert retained.details.phase == :request_completed
    assert retained.details.config.system_prompt == "review prompt"

    assert Enum.map(retained.details.conversation, &Jido.AI.Query.summarize(&1.content)) == [
             "review prompt",
             "Review query",
             "Reviewed"
           ]

    assert {:ok, [query, answer]} = History.read(retained.agent.state, review)
    assert query.refs.request_id == first.id and answer.refs.request_id == first.id
    assert List.last(retained.details.conversation).refs == answer.refs
    assert :ok = MockLLM.release(mock, :primary)
    assert {:ok, "Primary answer"} = Request.await(next)
    assert {:ok, done} = Session.snapshot(server)
    assert done.live == nil and done.details.active_request_id == nil

    assert Enum.map(done.details.conversation, &Jido.AI.Query.summarize(&1.content)) == [
             "primary prompt",
             "Primary query",
             "Primary answer"
           ]

    assert_script_done(mock)
  end

  test "snapshot reads current overrides while active work keeps its admitted prompt", %{jido: jido} do
    profile = profile(:assistant, :messages)
    source = source([profile])
    server = start_agent(jido, Jido.Agent.instantiate!(source))
    mock = mock([%{reply: {:wait, :answer, {:text, "First answer"}}}, %{reply: {:text, "Next answer"}}])
    assert {:ok, first} = ask(server, mock, :assistant, "First query")
    assert_receive {:mock_llm_waiting, ^mock, :answer, _}, 2_000
    assert {:ok, _} = Jido.AI.set_system_prompt(server, "Changed prompt")
    assert {:ok, _} = Jido.AI.set_tool_context(server, %{tenant: "two"})
    assert {:ok, active} = Session.snapshot(server)
    assert active.details.config.system_prompt == "Changed prompt"
    assert active.details.config.base_tool_context == %{tenant: "two"}

    assert Enum.map(active.details.conversation, &Jido.AI.Query.summarize(&1.content)) == [
             "Changed prompt",
             "First query"
           ]

    assert {:ok, current} = Configuration.profile(active.agent)
    assert current.instructions == "Changed prompt" and current.tool_context == %{tenant: "two"}
    assert Agent.profile(active.agent, :assistant) == profile
    assert :ok = MockLLM.release(mock, :answer)
    assert {:ok, "First answer"} = Request.await(first)
    assert {:ok, next} = ask(server, mock, :assistant, "Next query")
    assert {:ok, "Next answer"} = Request.await(next)
    [first_wire, next_wire] = MockLLM.report(mock).requests
    assert hd(first_wire.body["messages"])["content"] == "assistant prompt"
    assert hd(next_wire.body["messages"])["content"] == "Changed prompt"
    assert {:ok, retained} = Session.snapshot(server, request_id: first.id)
    assert retained.details.config.system_prompt == "Changed prompt"
    assert List.last(retained.details.conversation).content == "Next answer"
    assert_script_done(mock)
  end

  test "snapshot preserves imported content parts, tool messages, refs and context lane", %{jido: jido} do
    refs = %{case_id: "saved"}
    parts = [ContentPart.text("Question"), ContentPart.image(<<1, 2, 3>>, "image/png")]

    context =
      Context.new(system_prompt: "Saved prompt")
      |> Context.append_user(parts, refs: refs)
      |> Context.append_assistant(nil, [%{id: "tool", name: "echo", arguments: %{value: 5}}], refs: refs)
      |> Context.append_tool_result("tool", "echo", "5", refs: refs)
      |> Context.append_assistant("Answer", nil, refs: refs)

    source = source([profile(:assistant, :messages)])
    assert {:ok, agent} = Agent.from_initial_state(source, %{context: context})
    server = start_agent(jido, agent)
    assert {:ok, view} = Session.snapshot(server)
    assert [system, user, call, tool, answer] = view.details.conversation
    assert system == %{role: :system, content: "Saved prompt"}
    assert user.role == :user and user.content == parts
    assert Map.take(user.refs, [:case_id]) == refs
    assert hd(call.tool_calls).id == tool.tool_call_id
    assert tool.name == "echo" and Jido.AI.Query.summarize(tool.content) == "5"
    assert answer.role == :assistant and Jido.AI.Query.summarize(answer.content) == "Answer"
    assert view.details.active_context_ref == "default"
    assert view.request == nil
    assert {:ok, _} = Session.modify_context(server, %{type: :switch}, context_ref: "fresh", op_id: "fresh")
    assert {:ok, fresh} = Session.snapshot(server)
    assert fresh.details.active_context_ref == "fresh"
    assert fresh.details.conversation == [%{role: :system, content: "Saved prompt"}]
    assert {:ok, _} = Session.modify_context(server, %{type: :switch}, context_ref: "default", op_id: "return")
    assert {:ok, restored} = Session.snapshot(server)
    assert restored.details.active_context_ref == "default"
    assert restored.details.conversation == view.details.conversation
  end
end
