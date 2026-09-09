defmodule JidoAI.Examples.PromptPolicyTest do
  use JidoAI.Examples.Case
  alias Jido.AI.{Authoring, Request}
  alias JidoAI.Examples.{Adaptive, PromptPolicy}

  @react_prompt """
  You are a helpful AI assistant using the ReAct (Reason-Act) pattern.
  When you need to perform an action, use the available tools.
  When you have enough information to answer, provide your final answer directly.
  Think step by step and explain your reasoning.
  """

  setup do
    old = Application.fetch_env(:jido_ai, :model_aliases)
    Application.put_env(:jido_ai, :model_aliases, %{example: MockLLM.model()})

    on_exit(fn ->
      case old do
        {:ok, value} -> Application.put_env(:jido_ai, :model_aliases, value)
        :error -> Application.delete_env(:jido_ai, :model_aliases)
      end
    end)
  end

  defp request(server, context, query \\ "Use the tool") do
    Request.create_and_send(server, query,
      signal_type: "ai.adaptive.query",
      source: "/examples/prompts",
      context: context
    )
  end

  defp system(wire),
    do:
      wire.body["messages"]
      |> Enum.filter(&(&1["role"] == "system"))
      |> Enum.map(& &1["content"])
      |> Enum.join("\n")
      |> String.trim()

  test "public Adaptive omission nil false and empty inputs retain the selected ReAct default", %{
    jido: jido
  } do
    modules = [
      PromptPolicy.Default,
      PromptPolicy.Nil,
      PromptPolicy.False,
      PromptPolicy.Empty,
      PromptPolicy.Common
    ]

    {mock, context} = mock(List.duplicate(%{reply: {:text, "Four"}}, length(modules)))

    for module <- modules do
      server = start_agent(jido, module.new!())
      assert {:ok, request} = module.ask(server, "Use the tool", context: context)
      assert {:ok, "Four"} = Request.await(request)
      assert Server.agent(server).state.requests[request.id].meta.adaptive.strategy == :react
    end

    for wire <- MockLLM.report(mock).requests,
        do: assert(system(wire) == String.trim(@react_prompt))

    assert_script_done(mock)
  end

  test "a public prompt attribute replaces the selected ReAct default", %{jido: jido} do
    {mock, context} = mock([%{reply: {:text, "Four"}}])
    server = start_agent(jido, PromptPolicy.Custom.new!())
    assert {:ok, request} = PromptPolicy.Custom.ask(server, "Use the tool", context: context)
    assert {:ok, "Four"} = Request.await(request)
    assert [wire] = MockLLM.report(mock).requests
    assert system(wire) == "Use the supplied case facts."
    assert_script_done(mock)
  end

  test "native DSL data Builder and source JSON select the same ReAct prompt", %{jido: jido} do
    {mock, context} = mock(List.duplicate(%{reply: {:text, "Four"}}, 6))
    source = Adaptive.source()
    assert {:ok, definition} = Adaptive.definition()
    assert definition == Adaptive.Agent.definition()
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
               Adaptive.base(),
               Jason.decode!(Jason.encode!(document)),
               registry
             )

    assert decoded == built and built == definition

    for value <- [Adaptive.Agent.definition(), definition, built, decoded] do
      server = start_agent(jido, value)
      assert {:ok, request} = request(server, context)
      assert {:ok, "Four"} = Request.await(request)
      assert Server.agent(server).state.requests[request.id].meta.adaptive.strategy == :react
      assert Server.agent(server).plugins == value.plugins
    end

    assert {:ok, profile} = Jido.AI.Profile.new(source)
    assert {:ok, flow} = Authoring.reasoning_flow(profile)

    direct =
      Map.merge(context, %{agent_state: %{reply: nil}, jido_ai_profiles: %{assistant: profile}})

    assert {:ok, %{result: "Four"}} = Jido.Exec.run(flow, %{query: "Use the tool"}, direct)

    assert {:ok, turn_definition} =
             Adaptive.definition(%{requests: %{source.requests | mode: :turn}})

    server = start_agent(jido, turn_definition)

    signal =
      Jido.Signal.new!("ai.adaptive.query", %{query: "Use the tool"}, source: "/examples/prompts")

    assert {:ok, %{state: %{reply: "Four"}}} = Server.call(server, signal, context: context)

    for wire <- MockLLM.report(mock).requests,
        do: assert(system(wire) == String.trim(@react_prompt))

    assert_script_done(mock)
  end

  test "native empty and custom instructions keep their selected ReAct meaning", %{jido: jido} do
    {mock, context} = mock(List.duplicate(%{reply: {:text, "Four"}}, 3))

    for instructions <- [nil, "", "Use exact case facts."] do
      assert {:ok, definition} = Adaptive.definition(%{instructions: instructions})
      server = start_agent(jido, definition)
      assert {:ok, request} = request(server, context)
      assert {:ok, "Four"} = Request.await(request)
    end

    [default, empty, custom] = MockLLM.report(mock).requests
    assert system(default) == String.trim(@react_prompt)
    assert system(empty) == ""
    assert system(custom) == "Use exact case facts."
    assert_script_done(mock)
  end

  test "each selected method resolves its own default without changing the declared profile", %{
    jido: jido
  } do
    {mock, context} = mock([%{reply: {:text, "Conclusion: Four"}}, %{reply: {:text, "Four"}}])

    assert {:ok, definition} =
             Adaptive.definition(Adaptive.options(%{available_strategies: [:cot, :react]}))

    server = start_agent(jido, definition)
    assert {:ok, first} = request(server, context, "What is two plus two?")
    assert {:ok, "Four"} = Request.await(first)
    assert Server.agent(server).state.requests[first.id].meta.adaptive.strategy == :cot
    assert {:ok, next} = request(server, context)
    assert {:ok, "Four"} = Request.await(next)
    assert Server.agent(server).state.requests[next.id].meta.adaptive.strategy == :react
    [cot, react] = MockLLM.report(mock).requests
    assert system(cot) == String.trim(Jido.AI.Reasoning.Linear.default_prompt(:chain_of_thought))
    assert system(react) == String.trim(@react_prompt)
    assert Server.agent(server).plugins == definition.plugins
    assert_script_done(mock)
  end

  test "selected ReAct retains structured-output instructions beside its default prompt", %{
    jido: jido
  } do
    {mock, context} = mock([%{reply: {:object, %{answer: "Four"}}}])

    changes =
      Adaptive.options(%{available_strategies: [:react]})
      |> Map.put(:result, %{schema: Zoi.object(%{answer: Zoi.string()}), into: :reply})

    assert {:ok, definition} = Adaptive.definition(changes)
    server = start_agent(jido, definition)
    assert {:ok, request} = request(server, context)
    assert {:ok, %{answer: "Four"}} = Request.await(request)
    assert [wire] = MockLLM.report(mock).requests
    assert String.starts_with?(system(wire), String.trim(@react_prompt))
    assert system(wire) =~ "Structured output:"
    assert system(wire) =~ "answer"
    assert_script_done(mock)
  end

  test "direct public option maps retain the same empty-prompt defaults as macros", %{jido: jido} do
    {mock, context} = mock(List.duplicate(%{reply: {:text, "Four"}}, 4))

    for extra <- [[], [system_prompt: nil], [system_prompt: false], [system_prompt: ""]] do
      definition =
        JidoAI.Examples.PluginStack.definition(
          [reasoning: :adaptive, reasoning_options: %{available_strategies: [:react]}] ++ extra
        )

      server = start_agent(jido, definition)
      assert {:ok, request} = request(server, context)
      assert {:ok, "Four"} = Request.await(request)
    end

    for wire <- MockLLM.report(mock).requests,
        do: assert(system(wire) == String.trim(@react_prompt))

    assert_script_done(mock)
  end

  test "direct native ReAct keeps optional instructions without applying Adaptive defaults", %{
    jido: jido
  } do
    {mock, context} = mock([%{reply: {:text, "Four"}}])
    changes = %{reasoning: %{Adaptive.source().reasoning | method: :react, options: %{}}}
    assert {:ok, definition} = Adaptive.definition(changes)
    server = start_agent(jido, definition)
    assert {:ok, request} = request(server, context)
    assert {:ok, "Four"} = Request.await(request)
    assert [wire] = MockLLM.report(mock).requests
    assert system(wire) == ""
    assert_script_done(mock)
  end

  defp atoms(value) when is_atom(value), do: [value]
  defp atoms(value) when is_list(value), do: Enum.flat_map(value, &atoms/1)
  defp atoms(value) when is_tuple(value), do: value |> Tuple.to_list() |> atoms()
  defp atoms(%_{}), do: []

  defp atoms(value) when is_map(value),
    do: Enum.flat_map(value, fn {k, v} -> atoms(k) ++ atoms(v) end)

  defp atoms(_), do: []
end
