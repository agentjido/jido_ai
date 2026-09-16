defmodule JidoAITest.Authoring.Agents.CallableProfilesTest do
  use ExUnit.Case, async: false
  @moduletag :authoring

  alias Jido.AI.Plugins.Reasoning.ChainOfThought
  alias Jido.AI.Profile
  alias Jido.AI.Test.MockLLM
  alias Jido.AgentServer, as: Server
  alias Jido.Codec.Registry

  setup do
    jido = :"authoring_callable_#{System.unique_integer([:positive])}"
    start_supervised!({Jido, name: jido})
    {:ok, jido: jido}
  end

  for form <- [:definition, :builder, :codec] do
    @tag form: form
    test "#{form}: bound Profile runs prompt-only input into its selected field", %{jido: jido, form: form} do
      profile = profile()
      source = Jido.Agent.new!(attributes(profile: profile))
      definition = transport(source, form)
      assert definition === source
      mock = start_supervised!({MockLLM, script: [%{reply: {:text, "Step 1: Add two and two.\nConclusion: Four"}}]})
      {:ok, server} = Jido.start_agent(jido, definition)
      before = Server.agent(server).state
      context = %{ai: %{review: %{options: MockLLM.options(mock)}}}

      assert {:error, _} =
               Server.call(server, signal(%{prompt: "Add", model: MockLLM.model()}), context: context)

      assert Server.agent(server).state === before
      assert %{requests: []} = MockLLM.report(mock)

      assert {:ok, agent} =
               Server.call(server, signal(%{"prompt" => "What is two plus two?"}), context: context, timeout: 10_000)

      assert agent.state.answer.output == "Four"
      assert agent.state.answer.strategy == :cot
      assert agent.state === %{before | answer: agent.state.answer}
      assert agent.state.reasoning_cot == %{}
      assert %{remaining: [], unexpected: [], requests: [request]} = MockLLM.report(mock)
      assert request.body["model"] == "gpt-4o-mini"
      assert inspect(request.body["messages"]) =~ "What is two plus two?"
    end
  end

  test "Codec needs the host Profile Registry value; JSON does not embed its policy" do
    profile = profile()
    source = Jido.Agent.new!(attributes(profile: profile))
    {:ok, document, registry} = Jido.Agent.Codec.encode(source)
    {:ok, profile_id} = Registry.identifier(registry, :value, profile)
    document = document |> Jason.encode!() |> Jason.decode!()
    assert {:ok, ^source} = Jido.Agent.Codec.decode(document, registry)
    missing = Registry.new!(Map.delete(registry.entries, profile_id))
    assert {:error, error} = Jido.Agent.Codec.decode(document, missing)
    assert Exception.message(error) =~ "Registry"
    refute Jason.encode!(document) =~ "max_model_calls"
  end

  test "core definition and Builder reject wrong methods and invalid callable configuration" do
    profile = profile()

    for options <- [
          [profile: put_in(profile.reasoning.method, :chain_of_draft)],
          [profile: put_in(profile.controls.timeout, 0)],
          [profile: profile, timeout: 100],
          []
        ] do
      assert {:error, %Jido.Error.ExecutionError{}} = Jido.Agent.new(attributes(options))

      assert {:error, %Jido.Error.ExecutionError{}} =
               attributes(options) |> Jido.Agent.Builder.new() |> Jido.Agent.Builder.build()
    end
  end

  defp profile do
    Profile.new!(%{
      id: :review,
      model: MockLLM.model(),
      reasoning: :chain_of_thought,
      controls: %{timeout: 5_000},
      result: %{into: :answer}
    })
  end

  defp attributes(options) do
    %{
      name: "authored_callable",
      schema:
        Zoi.object(%{
          answer: Zoi.any() |> Zoi.default(nil),
          unrelated: Zoi.string() |> Zoi.default("keep")
        }),
      plugins: [{ChainOfThought, options}],
      routes: ChainOfThought.signal_routes([])
    }
  end

  defp signal(data), do: Jido.Signal.new!("reasoning.cot.run", data, source: "/authoring")
  defp transport(source, :definition), do: source

  defp transport(source, :builder),
    do:
      source |> Map.from_struct() |> Map.drop([:id, :state]) |> Jido.Agent.Builder.new() |> Jido.Agent.Builder.build!()

  defp transport(source, :codec) do
    {:ok, document, registry} = Jido.Agent.Codec.encode(source)
    {:ok, decoded} = Jido.Agent.Codec.decode(Jason.decode!(Jason.encode!(document)), registry)
    decoded
  end
end
