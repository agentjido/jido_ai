defmodule Jido.AI.Reasoning.Adaptive.StrategyTest do
  use ExUnit.Case, async: true

  alias Jido.Agent.Directive, as: AgentDirective
  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.AI.Reasoning.Adaptive.Strategy, as: Adaptive
  alias Jido.AI.Reasoning.ChainOfThought.Strategy, as: ChainOfThought
  alias Jido.AI.Reasoning.GraphOfThoughts.Strategy, as: GraphOfThoughts
  alias Jido.AI.Reasoning.ReAct.Strategy, as: ReAct
  alias Jido.AI.Reasoning.TreeOfThoughts.Strategy, as: TreeOfThoughts
  alias Jido.AI.Reasoning.TRM.Strategy, as: TRM

  @moduletag :unit

  # Helper to create an initialized agent
  defp create_agent(opts \\ []) do
    %Jido.Agent{
      id: "test-agent",
      name: "test_adaptive_agent",
      state: %{}
    }
    |> then(fn agent ->
      ctx = %{strategy_opts: opts}
      {agent, []} = Adaptive.init(agent, ctx)
      {agent, ctx}
    end)
  end

  describe "action_spec/1" do
    test "returns spec for adaptive_start" do
      spec = Adaptive.action_spec(:adaptive_start)
      assert spec.name == "adaptive.start"
      assert spec.doc =~ "Start adaptive reasoning"
    end

    test "returns spec for adaptive_llm_result" do
      spec = Adaptive.action_spec(:adaptive_llm_result)
      assert spec.name == "adaptive.llm_result"
      assert spec.doc =~ "Handle LLM response"
    end

    test "returns spec for adaptive_llm_partial" do
      spec = Adaptive.action_spec(:adaptive_llm_partial)
      assert spec.name == "adaptive.llm_partial"
      assert spec.doc =~ "Handle streaming LLM token chunk"
    end

    test "returns nil for unknown action" do
      assert is_nil(Adaptive.action_spec(:unknown_action))
    end
  end

  describe "signal_routes/1" do
    test "returns base signal routes" do
      {_agent, ctx} = create_agent()
      routes = Adaptive.signal_routes(ctx)

      assert {"ai.adaptive.query", {:strategy_cmd, :adaptive_start}} in routes
      assert {"ai.llm.response", {:strategy_cmd, :adaptive_llm_result}} in routes
      assert {"ai.llm.delta", {:strategy_cmd, :adaptive_llm_partial}} in routes
      assert {"ai.request.started", Jido.Actions.Control.Noop} in routes
      assert {"ai.request.completed", Jido.Actions.Control.Noop} in routes
      assert {"ai.request.failed", Jido.Actions.Control.Noop} in routes
      assert {"ai.tool.result", Jido.Actions.Control.Noop} in routes
      assert {"ai.cot.worker.event", {:strategy_cmd, :adaptive_cot_worker_event}} in routes
      assert {"ai.react.worker.event", {:strategy_cmd, :adaptive_react_worker_event}} in routes
    end
  end

  describe "init/2" do
    test "initializes with default config" do
      {agent, _ctx} = create_agent()
      state = StratState.get(agent, %{})

      assert state[:config][:model] == "anthropic:claude-haiku-4-5"
      assert state[:config][:default_strategy] == :react
      assert state[:config][:available_strategies] == [:cot, :react, :tot, :got, :trm]
      assert is_nil(state[:selected_strategy])
      assert is_nil(state[:strategy_type])
    end

    test "initializes with custom config" do
      {agent, _ctx} =
        create_agent(
          model: "openai:gpt-4",
          default_strategy: :cot,
          available_strategies: [:cot, :react, :tot, :got]
        )

      state = StratState.get(agent, %{})

      assert state[:config][:model] == "openai:gpt-4"
      assert state[:config][:default_strategy] == :cot
      assert state[:config][:available_strategies] == [:cot, :react, :tot, :got]
    end

    test "initializes with custom complexity thresholds" do
      {agent, _ctx} =
        create_agent(complexity_thresholds: %{simple: 0.2, complex: 0.8})

      state = StratState.get(agent, %{})
      assert state[:config][:complexity_thresholds] == %{simple: 0.2, complex: 0.8}
    end
  end

  describe "snapshot/2" do
    test "returns idle status before strategy selection" do
      {agent, ctx} = create_agent()
      snapshot = Adaptive.snapshot(agent, ctx)

      assert snapshot.status == :idle
      assert snapshot.done? == false
      assert snapshot.details.phase == :awaiting_selection
    end
  end

  describe "analyze_prompt/2" do
    test "classifies simple prompts" do
      {strategy, score, task_type} = Adaptive.analyze_prompt("What is the capital of France?")

      assert strategy == :cot
      assert score < 0.3
      assert task_type == :simple_query
    end

    test "classifies tool-use prompts" do
      {strategy, _score, task_type} =
        Adaptive.analyze_prompt("Search for the latest news about AI and fetch the top 5 results.")

      assert strategy == :react
      assert task_type == :tool_use
    end

    test "classifies complex exploration prompts" do
      # Exploration keywords without synthesis keywords
      {strategy, score, task_type} =
        Adaptive.analyze_prompt("""
        Analyze the following complex problem step by step.
        Consider the ethical implications, economic factors, and social consequences.
        Explore alternative solutions and compare their trade-offs.
        You must evaluate each option against the following criteria:
        1. Cost effectiveness
        2. Scalability
        3. Environmental impact
        4. Social acceptance
        What are the multiple options we should consider?
        """)

      assert strategy == :tot
      assert score > 0.7
      assert task_type == :exploration
    end

    test "classifies synthesis prompts for GoT" do
      # Synthesis keywords should select GoT
      {strategy, _score, task_type} =
        Adaptive.analyze_prompt("""
        Synthesize the following viewpoints into a unified recommendation.
        Combine the insights from marketing, engineering, and finance teams.
        Integrate their perspectives to create a comprehensive strategy.
        """)

      assert strategy == :got
      assert task_type == :synthesis
    end

    test "classifies moderate complexity prompts" do
      # A moderately complex prompt without tool keywords but more structure
      prompt = """
      I need to implement a sorting algorithm. The algorithm should work efficiently
      for large datasets. It must handle edge cases like empty arrays and single elements.
      The implementation should also track the number of comparisons made.
      """

      {strategy, score, _task_type} = Adaptive.analyze_prompt(prompt)

      # Moderate complexity score (between thresholds)
      assert score >= 0.3 and score <= 0.7, "Score #{score} should be between 0.3 and 0.7"
      # Without tool keywords, should select based on complexity - moderate goes to react
      assert strategy == :react
    end

    test "respects available strategies" do
      config = %{available_strategies: [:cot, :tot]}

      # Tool-use prompt, but ReAct not available
      {strategy, _score, _task_type} =
        Adaptive.analyze_prompt("Search for information", config)

      # Should fall back to available strategy
      assert strategy in [:cot, :tot]
    end
  end

  describe "calculate_complexity (via analyze_prompt)" do
    test "longer prompts have higher complexity" do
      short = "What is 2+2?"
      long = String.duplicate("This is a complex multi-sentence prompt. ", 20)

      {_strat1, score1, _type1} = Adaptive.analyze_prompt(short)
      {_strat2, score2, _type2} = Adaptive.analyze_prompt(long)

      assert score2 > score1
    end

    test "prompts with constraints have higher complexity" do
      simple = "Tell me about cats."

      constrained =
        "You must explain cats. You need to include their history. You should also mention their behavior. You have to be thorough."

      {_strat1, score1, _type1} = Adaptive.analyze_prompt(simple)
      {_strat2, score2, _type2} = Adaptive.analyze_prompt(constrained)

      assert score2 > score1
    end

    test "prompts with multiple questions have higher complexity" do
      single = "What is Python?"
      multiple = "What is Python? How does it compare to Java? Which should I learn? What are the job prospects?"

      {_strat1, score1, _type1} = Adaptive.analyze_prompt(single)
      {_strat2, score2, _type2} = Adaptive.analyze_prompt(multiple)

      assert score2 > score1
    end
  end

  describe "cmd/3 - strategy selection" do
    test "selects CoT for simple prompts" do
      {agent, ctx} = create_agent()

      instructions = [
        %{action: :adaptive_start, params: %{prompt: "What is 2+2?"}}
      ]

      {agent, _directives} = Adaptive.cmd(agent, instructions, ctx)
      state = StratState.get(agent, %{})

      assert state[:strategy_type] == :cot
      assert state[:selected_strategy] == ChainOfThought
    end

    test "selects ReAct for tool-use prompts" do
      # ReAct requires tools option
      {agent, ctx} = create_agent(tools: [])

      instructions = [
        %{action: :adaptive_start, params: %{prompt: "Search for and calculate the sum of the first 10 prime numbers."}}
      ]

      {agent, _directives} = Adaptive.cmd(agent, instructions, ctx)
      state = StratState.get(agent, %{})

      assert state[:strategy_type] == :react
      assert state[:selected_strategy] == ReAct
    end

    test "selects ToT for complex exploration prompts" do
      {agent, ctx} = create_agent()

      # Exploration keywords without synthesis keywords (no "perspectives", etc.)
      complex_prompt = """
      Analyze this complex problem step by step.
      Consider various alternatives and compare them.
      Explore different options and evaluate their trade-offs.
      You must assess each approach carefully.
      What are the multiple paths we should consider?
      """

      instructions = [
        %{action: :adaptive_start, params: %{prompt: complex_prompt}}
      ]

      {agent, _directives} = Adaptive.cmd(agent, instructions, ctx)
      state = StratState.get(agent, %{})

      assert state[:strategy_type] == :tot
      assert state[:selected_strategy] == TreeOfThoughts
    end

    test "emits delegated directive after strategy selection" do
      {agent, ctx} = create_agent()

      instructions = [
        %{action: :adaptive_start, params: %{prompt: "What is AI?"}}
      ]

      {_agent, directives} = Adaptive.cmd(agent, instructions, ctx)

      # CoT now delegates via worker spawn; other strategies may still emit LLMStream
      assert directives != []

      assert Enum.any?(directives, fn d ->
               match?(%Jido.AI.Directive.LLMStream{}, d) or match?(%AgentDirective.SpawnAgent{}, d)
             end)
    end
  end

  describe "cmd/3 - manual override" do
    test "respects strategy override option" do
      {agent, ctx} =
        create_agent(strategy: :tot)

      # Even a simple prompt should use ToT when overridden
      instructions = [
        %{action: :adaptive_start, params: %{prompt: "What is 2+2?"}}
      ]

      {agent, _directives} = Adaptive.cmd(agent, instructions, ctx)
      state = StratState.get(agent, %{})

      assert state[:strategy_type] == :tot
      assert state[:selected_strategy] == TreeOfThoughts
    end

    test "override to GoT works" do
      {agent, ctx} =
        create_agent(
          strategy: :got,
          available_strategies: [:cot, :react, :tot, :got]
        )

      instructions = [
        %{action: :adaptive_start, params: %{prompt: "Simple question"}}
      ]

      {agent, _directives} = Adaptive.cmd(agent, instructions, ctx)
      state = StratState.get(agent, %{})

      assert state[:strategy_type] == :got
      assert state[:selected_strategy] == GraphOfThoughts
    end
  end

  describe "cmd/3 - delegation" do
    test "delegates subsequent commands to selected strategy" do
      {agent, ctx} = create_agent()

      # First, select a strategy
      start_instructions = [
        %{action: :adaptive_start, params: %{prompt: "What is AI?", request_id: "req_adaptive_cot_1"}}
      ]

      {agent, directives} = Adaptive.cmd(agent, start_instructions, ctx)
      [spawn | _] = directives
      assert %AgentDirective.SpawnAgent{} = spawn

      child_started = %{
        action: :adaptive_child_started,
        params: %{
          parent_id: "parent",
          child_id: "child",
          child_module: Jido.AI.Reasoning.ChainOfThought.Worker.Agent,
          tag: :cot_worker,
          pid: self(),
          meta: %{}
        }
      }

      {agent, [emit]} = Adaptive.cmd(agent, [child_started], ctx)
      assert %AgentDirective.Emit{} = emit
      assert emit.signal.type == "ai.cot.worker.start"

      completion_event = %{
        id: "evt_adaptive_cot_done",
        seq: 1,
        at_ms: 1_700_000_000_000,
        run_id: "req_adaptive_cot_1",
        request_id: "req_adaptive_cot_1",
        iteration: 1,
        kind: :request_completed,
        llm_call_id: "cot_call_req_adaptive_cot_1",
        tool_call_id: nil,
        tool_name: nil,
        data: %{
          result: "Step 1: Think.\nConclusion: AI is artificial intelligence.",
          termination_reason: :success,
          usage: %{input_tokens: 10, output_tokens: 20}
        }
      }

      result_instructions = [
        %{
          action: :adaptive_cot_worker_event,
          params: %{
            request_id: "req_adaptive_cot_1",
            event: completion_event
          }
        }
      ]

      {agent, _directives} = Adaptive.cmd(agent, result_instructions, ctx)

      # The strategy should have processed the result
      state = StratState.get(agent, %{})
      assert state[:selected_strategy] != nil
    end
  end

  describe "get_selected_strategy/1" do
    test "returns nil before selection" do
      {agent, _ctx} = create_agent()
      assert is_nil(Adaptive.get_selected_strategy(agent))
    end

    test "returns strategy type after selection" do
      {agent, ctx} = create_agent()

      instructions = [
        %{action: :adaptive_start, params: %{prompt: "What is 2+2?"}}
      ]

      {agent, _directives} = Adaptive.cmd(agent, instructions, ctx)

      assert Adaptive.get_selected_strategy(agent) == :cot
    end
  end

  describe "get_complexity_score/1" do
    test "returns nil before selection" do
      {agent, _ctx} = create_agent()
      assert is_nil(Adaptive.get_complexity_score(agent))
    end

    test "returns score after selection" do
      {agent, ctx} = create_agent()

      instructions = [
        %{action: :adaptive_start, params: %{prompt: "What is 2+2?"}}
      ]

      {agent, _directives} = Adaptive.cmd(agent, instructions, ctx)

      score = Adaptive.get_complexity_score(agent)
      assert is_float(score)
      assert score >= 0.0 and score <= 1.0
    end
  end

  describe "action helper functions" do
    test "start_action/0 returns correct atom" do
      assert Adaptive.start_action() == :adaptive_start
    end

    test "llm_result_action/0 returns correct atom" do
      assert Adaptive.llm_result_action() == :adaptive_llm_result
    end

    test "llm_partial_action/0 returns correct atom" do
      assert Adaptive.llm_partial_action() == :adaptive_llm_partial
    end
  end

  describe "task type detection" do
    test "detects tool-use from keywords" do
      prompts = [
        "Search for information about climate change",
        "Find the best restaurants nearby",
        "Lookup the definition of this word",
        "Fetch the latest stock prices",
        "Calculate the total cost",
        "Execute this query",
        "Run the analysis tool"
      ]

      for prompt <- prompts do
        {strategy, _score, task_type} = Adaptive.analyze_prompt(prompt)
        assert task_type == :tool_use, "Expected tool_use for: #{prompt}"
        assert strategy == :react, "Expected :react for tool-use prompt: #{prompt}"
      end
    end

    test "detects exploration from keywords" do
      prompts = [
        "Analyze the implications of this decision",
        "Explore different approaches to solving this",
        "Consider multiple options for the design",
        "Compare and contrast these alternatives",
        "Evaluate the different strategies"
      ]

      for prompt <- prompts do
        {_strategy, _score, task_type} = Adaptive.analyze_prompt(prompt)
        assert task_type == :exploration, "Expected exploration for: #{prompt}"
      end
    end

    test "detects simple queries" do
      prompts = [
        "What is machine learning?",
        "Who invented the telephone?",
        "When was Python created?",
        "Where is the Eiffel Tower?",
        "Define recursion",
        "Explain how databases work",
        "Tell me about cats"
      ]

      for prompt <- prompts do
        {_strategy, _score, task_type} = Adaptive.analyze_prompt(prompt)
        assert task_type == :simple_query, "Expected simple_query for: #{prompt}"
      end
    end
  end

  describe "edge cases" do
    test "handles empty prompt" do
      {agent, ctx} = create_agent()

      instructions = [
        %{action: :adaptive_start, params: %{prompt: ""}}
      ]

      {agent, _directives} = Adaptive.cmd(agent, instructions, ctx)
      state = StratState.get(agent, %{})

      # Should still select a strategy (default)
      assert state[:selected_strategy] != nil
    end

    test "handles very long prompt" do
      # Long prompts may select ReAct, which requires tools
      {agent, ctx} = create_agent(tools: [])

      long_prompt = String.duplicate("This is a test sentence. ", 500)

      instructions = [
        %{action: :adaptive_start, params: %{prompt: long_prompt}}
      ]

      {agent, _directives} = Adaptive.cmd(agent, instructions, ctx)
      state = StratState.get(agent, %{})

      assert state[:selected_strategy] != nil
      # Very long prompts should have high complexity (at least moderate)
      assert state[:complexity_score] >= 0.5
    end

    test "handles missing prompt key in params" do
      {agent, ctx} = create_agent()

      instructions = [
        %{action: :adaptive_start, params: %{}}
      ]

      {agent, _directives} = Adaptive.cmd(agent, instructions, ctx)
      state = StratState.get(agent, %{})

      # Should handle gracefully with empty prompt
      assert state[:selected_strategy] != nil
    end

    test "handles no start instruction" do
      {agent, ctx} = create_agent()

      instructions = [
        %{action: :some_other_action, params: %{foo: "bar"}}
      ]

      {agent, directives} = Adaptive.cmd(agent, instructions, ctx)

      # Should return unchanged
      assert directives == []
      state = StratState.get(agent, %{})
      assert is_nil(state[:selected_strategy])
    end
  end

  describe "strategy fallback behavior" do
    test "falls back to first available when preferred not available" do
      config = %{
        available_strategies: [:cot, :tot],
        complexity_thresholds: %{simple: 0.3, complex: 0.7}
      }

      # Moderate complexity normally selects :react, but it's not available
      prompt = "Help me with this moderately complex task that requires some steps."
      {strategy, _score, _type} = Adaptive.analyze_prompt(prompt, config)

      assert strategy in [:cot, :tot]
    end

    test "uses default strategy when analysis is inconclusive" do
      {agent, ctx} =
        create_agent(
          default_strategy: :tot,
          available_strategies: [:cot, :react, :tot]
        )

      # A prompt that doesn't strongly match any category
      instructions = [
        %{action: :adaptive_start, params: %{prompt: "Hello there"}}
      ]

      {agent, _directives} = Adaptive.cmd(agent, instructions, ctx)
      state = StratState.get(agent, %{})

      # Should fall through complexity scoring, not task type override
      assert state[:selected_strategy] != nil
    end
  end

  describe "synthesis task detection" do
    test "detects synthesis from keywords" do
      prompts = [
        "Synthesize these findings into a report",
        "Combine the results from all teams",
        "Merge these different approaches",
        "Integrate the feedback from stakeholders",
        "Aggregate the data from multiple sources"
      ]

      for prompt <- prompts do
        {strategy, _score, task_type} = Adaptive.analyze_prompt(prompt)
        assert task_type == :synthesis, "Expected synthesis for: #{prompt}"
        assert strategy == :got, "Expected :got for synthesis prompt: #{prompt}"
      end
    end

    test "detects graph-related tasks from keywords" do
      prompts = [
        "Map the relationships between these entities",
        "Identify connections in the data",
        "Analyze the network of dependencies",
        "Explore how these are linked together"
      ]

      for prompt <- prompts do
        {strategy, _score, task_type} = Adaptive.analyze_prompt(prompt)
        assert task_type == :synthesis, "Expected synthesis for: #{prompt}"
        assert strategy == :got, "Expected :got for graph-related prompt: #{prompt}"
      end
    end

    test "selects GoT when available for synthesis" do
      {agent, ctx} = create_agent(available_strategies: [:cot, :react, :tot, :got])

      instructions = [
        %{action: :adaptive_start, params: %{prompt: "Synthesize these viewpoints into one"}}
      ]

      {agent, _directives} = Adaptive.cmd(agent, instructions, ctx)
      state = StratState.get(agent, %{})

      assert state[:strategy_type] == :got
      assert state[:task_type] == :synthesis
    end

    test "falls back to ToT when GoT not available for synthesis" do
      {agent, ctx} = create_agent(available_strategies: [:cot, :react, :tot])

      instructions = [
        %{action: :adaptive_start, params: %{prompt: "Synthesize these viewpoints into one"}}
      ]

      {agent, _directives} = Adaptive.cmd(agent, instructions, ctx)
      state = StratState.get(agent, %{})

      # Falls back to ToT since GoT not available
      assert state[:strategy_type] == :tot
      assert state[:task_type] == :synthesis
    end
  end

  describe "TRM integration" do
    test "TRM is in strategy_modules" do
      # Verify TRM is registered as an available strategy
      {agent, _ctx} = create_agent()
      state = StratState.get(agent, %{})

      assert :trm in state[:config][:available_strategies]
    end

    test "detects iterative reasoning from puzzle keywords" do
      # Each prompt should contain at least one puzzle keyword:
      # puzzle, iterate, improve, refine, recursive, riddle
      prompts = [
        "This is a puzzle that needs careful reasoning",
        "Iterate on this solution until perfect",
        "Improve the answer through multiple refinements",
        "Refine this draft recursively",
        "This riddle needs careful reasoning"
      ]

      for prompt <- prompts do
        {strategy, _score, task_type} = Adaptive.analyze_prompt(prompt)
        assert task_type == :iterative_reasoning, "Expected iterative_reasoning for: #{prompt}"
        assert strategy == :trm, "Expected :trm for puzzle prompt: #{prompt}"
      end
    end

    test "selects TRM for iterative reasoning tasks" do
      {agent, ctx} = create_agent(available_strategies: [:cot, :react, :tot, :got, :trm])

      instructions = [
        %{
          action: :adaptive_start,
          params: %{prompt: "Solve this puzzle step by step and iterate to improve the solution"}
        }
      ]

      {agent, _directives} = Adaptive.cmd(agent, instructions, ctx)
      state = StratState.get(agent, %{})

      assert state[:strategy_type] == :trm
      assert state[:selected_strategy] == TRM
      assert state[:task_type] == :iterative_reasoning
    end

    test "falls back to ToT when TRM not available for iterative reasoning" do
      {agent, ctx} = create_agent(available_strategies: [:cot, :react, :tot, :got])

      instructions = [
        %{action: :adaptive_start, params: %{prompt: "This puzzle needs iterative reasoning"}}
      ]

      {agent, _directives} = Adaptive.cmd(agent, instructions, ctx)
      state = StratState.get(agent, %{})

      # Falls back to ToT since TRM not available
      assert state[:strategy_type] == :tot
      assert state[:task_type] == :iterative_reasoning
    end

    test "override to TRM works" do
      {agent, ctx} = create_agent(strategy: :trm)

      instructions = [
        %{action: :adaptive_start, params: %{prompt: "Simple question"}}
      ]

      {agent, _directives} = Adaptive.cmd(agent, instructions, ctx)
      state = StratState.get(agent, %{})

      assert state[:strategy_type] == :trm
      assert state[:selected_strategy] == TRM
    end

    test "TRM action mappings work correctly" do
      {agent, ctx} = create_agent(strategy: :trm)

      instructions = [
        %{action: :adaptive_start, params: %{prompt: "Test prompt"}}
      ]

      {agent, directives} = Adaptive.cmd(agent, instructions, ctx)

      # Should have a directive from TRM strategy
      assert directives != []
      assert Enum.any?(directives, fn d -> match?(%Jido.AI.Directive.LLMStream{}, d) end)

      # State should show TRM is selected
      state = StratState.get(agent, %{})
      assert state[:selected_strategy] == TRM
    end
  end
end
