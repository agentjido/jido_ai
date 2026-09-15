defmodule Jido.AI.Actions.Reasoning.RunStrategyProfileTest do
  use ExUnit.Case, async: false
  use Mimic

  import Jido.AI.Test

  alias Jido.AI.Actions.Reasoning.{RunCapability, RunStrategy}
  alias Jido.AI.Error.Validation.Invalid
  alias Jido.AI.{Agent, Profile, Reasoning}
  alias Jido.AgentServer
  alias Jido.AI.Plugins.ModelRouting
  alias Jido.AI.Plugins.Reasoning.ChainOfThought

  @moduletag :unit
  setup :set_mimic_from_context

  test "all seven bindings keep their ID, Profile defaults, and explicit method limits" do
    for method <- [
          :chain_of_draft,
          :chain_of_thought,
          :tree_of_thoughts,
          :graph_of_thoughts,
          :trm,
          :algorithm_of_thoughts,
          :adaptive
        ] do
      profile = profile(%{reasoning: method})
      assert capture_profile(profile) == profile
      assert profile.id == :review
      assert profile.models.default.model == :fast
      assert profile.instructions == nil

      assert Map.take(profile.controls, [:timeout, :max_iterations, :max_model_calls, :max_tool_calls]) == %{
               timeout: 60_000,
               max_iterations: 8,
               max_model_calls: 12,
               max_tool_calls: 16
             }

      refute profile.requests.streaming
      assert profile.requests.on_busy == :reject
      assert profile.result.into == :answer
      assert profile.result.schema == nil

      profile =
        put_in(profile.controls, %{
          timeout: 30_000,
          max_iterations: :method_default,
          max_model_calls: :method_default,
          max_tool_calls: :method_default
        })

      assert {:ok, profile} = Profile.validate(profile)
      assert capture_profile(profile) == profile
      assert {:ok, selected, _} = Reasoning.select(profile, "What is this?")
      assert is_integer(selected.controls.max_iterations)
      assert selected.controls.max_model_calls == selected.controls.max_iterations + selected.result.max_repairs
    end
  end

  test "only one nonempty string prompt is accepted, including direct calls" do
    stub(AgentServer, :start_link, fn _ -> flunk("Invalid input must not start a server") end)
    context = %{jido_ai_callable_profile: profile()}

    invalid = [
      %{},
      nil,
      [],
      "prompt",
      %{prompt: ""},
      %{prompt: nil},
      %{prompt: false},
      %{prompt: 1},
      %{prompt: ["text"]},
      %{:prompt => "one", "prompt" => "two"}
    ]

    legacy = [
      :strategy,
      :model,
      :profile,
      :profile_id,
      :timeout,
      :options,
      :system_prompt,
      :temperature,
      :max_tokens,
      :tools,
      :max_model_calls,
      :default_model,
      :llm_timeout_ms,
      :request_policy,
      :branching_factor,
      :max_nodes,
      :available_strategies,
      :jido_ai_callable_profile
    ]

    invalid =
      invalid ++ for key <- legacy, form <- [key, Atom.to_string(key)], do: Map.put(%{prompt: "Explain"}, form, nil)

    for params <- invalid do
      assert {:error, :invalid_strategy_request} = RunStrategy.run(params, context)
      assert {:error, _} = Jido.Exec.run(RunStrategy, params, context)
    end

    assert {:ok, %{prompt: "  "}} = RunStrategy.validate_params(%{"prompt" => "  "})
    assert {:ok, %{prompt: " Keep spacing "}} = RunStrategy.validate_params(%{prompt: " Keep spacing "})
    assert {:error, _} = Zoi.parse(RunStrategy.schema(), %{prompt: "ok", model: :fast})
  end

  test "binding requires a resolved Profile; input and old caller defaults cannot supply policy" do
    assert {:error, :reasoning_profile_not_bound} = RunStrategy.run(%{prompt: "Explain"}, %{})

    for value <- [nil, :review, "review", %{id: :review}, {:ref, :review}, fn -> profile() end] do
      assert {:error, %Invalid{field: "profile"}} =
               RunStrategy.run(%{prompt: "Explain"}, %{jido_ai_callable_profile: value})
    end

    defaults = %{default_model: :reasoning, timeout: 1, options: %{system_prompt: "Old instructions"}}

    context =
      Map.merge(defaults, %{
        provided_params: [],
        plugin_state: %{reasoning_cot: defaults},
        state: %{reasoning_cot: defaults},
        agent: %{state: %{reasoning_cot: defaults}}
      })

    assert capture_profile(profile(), context) == profile()
  end

  test "Profile errors retain field order and reject turn mode, ReAct, collisions, nil and false" do
    stub(AgentServer, :start_link, fn _ -> flunk("Invalid policy must not start a server") end)

    for {value, field} <- [
          {%{profile() | instructions: 123, controls: %{timeout: 0}}, "instructions"},
          {put_in(profile().models.default.model, false), "models"},
          {put_in(profile().models.default.model, nil), "models"},
          {put_in(profile().controls.timeout, 0), "controls"},
          {put_in(profile().requests.mode, :turn), "requests.mode"},
          {put_in(profile().reasoning.method, :react), "reasoning.method"},
          {put_in(profile().result.into, nil), "result"},
          {put_in(profile().memory.history, :answer), "memory.history"}
        ] do
      assert {:error, %Invalid{field: ^field}} =
               RunStrategy.run(%{prompt: "Explain"}, %{jido_ai_callable_profile: value})
    end

    assert {:error, %Invalid{}} = Profile.new(%{id: :review, timeout: 3, result: %{into: :answer}})
    assert {:error, %Invalid{}} = Profile.new(%{id: :review, controls: %{unknown: true}, result: %{into: :answer}})
  end

  test "AoT keeps canonical generation fields, false options, and normalized examples" do
    profile =
      profile(%{
        models: %{answer: %{model: :capable, temperature: 0.4, max_tokens: 700, timeout: 900}},
        reasoning: %{
          method: :algorithm_of_thoughts,
          model: :answer,
          options: %{profile: :short, search_style: :bfs, require_explicit_answer: false, examples: [" sample ", " "]}
        }
      })

    assert capture_profile(profile) == profile
    assert profile.reasoning.options.require_explicit_answer == false
    assert profile.reasoning.options.examples == ["sample"]
    assert profile.models.answer.temperature == 0.4
    assert profile.models.answer.max_tokens == 700
    assert profile.models.answer.timeout == 900
  end

  test "a tool completes with an explicit host binding and provider options under the retained ID" do
    script =
      expect_react do
        user("Explain tool execution")
        answer("Tool answer")
      end

    profile = profile(%{controls: %{timeout: 5_000}})

    assert {:ok, payload, []} =
             Jido.AI.Turn.execute(
               "reason",
               %{"prompt" => "Explain tool execution"},
               %{jido_ai_callable_profile: profile, ai: %{review: %{options: react_llm_opts(script)}}},
               tools: %{"reason" => RunStrategy},
               timeout: 10_000
             )

    assert payload.strategy == :cot
    assert payload.status == :success
    assert payload.output == "Tool answer"
    assert payload.diagnostics.timeout == 5_000
    refute inspect(payload.diagnostics) =~ "jido_ai_callable_profile"
  end

  test "reasoning and routing Plugins compose without flat model input" do
    owner = self()

    stub(AgentServer, :start_link, fn opts ->
      send(owner, {:routed_profile, Agent.profile(Keyword.fetch!(opts, :agent), :review)})
      Mimic.call_original(AgentServer, :start_link, [opts])
    end)

    expect_react do
      user("Explain composition")
      answer("Plugin answer")
    end

    profile = profile(%{instructions: "Use facts", controls: %{timeout: 5_000}})
    agent = definition(profile, [{ModelRouting, [routes: %{"reasoning.cot.run" => :capable}]}])
    signal = Jido.Signal.new!("reasoning.cot.run", %{prompt: "Explain composition"}, source: "/test")
    assert {:ok, updated, []} = Jido.Agent.cmd(agent, signal)
    assert updated.state.answer.strategy == :cot
    assert updated.state.answer.status == :success
    assert updated.state.answer.output == "Plugin answer"
    assert updated.state.answer.diagnostics.timeout == 5_000
    assert updated.state.reasoning_cot == agent.state.reasoning_cot
    assert_receive {:routed_profile, profile}
    assert profile.models.default.model == :capable
    assert profile.instructions == "Use facts"
  end

  test "core rejects forged prepared input and RunCapability requires the selected Plugin" do
    agent = definition(profile())
    signal = Jido.Signal.new!("reasoning.cot.run", %{prompt: "Explain"}, source: "/test")

    forged = %{
      ChainOfThought => %Jido.Plugin.Input{prepared: %{owner: ChainOfThought, profile: profile(), key: :reasoning_cot}}
    }

    assert {:error, _} = Jido.Agent.cmd(agent, signal, context: %{plugin_inputs: forged})
    assert {:error, :reasoning_capability_not_bound} = RunCapability.run(%{prompt: "Explain"}, %{})
    assert {:error, :reasoning_capability_not_bound} = RunCapability.run(%{prompt: "Explain"}, %{agent_state: %{}})

    for field <- [:strategy, :model, :profile, :options] do
      signal = %{signal | data: %{field => :got, prompt: "Explain"}}
      assert {:error, _} = Jido.Agent.cmd(agent, signal)
      assert agent.state.answer == nil
    end
  end

  defp profile(attrs \\ %{}) do
    Profile.new!(
      Map.merge(
        %{id: :review, reasoning: :chain_of_thought, requests: %{mode: :session}, result: %{into: :answer}},
        attrs
      )
    )
  end

  defp definition(profile, plugins \\ []) do
    Jido.Agent.new!(%{
      name: "callable_reasoning_composition",
      schema: Zoi.object(%{answer: Zoi.any() |> Zoi.default(nil)}),
      plugins: [{ChainOfThought, [profile: profile]} | plugins],
      routes: ChainOfThought.signal_routes([])
    })
    |> Jido.Agent.instantiate!()
  end

  defp capture_profile(profile, context \\ %{}) do
    owner = self()

    stub(AgentServer, :start_link, fn opts ->
      send(owner, {:profile, Agent.profile(Keyword.fetch!(opts, :agent), profile.id)})
      {:error, :startup_not_requested}
    end)

    assert {:error, :startup_not_requested} =
             RunStrategy.run(%{prompt: "Explain"}, Map.put(context, :jido_ai_callable_profile, profile))

    assert_receive {:profile, %Profile{} = profile}
    profile
  end
end
