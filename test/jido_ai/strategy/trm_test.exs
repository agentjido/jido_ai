defmodule Jido.AI.Strategies.TRMTest do
  use ExUnit.Case, async: true

  alias Jido.Agent
  alias Jido.Agent.Strategy.State
  alias Jido.AI.Directive
  alias Jido.AI.Strategies.TRM

  def build_test_agent do
    %Agent{
      id: Jido.Util.generate_id(),
      name: "test_trm_agent",
      state: %{}
    }
  end

  def build_ctx(opts \\ []) do
    %{strategy_opts: opts}
  end

  describe "action accessors" do
    test "start_action/0 returns :trm_start" do
      assert TRM.start_action() == :trm_start
    end

    test "llm_result_action/0 returns :trm_llm_result" do
      assert TRM.llm_result_action() == :trm_llm_result
    end

    test "llm_partial_action/0 returns :trm_llm_partial" do
      assert TRM.llm_partial_action() == :trm_llm_partial
    end
  end

  describe "action_spec/1" do
    test "returns spec for start action" do
      spec = TRM.action_spec(:trm_start)

      assert spec.name == "trm.start"
      assert spec.doc =~ "Start TRM"
      assert spec.schema != nil
    end

    test "returns spec for llm_result action" do
      spec = TRM.action_spec(:trm_llm_result)

      assert spec.name == "trm.llm_result"
      assert spec.doc =~ "Handle LLM response"
    end

    test "returns spec for llm_partial action" do
      spec = TRM.action_spec(:trm_llm_partial)

      assert spec.name == "trm.llm_partial"
      assert spec.doc =~ "streaming"
    end

    test "returns nil for unknown action" do
      assert TRM.action_spec(:unknown_action) == nil
    end
  end

  describe "signal_routes/1" do
    test "returns correct signal routing" do
      routes = TRM.signal_routes(%{})

      assert {"trm.query", {:strategy_cmd, :trm_start}} in routes
      assert {"reqllm.result", {:strategy_cmd, :trm_llm_result}} in routes
      assert {"reqllm.partial", {:strategy_cmd, :trm_llm_partial}} in routes
    end
  end

  describe "init/2" do
    test "creates machine with default config" do
      agent = build_test_agent()
      ctx = build_ctx()

      {agent, directives} = TRM.init(agent, ctx)

      assert directives == []

      state = State.get(agent, %{})
      assert state[:status] == :idle
      assert state[:max_supervision_steps] == 5
      assert state[:act_threshold] == 0.9
    end

    test "accepts custom max_supervision_steps" do
      agent = build_test_agent()
      ctx = build_ctx(max_supervision_steps: 10)

      {agent, _} = TRM.init(agent, ctx)

      state = State.get(agent, %{})
      assert state[:max_supervision_steps] == 10
    end

    test "accepts custom act_threshold" do
      agent = build_test_agent()
      ctx = build_ctx(act_threshold: 0.85)

      {agent, _} = TRM.init(agent, ctx)

      state = State.get(agent, %{})
      assert state[:act_threshold] == 0.85
    end

    test "accepts custom model" do
      agent = build_test_agent()
      ctx = build_ctx(model: "anthropic:claude-sonnet-4-20250514")

      {agent, _} = TRM.init(agent, ctx)

      state = State.get(agent, %{})
      assert state[:config].model == "anthropic:claude-sonnet-4-20250514"
    end

    test "stores config in state" do
      agent = build_test_agent()
      ctx = build_ctx()

      {agent, _} = TRM.init(agent, ctx)

      state = State.get(agent, %{})
      config = state[:config]

      assert config.model == "anthropic:claude-haiku-4-5"
      assert config.max_supervision_steps == 5
      assert config.act_threshold == 0.9
    end

    test "default prompts are available via helper functions" do
      # Prompts are managed internally by Reasoning/Supervision modules
      # but accessible via helper functions for reference
      assert is_binary(TRM.default_reasoning_prompt())
      assert is_binary(TRM.default_supervision_prompt())
      assert is_binary(TRM.default_improvement_prompt())
    end
  end

  describe "cmd/3 with start instruction" do
    setup do
      agent = build_test_agent()
      ctx = build_ctx()
      {agent, _} = TRM.init(agent, ctx)
      {:ok, agent: agent, ctx: ctx}
    end

    test "creates reasoning directive", %{agent: agent, ctx: ctx} do
      instruction = %Jido.Instruction{
        action: :trm_start,
        params: %{prompt: "What is machine learning?"}
      }

      {_agent, directives} = TRM.cmd(agent, [instruction], ctx)

      assert length(directives) == 1
      directive = hd(directives)

      assert %Directive.ReqLLMStream{} = directive
      assert directive.model == "anthropic:claude-haiku-4-5"
      assert directive.metadata.phase == :reasoning
    end

    test "updates state to reasoning", %{agent: agent, ctx: ctx} do
      instruction = %Jido.Instruction{
        action: :trm_start,
        params: %{prompt: "What is AI?"}
      }

      {agent, _} = TRM.cmd(agent, [instruction], ctx)

      state = State.get(agent, %{})
      assert state[:status] == :reasoning
      assert state[:question] == "What is AI?"
      assert state[:supervision_step] == 1
    end

    test "handles string keys in params", %{agent: agent, ctx: ctx} do
      instruction = %Jido.Instruction{
        action: :trm_start,
        params: %{"prompt" => "String key prompt"}
      }

      {agent, directives} = TRM.cmd(agent, [instruction], ctx)

      assert length(directives) == 1
      state = State.get(agent, %{})
      assert state[:question] == "String key prompt"
    end
  end

  describe "cmd/3 with llm_result instruction" do
    setup do
      agent = build_test_agent()
      ctx = build_ctx()
      {agent, _} = TRM.init(agent, ctx)

      # Start reasoning
      start_instr = %Jido.Instruction{
        action: :trm_start,
        params: %{prompt: "What is 2+2?"}
      }

      {agent, [directive]} = TRM.cmd(agent, [start_instr], ctx)
      call_id = directive.id

      {:ok, agent: agent, ctx: ctx, call_id: call_id}
    end

    test "processes reasoning result and returns supervise directive", %{
      agent: agent,
      ctx: ctx,
      call_id: call_id
    } do
      instruction = %Jido.Instruction{
        action: :trm_llm_result,
        params: %{
          call_id: call_id,
          result: {:ok, %{text: "The answer is 4"}},
          phase: :reasoning
        }
      }

      {_agent, directives} = TRM.cmd(agent, [instruction], ctx)

      assert length(directives) == 1
      directive = hd(directives)
      assert %Directive.ReqLLMStream{} = directive
      assert directive.metadata.phase == :supervising
    end

    test "updates state after reasoning result", %{agent: agent, ctx: ctx, call_id: call_id} do
      instruction = %Jido.Instruction{
        action: :trm_llm_result,
        params: %{
          call_id: call_id,
          result: {:ok, %{text: "The answer is 4"}},
          phase: :reasoning
        }
      }

      {agent, _} = TRM.cmd(agent, [instruction], ctx)

      state = State.get(agent, %{})
      assert state[:status] == :supervising
      assert state[:current_answer] == "The answer is 4"
    end
  end

  describe "cmd/3 through full TRM cycle" do
    setup do
      agent = build_test_agent()
      ctx = build_ctx(max_supervision_steps: 2, act_threshold: 0.99)
      {agent, _} = TRM.init(agent, ctx)
      {:ok, agent: agent, ctx: ctx}
    end

    test "completes full reason-supervise-improve cycle", %{agent: agent, ctx: ctx} do
      # 1. Start
      start_instr = %Jido.Instruction{
        action: :trm_start,
        params: %{prompt: "What is 2+2?"}
      }

      {agent, [reason_dir]} = TRM.cmd(agent, [start_instr], ctx)
      assert reason_dir.metadata.phase == :reasoning

      # 2. Reasoning result -> Supervise
      reasoning_instr = %Jido.Instruction{
        action: :trm_llm_result,
        params: %{
          call_id: reason_dir.id,
          result: {:ok, %{text: "The answer is 4"}},
          phase: :reasoning
        }
      }

      {agent, [supervise_dir]} = TRM.cmd(agent, [reasoning_instr], ctx)
      assert supervise_dir.metadata.phase == :supervising

      # 3. Supervision result -> Improve
      supervision_instr = %Jido.Instruction{
        action: :trm_llm_result,
        params: %{
          call_id: supervise_dir.id,
          result: {:ok, %{text: "Score: 0.6. Needs more detail."}},
          phase: :supervising
        }
      }

      {agent, [improve_dir]} = TRM.cmd(agent, [supervision_instr], ctx)
      assert improve_dir.metadata.phase == :improving

      # 4. Improvement result -> loops back to reasoning (step 2 < max_steps 2)
      improvement_instr = %Jido.Instruction{
        action: :trm_llm_result,
        params: %{
          call_id: improve_dir.id,
          result: {:ok, %{text: "2+2=4 because adding two and two gives four."}},
          phase: :improving
        }
      }

      {agent, directives} = TRM.cmd(agent, [improvement_instr], ctx)

      state = State.get(agent, %{})

      # Should either continue or complete based on step count
      if state[:status] == :reasoning do
        assert length(directives) == 1
        assert hd(directives).metadata.phase == :reasoning
      else
        assert state[:status] == :completed
        assert directives == []
      end
    end
  end

  describe "snapshot/2" do
    test "returns idle status when not started" do
      agent = build_test_agent()
      ctx = build_ctx()
      {agent, _} = TRM.init(agent, ctx)

      snapshot = TRM.snapshot(agent, ctx)

      assert snapshot.status == :idle
      assert snapshot.done? == false
      assert snapshot.result == nil
    end

    test "returns running status when in progress" do
      agent = build_test_agent()
      ctx = build_ctx()
      {agent, _} = TRM.init(agent, ctx)

      # Start reasoning
      instruction = %Jido.Instruction{
        action: :trm_start,
        params: %{prompt: "Test question"}
      }

      {agent, _} = TRM.cmd(agent, [instruction], ctx)
      snapshot = TRM.snapshot(agent, ctx)

      assert snapshot.status == :running
      assert snapshot.done? == false
      assert snapshot.details.phase == :reasoning
      assert snapshot.details.supervision_step == 1
    end

    test "returns success status when completed" do
      agent = build_test_agent()
      ctx = build_ctx()
      {agent, _} = TRM.init(agent, ctx)

      # Manually set completed state
      state =
        State.get(agent, %{})
        |> Map.put(:status, :completed)
        |> Map.put(:result, "Final answer")

      agent = State.put(agent, state)

      snapshot = TRM.snapshot(agent, ctx)

      assert snapshot.status == :success
      assert snapshot.done? == true
      assert snapshot.result == "Final answer"
    end

    test "returns failure status on error" do
      agent = build_test_agent()
      ctx = build_ctx()
      {agent, _} = TRM.init(agent, ctx)

      # Manually set error state
      state =
        State.get(agent, %{})
        |> Map.put(:status, :error)

      agent = State.put(agent, state)

      snapshot = TRM.snapshot(agent, ctx)

      assert snapshot.status == :failure
      assert snapshot.done? == true
    end

    test "includes details in snapshot" do
      agent = build_test_agent()
      ctx = build_ctx()
      {agent, _} = TRM.init(agent, ctx)

      # Set up some state
      state =
        State.get(agent, %{})
        |> Map.put(:status, :supervising)
        |> Map.put(:supervision_step, 2)
        |> Map.put(:max_supervision_steps, 5)
        |> Map.put(:act_threshold, 0.9)
        |> Map.put(:best_score, 0.7)
        |> Map.put(:answer_history, ["answer1", "answer2"])

      agent = State.put(agent, state)

      snapshot = TRM.snapshot(agent, ctx)

      assert snapshot.details.supervision_step == 2
      assert snapshot.details.max_supervision_steps == 5
      assert snapshot.details.act_threshold == 0.9
      assert snapshot.details.best_score == 0.7
      assert snapshot.details.answer_count == 2
    end
  end

  describe "public API functions" do
    setup do
      agent = build_test_agent()
      ctx = build_ctx()
      {agent, _} = TRM.init(agent, ctx)
      {:ok, agent: agent}
    end

    test "get_answer_history/1 returns empty list initially", %{agent: agent} do
      assert TRM.get_answer_history(agent) == []
    end

    test "get_answer_history/1 returns history after updates", %{agent: agent} do
      state =
        State.get(agent, %{})
        |> Map.put(:answer_history, ["first", "second", "third"])

      agent = State.put(agent, state)

      assert TRM.get_answer_history(agent) == ["first", "second", "third"]
    end

    test "get_current_answer/1 returns nil initially", %{agent: agent} do
      assert TRM.get_current_answer(agent) == nil
    end

    test "get_current_answer/1 returns current answer", %{agent: agent} do
      state =
        State.get(agent, %{})
        |> Map.put(:current_answer, "The answer is 42")

      agent = State.put(agent, state)

      assert TRM.get_current_answer(agent) == "The answer is 42"
    end

    test "get_confidence/1 returns 0.0 initially", %{agent: agent} do
      assert TRM.get_confidence(agent) == 0.0
    end

    test "get_confidence/1 returns confidence from latent state", %{agent: agent} do
      state =
        State.get(agent, %{})
        |> Map.put(:latent_state, %{confidence_score: 0.85, reasoning_trace: []})

      agent = State.put(agent, state)

      assert TRM.get_confidence(agent) == 0.85
    end

    test "get_supervision_step/1 returns 0 initially", %{agent: agent} do
      assert TRM.get_supervision_step(agent) == 0
    end

    test "get_supervision_step/1 returns current step", %{agent: agent} do
      state =
        State.get(agent, %{})
        |> Map.put(:supervision_step, 3)

      agent = State.put(agent, state)

      assert TRM.get_supervision_step(agent) == 3
    end

    test "get_best_answer/1 returns nil initially", %{agent: agent} do
      assert TRM.get_best_answer(agent) == nil
    end

    test "get_best_answer/1 returns best answer", %{agent: agent} do
      state =
        State.get(agent, %{})
        |> Map.put(:best_answer, "Best answer so far")

      agent = State.put(agent, state)

      assert TRM.get_best_answer(agent) == "Best answer so far"
    end

    test "get_best_score/1 returns 0.0 initially", %{agent: agent} do
      assert TRM.get_best_score(agent) == 0.0
    end

    test "get_best_score/1 returns best score", %{agent: agent} do
      state =
        State.get(agent, %{})
        |> Map.put(:best_score, 0.92)

      agent = State.put(agent, state)

      assert TRM.get_best_score(agent) == 0.92
    end
  end

  describe "default prompts" do
    test "default_reasoning_prompt/0 returns reasoning prompt" do
      prompt = TRM.default_reasoning_prompt()

      assert is_binary(prompt)
      assert prompt =~ "reasoning"
    end

    test "default_supervision_prompt/0 returns supervision prompt" do
      prompt = TRM.default_supervision_prompt()

      assert is_binary(prompt)
      assert prompt =~ "evaluator"
    end

    test "default_improvement_prompt/0 returns improvement prompt" do
      prompt = TRM.default_improvement_prompt()

      assert is_binary(prompt)
      assert prompt =~ "improve"
    end
  end

  describe "cmd/3 with llm_partial instruction" do
    setup do
      agent = build_test_agent()
      ctx = build_ctx()
      {agent, _} = TRM.init(agent, ctx)

      # Start reasoning
      start_instr = %Jido.Instruction{
        action: :trm_start,
        params: %{prompt: "What is AI?"}
      }

      {agent, [directive]} = TRM.cmd(agent, [start_instr], ctx)
      call_id = directive.id

      {:ok, agent: agent, ctx: ctx, call_id: call_id}
    end

    test "processes streaming partial", %{agent: agent, ctx: ctx, call_id: call_id} do
      instruction = %Jido.Instruction{
        action: :trm_llm_partial,
        params: %{
          call_id: call_id,
          delta: "Hello ",
          chunk_type: :content
        }
      }

      {agent, directives} = TRM.cmd(agent, [instruction], ctx)

      # Partials don't generate directives
      assert directives == []

      # Check streaming text was updated
      state = State.get(agent, %{})
      assert state[:streaming_text] == "Hello "
    end

    test "accumulates multiple partials", %{agent: agent, ctx: ctx, call_id: call_id} do
      instr1 = %Jido.Instruction{
        action: :trm_llm_partial,
        params: %{call_id: call_id, delta: "Hello ", chunk_type: :content}
      }

      instr2 = %Jido.Instruction{
        action: :trm_llm_partial,
        params: %{call_id: call_id, delta: "world!", chunk_type: :content}
      }

      {agent, _} = TRM.cmd(agent, [instr1], ctx)
      {agent, _} = TRM.cmd(agent, [instr2], ctx)

      state = State.get(agent, %{})
      assert state[:streaming_text] == "Hello world!"
    end
  end

  describe "directive context includes proper prompts" do
    test "reasoning directive includes question and prompts" do
      agent = build_test_agent()
      ctx = build_ctx()
      {agent, _} = TRM.init(agent, ctx)

      instruction = %Jido.Instruction{
        action: :trm_start,
        params: %{prompt: "What is the meaning of life?"}
      }

      {_agent, [directive]} = TRM.cmd(agent, [instruction], ctx)

      # Check directive has proper structure
      assert directive.model == "anthropic:claude-haiku-4-5"
      assert length(directive.context) >= 2

      # Find user message
      user_msg = Enum.find(directive.context, &(&1.role == :user))
      assert user_msg != nil

      # Content can be a string or list of content parts
      content_text =
        case user_msg.content do
          content when is_binary(content) ->
            content

          content when is_list(content) ->
            content
            |> Enum.map_join(" ", fn
              %{text: text} -> text
              part -> inspect(part)
            end)
        end

      assert content_text =~ "What is the meaning of life?"
    end
  end

  describe "unknown instructions" do
    test "ignores unknown actions" do
      agent = build_test_agent()
      ctx = build_ctx()
      {agent, _} = TRM.init(agent, ctx)

      instruction = %Jido.Instruction{
        action: :unknown_action,
        params: %{foo: "bar"}
      }

      {agent, directives} = TRM.cmd(agent, [instruction], ctx)

      assert directives == []
      state = State.get(agent, %{})
      assert state[:status] == :idle
    end
  end
end
