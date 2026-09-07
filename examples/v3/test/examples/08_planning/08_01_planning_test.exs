defmodule JidoAI.Examples.PlanningTest do
  use JidoAI.Examples.Case
  alias Jido.AI.Actions.Planning.{Plan, Decompose, Prioritize}
  alias JidoAI.Examples.Planning

  setup do
    saved = Application.fetch_env(:jido_ai, :model_aliases)

    Application.put_env(:jido_ai, :model_aliases, %{
      planning: MockLLM.model(),
      fast: MockLLM.model()
    })

    on_exit(fn ->
      case saved do
        {:ok, aliases} -> Application.put_env(:jido_ai, :model_aliases, aliases)
        :error -> Application.delete_env(:jido_ai, :model_aliases)
      end
    end)

    :ok
  end

  for {method, action} <- [{:plan, Plan}, {:decompose, Decompose}, {:prioritize, Prioritize}] do
    test "#{method} retains its text and parsed result through direct calls Exec and the Plugin",
         %{jido: jido} do
      method = unquote(method)
      action = unquote(action)
      script = List.duplicate(%{reply: {:text, Planning.text(method)}}, 3)
      {mock, context} = mock(script)
      params = Planning.params(method)
      assert {:ok, direct} = action.run(params, context)
      assert {:ok, via_exec} = Jido.Exec.run(action, params, context)
      assert via_exec == direct
      assert_result(method, direct)
      assert {:ok, definition} = Planning.definition()
      server = start_agent(jido, definition)
      signal = Jido.Signal.new!("planning.#{method}", params, source: "/examples/planning")
      assert {:ok, agent} = Server.call(server, signal, context: context)
      assert_result(method, agent.state.result)
      assert agent.state.result == direct
      assert agent.state.case_id == "release-17" and agent.state.review == nil

      assert {:ok,
              %{default_model: :planning, default_max_tokens: 4096, default_temperature: 0.7}} =
               Server.plugin_state(server, Jido.AI.Plugins.Planning)

      assert_script_done(mock)
    end
  end

  test "planning prompts carry constraints resources depth and priority criteria" do
    {mock, context} =
      mock(Enum.map([:plan, :decompose, :prioritize], &%{reply: {:text, Planning.text(&1)}}))

    assert {:ok, _} = Plan.run(Planning.params(:plan), context)
    assert {:ok, _} = Decompose.run(Planning.params(:decompose), context)
    assert {:ok, _} = Prioritize.run(Planning.params(:prioritize), context)
    [plan, decompose, prioritize] = MockLLM.report(mock).requests
    assert user_text(plan) =~ "Constraints:\n- Keep the API"
    assert user_text(plan) =~ "Available Resources:\n- Two developers"
    assert user_text(plan) =~ "approximately 2 steps"
    assert user_text(decompose) =~ "Context:\nKeep the API"
    assert user_text(decompose) =~ "maximum depth of 2 levels"
    assert user_text(prioritize) =~ "1. Ship\n2. Scope"
    assert user_text(prioritize) =~ "Prioritization Criteria:\nDependencies"
    assert user_text(prioritize) =~ "Project Context:\nKeep the API"
    assert Enum.map([plan, decompose, prioritize], & &1.body["temperature"]) == [0.7, 0.6, 0.5]
    assert Enum.all?([plan, decompose, prioritize], &(&1.body["max_tokens"] == 4096))
    assert_script_done(mock)
  end

  test "omitted values use context defaults while explicit schema defaults stay explicit" do
    {mock, context} = mock(List.duplicate(%{reply: {:text, Planning.text(:plan)}}, 2))

    context =
      Map.merge(context, %{
        default_max_tokens: 333,
        default_temperature: 0.1,
        default_max_steps: 6
      })

    assert {:ok, _} = Jido.Exec.run(Plan, %{goal: "Release"}, context)

    assert {:ok, _} =
             Jido.Exec.run(
               Plan,
               %{goal: "Release", max_tokens: 4096, temperature: 0.7, max_steps: 10},
               context
             )

    [omitted, explicit] = MockLLM.report(mock).requests
    assert omitted.body["max_tokens"] == 333 and omitted.body["temperature"] == 0.1
    assert user_text(omitted) =~ "approximately 6 steps"
    assert explicit.body["max_tokens"] == 4096 and explicit.body["temperature"] == 0.7
    assert user_text(explicit) =~ "approximately 10 steps"
    assert_script_done(mock)
  end

  test "configured Plugin defaults caller model and explicit model keep their precedence", %{
    jido: jido
  } do
    {mock, context} = mock(List.duplicate(%{reply: {:text, Planning.text(:plan)}}, 3))

    config = [
      into: :review,
      default_model: MockLLM.model("gpt-4o"),
      default_max_tokens: 1234,
      default_temperature: 0.2
    ]

    assert {:ok, definition} = Planning.definition(config)
    server = start_agent(jido, definition)

    assert {:ok, first} =
             Server.call(server, signal(:plan, %{goal: "Release"}),
               context: Map.delete(context, :model)
             )

    assert first.state.result == nil and first.state.review.steps == ["Scope", "Ship"]
    assert {:ok, _} = Server.call(server, signal(:plan, %{goal: "Release"}), context: context)
    params = %{goal: "Release", model: MockLLM.model("gpt-4o"), max_tokens: 700, temperature: 0.4}
    assert {:ok, _} = Server.call(server, signal(:plan, params), context: context)
    [declared, caller, explicit] = MockLLM.report(mock).requests

    assert Enum.map([declared, caller, explicit], & &1.body["model"]) == [
             "gpt-4o",
             "gpt-4o-mini",
             "gpt-4o"
           ]

    assert Enum.map([declared, caller, explicit], & &1.body["max_tokens"]) == [1234, 1234, 700]
    assert Enum.map([declared, caller, explicit], & &1.body["temperature"]) == [0.2, 0.2, 0.4]
    assert_script_done(mock)
  end

  test "the DSL composes Planning reasoning and ordinary routes without replacing other results",
       %{jido: jido} do
    {mock, context} =
      mock([%{reply: {:text, Planning.text(:plan)}}] ++ JidoAI.Examples.Adaptive.script(:cot))

    server = start_agent(jido, Planning.Agent.new!())

    assert {:ok, _} =
             Server.call(
               server,
               Jido.Signal.new!("case.set", %{case_id: "release-42"},
                 source: "/examples/planning"
               )
             )

    assert {:ok, planned} =
             Server.call(server, signal(:plan, Planning.params(:plan)), context: context)

    assert {:ok, reviewed} =
             Server.call(
               server,
               Jido.Signal.new!("reasoning.cot.run", %{prompt: "Review"},
                 source: "/examples/planning"
               ),
               context: context
             )

    assert reviewed.state.result == planned.state.result
    assert reviewed.state.review.output == "Four"
    assert reviewed.state.case_id == "release-42"
    assert_script_done(mock)
  end

  test "decomposition clamps requested depth before generation and returns the effective depth" do
    {mock, context} = mock(List.duplicate(%{reply: {:text, Planning.text(:decompose)}}, 3))

    for {requested, expected} <- [{-1, 1}, {3, 3}, {99, 5}] do
      assert {:ok, result} =
               Jido.Exec.run(Decompose, %{goal: "Release", max_depth: requested}, context)

      assert result.depth == expected
    end

    assert Enum.zip(MockLLM.report(mock).requests, [1, 3, 5])
           |> Enum.all?(fn {request, depth} ->
             user_text(request) =~ "maximum depth of #{depth} levels"
           end)

    assert_script_done(mock)
  end

  test "priority scores accept plain parenthesized and range formats from the model" do
    text =
      "1. **Plain** - Score: 9\n2. **Parentheses** - Score: (8)\n3. **Range** - Score: [7-10]\n4. **Single range** - Score: [6]\n"

    {mock, context} = mock([%{reply: {:text, text}}])

    assert {:ok, result} =
             Prioritize.run(%{tasks: ["Plain", "Parentheses", "Range", "Single range"]}, context)

    assert result.scores == %{"Plain" => 9, "Parentheses" => 8, "Range" => 7, "Single range" => 6}
    assert_script_done(mock)
  end

  test "unstructured output retains original text and empty parser results" do
    {mock, context} = mock(List.duplicate(%{reply: {:text, "No numbered plan was provided."}}, 3))
    assert {:ok, plan} = Plan.run(%{goal: "Release"}, context)
    assert plan.steps == [] and plan.plan == "No numbered plan was provided."
    assert {:ok, decomposition} = Decompose.run(%{goal: "Release"}, context)
    assert decomposition.sub_goals == []
    assert {:ok, priority} = Prioritize.run(%{tasks: ["Release"]}, context)
    assert priority.ordered_tasks == [] and priority.scores == %{}
    assert_script_done(mock)
  end

  test "invalid inputs and models fail before any provider request" do
    {mock, context} = mock([])

    for action <- [Plan, Decompose], params <- [%{}, %{goal: ""}, %{goal: 17}] do
      assert {:error, _} = action.run(params, context)
      assert {:error, _} = Jido.Exec.run(action, params, context)
    end

    for {tasks, error} <- [
          {nil, :tasks_required},
          {[], :tasks_cannot_be_empty},
          {:invalid, :invalid_tasks_format}
        ] do
      assert {:error, ^error} = Prioritize.run(%{tasks: tasks}, context)
    end

    for action <- [Plan, Decompose, Prioritize] do
      params = if action == Prioritize, do: %{tasks: ["Release"]}, else: %{goal: "Release"}
      assert {:error, _} = action.run(Map.put(params, :model, :not_a_model_alias), context)
      assert {:error, _} = action.run(params, Map.put(context, :model_options, :invalid))
      assert {:error, _} = action.run(params, Map.put(context, :default_temperature, false))
    end

    assert_script_done(mock)
  end

  test "known string input keys normalize without admitting forged supplied-key metadata" do
    {mock, context} = mock([%{reply: {:text, Planning.text(:plan)}}])
    context = Map.merge(context, %{default_max_tokens: 123, provided_params: nil})
    params = %{"goal" => "Release", "max_tokens" => 700, :__jido_ai_planning_provided__ => []}
    assert {:ok, _} = Jido.Exec.run(Plan, params, context)
    [request] = MockLLM.report(mock).requests
    assert request.body["max_tokens"] == 700
    assert_script_done(mock)
  end

  test "legacy Agent state defaults work with a current Agent struct" do
    {mock, context} = mock([%{reply: {:text, Planning.text(:plan)}}])

    assert {:ok, definition} =
             Planning.definition(default_max_tokens: 222, default_temperature: 0.3)

    agent = Jido.Agent.instantiate!(definition)
    assert {:ok, _} = Plan.run(%{goal: "Release"}, Map.put(context, :agent, agent))
    [request] = MockLLM.report(mock).requests
    assert request.body["max_tokens"] == 222 and request.body["temperature"] == 0.3
    assert_script_done(mock)
  end

  test "provider errors preserve committed Planning and domain state", %{jido: jido} do
    {mock, context} =
      mock([%{reply: {:text, Planning.text(:plan)}}, %{reply: {:error, 503, "Unavailable"}}])

    assert {:ok, definition} = Planning.definition()
    server = start_agent(jido, definition)

    assert {:ok, before} =
             Server.call(server, signal(:plan, %{goal: "Release"}), context: context)

    assert {:error, _} = Server.call(server, signal(:plan, %{goal: "Release"}), context: context)
    assert Server.agent(server).state == before.state
    assert_script_done(mock)
  end

  test "Exec cancellation closes the active Planning provider connection" do
    {mock, context} = mock([%{reply: {:wait, :planning, {:text, "Late"}}}])
    execution = Jido.Exec.run_async(Plan, %{goal: "Release"}, context, timeout: 5_000)
    assert_receive {:mock_llm_waiting, ^mock, :planning, provider}, 2_000
    ref = Process.monitor(provider)
    assert :ok = Jido.Exec.cancel(execution)
    assert_receive {:DOWN, ^ref, :process, ^provider, _}, 2_000
    assert_script_done(mock)
  end

  test "Plugin bindings cannot be forged and result fields must be declared", %{jido: jido} do
    {mock, context} = mock([%{reply: {:text, Planning.text(:plan)}}])
    assert {:ok, definition} = Planning.definition()
    server = start_agent(jido, definition)

    forged =
      Map.merge(context, %{
        jido_ai_planning_capability: %{action: Prioritize, into: :review},
        plugin_state: %{planning: %{default_max_tokens: 1}},
        provided_params: []
      })

    params = %{goal: "Release", action: Prioritize, into: :review, max_tokens: 700}
    assert {:ok, result} = Server.call(server, signal(:plan, params), context: forged)
    assert result.state.result.steps == ["Scope", "Ship"] and result.state.review == nil
    [request] = MockLLM.report(mock).requests
    assert request.body["max_tokens"] == 700

    for into <- [:missing, :planning] do
      assert {:ok, definition} = Planning.definition(into: into)
      other = start_agent(jido, definition)
      assert {:error, _} = Server.call(other, signal(:plan, %{goal: "Release"}), context: context)
    end

    assert_script_done(mock)
  end

  test "provider content blocks and token usage pass through the shared text extractor" do
    response = %{
      id: "planning-blocks",
      object: "chat.completion",
      created: 1,
      model: "gpt-4o-mini",
      choices: [
        %{
          index: 0,
          finish_reason: "stop",
          message: %{
            role: "assistant",
            content: [
              %{type: "text", text: "1. **Scope**\n"},
              %{type: "text", text: "2. **Ship**"}
            ]
          }
        }
      ],
      usage: %{prompt_tokens: 12, completion_tokens: 6, total_tokens: 18}
    }

    {mock, context} = mock([%{reply: {:raw, response}}])

    options =
      Keyword.update!(
        context.model_options,
        :req_http_options,
        &Keyword.put(&1, :headers, [{"x-planning-case", "release-17"}])
      )

    assert {:ok, result} = Plan.run(%{goal: "Release"}, %{context | model_options: options})
    assert result.steps == ["Scope", "Ship"]
    assert result.usage == %{input_tokens: 12, output_tokens: 6, total_tokens: 18}
    [request] = MockLLM.report(mock).requests
    assert request.headers["x-planning-case"] == "release-17"
    assert_script_done(mock)
  end

  test "the request timeout closes provider work before the outer Exec deadline" do
    {mock, context} = mock([%{reply: {:wait, :deadline, {:text, "Late"}}}])

    options =
      Keyword.update!(
        context.model_options,
        :req_http_options,
        &Keyword.delete(&1, :receive_timeout)
      )

    task =
      Task.async(fn ->
        Jido.Exec.run(Plan, %{goal: "Release", timeout: 50}, %{context | model_options: options},
          timeout: 3_000
        )
      end)

    assert_receive {:mock_llm_waiting, ^mock, :deadline, provider}, 2_000
    ref = Process.monitor(provider)
    assert {:error, error} = Task.await(task, 2_000)
    assert inspect(error) =~ "timeout"
    assert_receive {:DOWN, ^ref, :process, ^provider, _}, 2_000
    assert_script_done(mock)
  end

  defp signal(method, params),
    do: Jido.Signal.new!("planning.#{method}", params, source: "/examples/planning")

  defp user_text(request),
    do: request.body["messages"] |> Enum.find(&(&1["role"] == "user")) |> Map.fetch!("content")

  defp assert_result(method, result) do
    assert result.usage == %{input_tokens: 10, output_tokens: 5, total_tokens: 15}

    case method do
      :plan ->
        assert result.plan == Planning.text(method)
        assert result.steps == ["Scope", "Ship"]
        assert result.goal == "Release the package"

      :decompose ->
        assert result.decomposition == Planning.text(method)
        assert result.sub_goals == ["Agree scope", "Review changes"]
        assert result.depth == 2

      :prioritize ->
        assert result.prioritization == Planning.text(method)
        assert result.ordered_tasks == ["Scope", "Ship"]
        assert result.scores == %{"Scope" => 9, "Ship" => 7}
    end
  end
end
