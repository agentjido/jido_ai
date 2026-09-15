defmodule Jido.AI.Actions.Reasoning.RunStrategyProfileTest do
  use ExUnit.Case, async: false
  use Mimic

  import Jido.AI.Test

  alias Jido.AI.Actions.Reasoning.RunStrategy
  alias Jido.AI.Error.Validation.Invalid
  alias Jido.AI.{Agent, Profile, Reasoning}
  alias Jido.AgentServer
  alias Jido.AI.Plugins.ModelRouting
  alias Jido.AI.Plugins.Reasoning.ChainOfThought

  @moduletag :unit

  setup :set_mimic_from_context

  test "all callable methods reach the server with canonical profiles and deferred method limits" do
    for {strategy, method} <- [
          cod: :chain_of_draft,
          cot: :chain_of_thought,
          tot: :tree_of_thoughts,
          got: :graph_of_thoughts,
          trm: :trm,
          aot: :algorithm_of_thoughts,
          adaptive: :adaptive
        ] do
      profile = capture_profile(%{strategy: strategy, prompt: "Explain the result"})

      assert profile.reasoning.method == method
      assert profile.models.answer.model == :fast
      assert profile.instructions == nil
      assert profile.controls.timeout == 30_000
      assert profile.controls.max_iterations == :method_default
      assert profile.controls.max_model_calls == :method_default
      assert profile.controls.max_tool_calls == :method_default
      assert profile.requests.mode == :session
      assert profile.requests.streaming
      assert profile.requests.on_busy == :reject
      assert profile.result.into == :result
      assert profile.result.schema == nil
      assert {:ok, ^profile} = Profile.validate(profile)

      assert {:ok, selected, _selection} = Reasoning.select(profile, "What is this?")
      assert is_integer(selected.controls.max_iterations)
      assert selected.controls.max_model_calls == selected.controls.max_iterations + selected.result.max_repairs
    end
  end

  test "top-level values precede nested values and canonical validation normalizes method options" do
    profile =
      capture_profile(%{
        strategy: :aot,
        prompt: "Find an answer",
        model: :capable,
        profile: :short,
        require_explicit_answer: false,
        temperature: 0.4,
        options: %{
          "model" => :reasoning,
          "profile" => "long",
          "search_style" => "bfs",
          "require_explicit_answer" => true,
          "temperature" => 0.8,
          "max_tokens" => 700,
          "llm_timeout_ms" => 900,
          "examples" => ["  sample  ", " "]
        }
      })

    assert profile.models.answer.model == :capable
    assert Map.new(profile.models.answer.generation) == %{temperature: 0.4, max_tokens: 700, receive_timeout: 900}

    assert profile.reasoning.options == %{
             profile: :short,
             search_style: :bfs,
             examples: ["sample"],
             require_explicit_answer: false
           }
  end

  test "caller presence and context precedence retain the Action defaults contract" do
    defaults = %{default_model: :reasoning, timeout: 850, options: %{system_prompt: "Plugin prompt"}}

    for source <- [
          %{plugin_state: %{reasoning_cot: defaults}},
          %{state: %{reasoning_cot: defaults}},
          %{agent: %{state: %{reasoning_cot: defaults}}}
        ] do
      params = %{strategy: :cot, prompt: "Explain", timeout: 30_000, options: %{}}
      omitted = Map.put(source, :provided_params, [:strategy, :prompt])
      profile = capture_profile(params, omitted)
      assert profile.models.answer.model == :reasoning
      assert profile.controls.timeout == 850
      assert profile.instructions == "Plugin prompt"

      explicit = Map.put(source, :provided_params, ["strategy", "prompt", "timeout", "options"])
      assert capture_profile(params, explicit).controls.timeout == 30_000

      context = Map.merge(omitted, %{default_model: :capable, timeout: 950, options: %{system_prompt: "Caller prompt"}})
      profile = capture_profile(params, context)
      assert profile.models.answer.model == :capable
      assert profile.controls.timeout == 950
      assert profile.instructions == "Caller prompt"
    end
  end

  test "direct callers retain nil fallback, atom-key precedence, and ignored options" do
    profile =
      capture_profile(%{
        strategy: :cot,
        prompt: "Explain",
        system_prompt: nil,
        options: %{
          :system_prompt => "Nested prompt",
          "system_prompt" => "String prompt",
          :max_iterations => 0,
          :max_model_calls => 0,
          :max_tool_calls => 0,
          :branching_factor => 0,
          :temperature => 0.9
        }
      })

    assert profile.instructions == "Nested prompt"
    assert profile.models.answer.generation == []
    refute Map.has_key?(profile.reasoning, :options)
    assert profile.controls.max_model_calls == :method_default
  end

  test "Profile errors precede server startup and retain their field order" do
    stub(AgentServer, :start_link, fn _ -> flunk("Invalid input must not start a server") end)

    for {overrides, field} <- [
          {%{strategy: :cot, system_prompt: 123, timeout: 0}, "instructions"},
          {%{max_depth: 0, timeout: 0}, "reasoning.options"},
          {%{timeout: 0}, "controls"},
          {%{strategy: :cot, request_policy: :queue}, "requests"}
        ] do
      params = Map.merge(%{strategy: :tot, prompt: "Explain"}, overrides)
      assert {:error, %Invalid{field: ^field}} = RunStrategy.run(params, %{})
    end

    assert {:error, :invalid_strategy_request} = RunStrategy.run(%{strategy: :react, prompt: "Explain"}, %{})
    assert {:error, :invalid_strategy_request} = RunStrategy.run(%{strategy: :cot, prompt: ""}, %{})
  end

  test "a callable tool completes through the isolated Agent and Session" do
    script =
      expect_react do
        user("Explain tool execution")
        answer("Tool answer")
      end

    assert {:ok, payload, []} =
             Jido.AI.Turn.execute(
               "reason",
               %{"strategy" => "cot", "prompt" => "Explain tool execution", "timeout" => 5_000},
               %{ai: %{assistant: %{options: react_llm_opts(script)}}},
               tools: %{"reason" => RunStrategy},
               timeout: 10_000
             )

    assert payload.strategy == :cot
    assert payload.status == :success
    assert is_binary(payload.output)
    assert payload.output == "Tool answer"
    assert payload.diagnostics.timeout == 5_000
  end

  test "reasoning and model-routing Plugins compose with a fixed method and result field" do
    owner = self()

    stub(AgentServer, :start_link, fn opts ->
      send(owner, {:routed_profile, Agent.profile(Keyword.fetch!(opts, :agent), :assistant)})
      Mimic.call_original(AgentServer, :start_link, [opts])
    end)

    expect_react do
      user("Explain composition")
      answer("Plugin answer")
    end

    config = [default_model: :fast, timeout: 5_000, into: :answer, options: %{system_prompt: "Use facts"}]

    agent =
      Jido.Agent.new!(%{
        name: "callable_reasoning_composition",
        schema: Zoi.object(%{answer: Zoi.any() |> Zoi.default(nil)}),
        plugins: [
          {ChainOfThought, config},
          {ModelRouting, [routes: %{"reasoning.cot.run" => :capable}]}
        ],
        routes: ChainOfThought.signal_routes(config)
      })
      |> Jido.Agent.instantiate!()

    signal = Jido.Signal.new!("reasoning.cot.run", %{strategy: :got, prompt: "Explain composition"}, source: "/test")

    assert {:ok, updated, []} = Jido.Agent.cmd(agent, signal)
    assert updated.state.answer.strategy == :cot
    assert updated.state.answer.status == :success
    assert updated.state.answer.output == "Plugin answer"
    assert updated.state.answer.diagnostics.timeout == 5_000
    assert updated.state.reasoning_cot == agent.state.reasoning_cot
    assert_receive {:routed_profile, profile}
    assert profile.models.answer.model == :capable
    assert profile.instructions == "Use facts"
  end

  defp capture_profile(params, context \\ %{}) do
    owner = self()

    stub(AgentServer, :start_link, fn opts ->
      send(owner, {:profile, Agent.profile(Keyword.fetch!(opts, :agent), :assistant)})
      {:error, :startup_not_requested}
    end)

    assert {:error, :startup_not_requested} = RunStrategy.run(params, context)
    assert_receive {:profile, %Profile{} = profile}
    profile
  end
end
