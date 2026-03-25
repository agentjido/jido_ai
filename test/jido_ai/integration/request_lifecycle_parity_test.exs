defmodule Jido.AI.Integration.RequestLifecycleParityTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Directive
  alias Jido.AI.Observe
  alias Jido.AI.Reasoning.AlgorithmOfThoughts.Strategy, as: AlgorithmOfThoughts
  alias Jido.AI.Reasoning.ChainOfThought.Strategy, as: ChainOfThought
  alias Jido.AI.Reasoning.Adaptive.Strategy, as: Adaptive
  alias Jido.AI.Reasoning.GraphOfThoughts.Strategy, as: GraphOfThoughts
  alias Jido.AI.Reasoning.TRM.Strategy, as: TRM
  alias Jido.AI.Reasoning.TreeOfThoughts.Strategy, as: TreeOfThoughts

  @strategies [
    {AlgorithmOfThoughts, []},
    {ChainOfThought, []},
    {TreeOfThoughts, []},
    {GraphOfThoughts, []},
    {TRM, []},
    {Adaptive, [default_strategy: :cot, available_strategies: [:cot], tools: []]}
  ]

  describe "busy rejection closes request lifecycle with request-scoped error" do
    for {strategy, opts} <- @strategies do
      test "#{strategy} rejects second concurrent request with request_id correlation" do
        strategy = unquote(strategy)
        opts = unquote(opts)

        agent = init_agent(strategy, opts)

        first_instruction = %Jido.Instruction{
          action: strategy.start_action(),
          params: %{prompt: "first", request_id: "req_1"}
        }

        {agent, first_directives} = strategy.cmd(agent, [first_instruction], %{})

        assert Enum.any?(first_directives, fn directive ->
                 Map.get(directive, :id) == "req_1" or
                   match?(%Jido.Agent.Directive.SpawnAgent{tag: :cot_worker}, directive)
               end)

        second_instruction = %Jido.Instruction{
          action: strategy.start_action(),
          params: %{prompt: "second", request_id: "req_2"}
        }

        {_agent, second_directives} = strategy.cmd(agent, [second_instruction], %{})

        assert [%Directive.EmitRequestError{} = request_error] = second_directives
        assert request_error.request_id == "req_2"
        assert request_error.reason == :busy
      end
    end
  end

  describe "happy path keeps lifecycle open for accepted requests" do
    for {strategy, opts} <- @strategies do
      test "#{strategy} accepts first request without immediate rejection" do
        strategy = unquote(strategy)
        opts = unquote(opts)

        agent = init_agent(strategy, opts)

        instruction = %Jido.Instruction{
          action: strategy.start_action(),
          params: %{prompt: "first", request_id: "req_happy"}
        }

        {agent, directives} = strategy.cmd(agent, [instruction], %{})
        refute Enum.any?(directives, &match?(%Directive.EmitRequestError{}, &1))

        snapshot = strategy.snapshot(agent, %{})
        refute snapshot.done?
        assert snapshot.status == :running
      end
    end
  end

  describe "ChainOfThought lifecycle completion and signal parity" do
    test "worker request_started and request_completed events emit canonical request signals" do
      request_id = "req_lifecycle_ok"
      agent = init_agent(ChainOfThought, [])

      start_instruction = %Jido.Instruction{
        action: ChainOfThought.start_action(),
        params: %{prompt: "first", request_id: request_id}
      }

      {agent, _directives} = ChainOfThought.cmd(agent, [start_instruction], %{})
      flush_signal_casts()

      started_instruction = %Jido.Instruction{
        action: :cot_worker_event,
        params: %{
          request_id: request_id,
          event: %{
            id: "evt_started",
            seq: 1,
            at_ms: 1_700_000_000_000,
            run_id: request_id,
            request_id: request_id,
            iteration: 1,
            kind: :request_started,
            llm_call_id: nil,
            tool_call_id: nil,
            tool_name: nil,
            data: %{query: "first"}
          }
        }
      }

      {agent, _directives} = ChainOfThought.cmd(agent, [started_instruction], %{})

      assert_receive {:"$gen_cast", {:signal, request_started}}, 200
      assert request_started.type == "ai.request.started"
      assert request_started.data.request_id == request_id
      assert request_started.data.query == "first"

      completed_instruction = %Jido.Instruction{
        action: :cot_worker_event,
        params: %{
          request_id: request_id,
          event: %{
            id: "evt_completed",
            seq: 2,
            at_ms: 1_700_000_000_100,
            run_id: request_id,
            request_id: request_id,
            iteration: 1,
            kind: :request_completed,
            llm_call_id: "cot_call_1",
            tool_call_id: nil,
            tool_name: nil,
            data: %{
              result: "final answer",
              termination_reason: :success,
              usage: %{input_tokens: 10, output_tokens: 5}
            }
          }
        }
      }

      {completed_agent, _directives} = ChainOfThought.cmd(agent, [completed_instruction], %{})

      assert_receive {:"$gen_cast", {:signal, request_completed}}, 200
      assert request_completed.type == "ai.request.completed"
      assert request_completed.data.request_id == request_id
      assert request_completed.data.result == "final answer"

      snapshot = ChainOfThought.snapshot(completed_agent, %{})
      assert snapshot.done?
      assert snapshot.status == :success
      assert snapshot.result == "final answer"
    end

    test "worker request_failed event emits ai.request.failed and closes lifecycle" do
      request_id = "req_lifecycle_failed"
      agent = init_agent(ChainOfThought, [])

      start_instruction = %Jido.Instruction{
        action: ChainOfThought.start_action(),
        params: %{prompt: "first", request_id: request_id}
      }

      {agent, _directives} = ChainOfThought.cmd(agent, [start_instruction], %{})
      flush_signal_casts()

      failed_instruction = %Jido.Instruction{
        action: :cot_worker_event,
        params: %{
          request_id: request_id,
          event: %{
            id: "evt_failed",
            seq: 2,
            at_ms: 1_700_000_000_100,
            run_id: request_id,
            request_id: request_id,
            iteration: 1,
            kind: :request_failed,
            llm_call_id: "cot_call_1",
            tool_call_id: nil,
            tool_name: nil,
            data: %{error: {:provider_error, :overloaded}}
          }
        }
      }

      {failed_agent, _directives} = ChainOfThought.cmd(agent, [failed_instruction], %{})

      assert_receive {:"$gen_cast", {:signal, request_failed}}, 200
      assert request_failed.type == "ai.request.failed"
      assert request_failed.data.request_id == request_id
      assert request_failed.data.error == {:provider_error, :overloaded}

      snapshot = ChainOfThought.snapshot(failed_agent, %{})
      assert snapshot.done?
      assert snapshot.status == :failure
      assert snapshot.result =~ "provider_error"
    end
  end

  describe "non-delegated strategy request lifecycle parity" do
    test "AoT emits request started/completed signals and request telemetry" do
      request_id = "req_aot_lifecycle"
      handler_id = attach_request_handler(self(), [Observe.request(:start), Observe.request(:complete)])
      on_exit(fn -> :telemetry.detach(handler_id) end)

      agent = init_agent(AlgorithmOfThoughts, [])

      start_instruction = %Jido.Instruction{
        action: AlgorithmOfThoughts.start_action(),
        params: %{prompt: "Solve 4,4,6,8 to get 24", request_id: request_id}
      }

      {agent, [%Directive.LLMStream{id: call_id}]} = AlgorithmOfThoughts.cmd(agent, [start_instruction], %{})

      assert_receive {:"$gen_cast", {:signal, request_started}}, 200
      assert request_started.type == "ai.request.started"
      assert request_started.data.request_id == request_id
      assert_receive {:telemetry_event, [:jido, :ai, :request, :start], _, %{request_id: ^request_id}}, 200

      response = """
      Trying a promising first operation:
      1. 8 - 6 : (4, 4, 2)
      - 4 + 2 : (6, 4) 24 = 6 * 4 -> found it!
      Backtracking the solution:
      Step 1: 8 - 6 = 2
      Step 2: 4 + 2 = 6
      Step 3: 6 * 4 = 24
      answer: (4 + (8 - 6)) * 4 = 24
      """

      complete_instruction = %Jido.Instruction{
        action: AlgorithmOfThoughts.llm_result_action(),
        params: %{call_id: call_id, result: {:ok, %{text: response, usage: %{input_tokens: 4, output_tokens: 9}}}}
      }

      {_agent, []} = AlgorithmOfThoughts.cmd(agent, [complete_instruction], %{})

      assert_receive {:"$gen_cast", {:signal, request_completed}}, 200
      assert request_completed.type == "ai.request.completed"
      assert request_completed.data.request_id == request_id
      assert request_completed.data.result.answer == "(4 + (8 - 6)) * 4 = 24"

      assert_receive {:telemetry_event, [:jido, :ai, :request, :complete], measurements, metadata}, 200
      assert metadata.request_id == request_id
      assert measurements.total_tokens == 13
    end

    test "GoT emits request started/completed signals and request telemetry" do
      request_id = "req_got_complete"
      handler_id = attach_request_handler(self(), [Observe.request(:start), Observe.request(:complete)])
      on_exit(fn -> :telemetry.detach(handler_id) end)

      agent = init_agent(GraphOfThoughts, max_nodes: 2)

      start_instruction = %Jido.Instruction{
        action: GraphOfThoughts.start_action(),
        params: %{prompt: "Compare two ideas", request_id: request_id}
      }

      {agent, [%Directive.LLMStream{id: call_id}]} = GraphOfThoughts.cmd(agent, [start_instruction], %{})

      assert_receive {:"$gen_cast", {:signal, request_started}}, 200
      assert request_started.type == "ai.request.started"
      assert request_started.data.request_id == request_id
      assert_receive {:telemetry_event, [:jido, :ai, :request, :start], _, %{request_id: ^request_id}}, 200

      complete_instruction = %Jido.Instruction{
        action: GraphOfThoughts.llm_result_action(),
        params: %{
          call_id: call_id,
          result: {:ok, %{text: "Thought 1: compare tradeoffs", usage: %{input_tokens: 2, output_tokens: 3}}}
        }
      }

      {_agent, []} = GraphOfThoughts.cmd(agent, [complete_instruction], %{})

      assert_receive {:"$gen_cast", {:signal, request_completed}}, 200
      assert request_completed.type == "ai.request.completed"
      assert request_completed.data.request_id == request_id
      assert request_completed.data.result == "Thought 1: compare tradeoffs"

      assert_receive {:telemetry_event, [:jido, :ai, :request, :complete], measurements, metadata}, 200
      assert metadata.request_id == request_id
      assert measurements.total_tokens == 5
    end

    test "GoT emits request failed signal and request telemetry on llm error" do
      request_id = "req_got_failed"
      handler_id = attach_request_handler(self(), [Observe.request(:failed)])
      on_exit(fn -> :telemetry.detach(handler_id) end)

      agent = init_agent(GraphOfThoughts, [])

      start_instruction = %Jido.Instruction{
        action: GraphOfThoughts.start_action(),
        params: %{prompt: "Analyze this", request_id: request_id}
      }

      {agent, [%Directive.LLMStream{id: call_id}]} = GraphOfThoughts.cmd(agent, [start_instruction], %{})
      flush_signal_casts()

      failed_instruction = %Jido.Instruction{
        action: GraphOfThoughts.llm_result_action(),
        params: %{call_id: call_id, result: {:error, :overloaded}}
      }

      {_agent, []} = GraphOfThoughts.cmd(agent, [failed_instruction], %{})

      assert_receive {:"$gen_cast", {:signal, request_failed}}, 200
      assert request_failed.type == "ai.request.failed"
      assert request_failed.data.request_id == request_id
      assert request_failed.data.error == {:error, :overloaded}

      assert_receive {:telemetry_event, [:jido, :ai, :request, :failed], _,
                      %{request_id: ^request_id, error_type: :overloaded}},
                     200
    end

    test "TRM emits request started/failed signals and request telemetry" do
      request_id = "req_trm_failed"
      handler_id = attach_request_handler(self(), [Observe.request(:start), Observe.request(:failed)])
      on_exit(fn -> :telemetry.detach(handler_id) end)

      agent = init_agent(TRM, [])

      start_instruction = %Jido.Instruction{
        action: TRM.start_action(),
        params: %{prompt: "What is 2+2?", request_id: request_id}
      }

      {agent, [%Directive.LLMStream{id: call_id}]} = TRM.cmd(agent, [start_instruction], %{})

      assert_receive {:"$gen_cast", {:signal, request_started}}, 200
      assert request_started.type == "ai.request.started"
      assert request_started.data.request_id == request_id
      assert_receive {:telemetry_event, [:jido, :ai, :request, :start], _, %{request_id: ^request_id}}, 200

      failed_instruction = %Jido.Instruction{
        action: TRM.llm_result_action(),
        params: %{call_id: call_id, result: {:error, :provider_down}, phase: :reasoning}
      }

      {_agent, []} = TRM.cmd(agent, [failed_instruction], %{})

      assert_receive {:"$gen_cast", {:signal, request_failed}}, 200
      assert request_failed.type == "ai.request.failed"
      assert request_failed.data.request_id == request_id
      assert request_failed.data.error == "Error: provider_down"

      assert_receive {:telemetry_event, [:jido, :ai, :request, :failed], _,
                      %{request_id: ^request_id, error_type: :provider_down}},
                     200
    end

    test "TRM emits request completed when max supervision steps are reached" do
      request_id = "req_trm_complete"
      handler_id = attach_request_handler(self(), [Observe.request(:complete)])
      on_exit(fn -> :telemetry.detach(handler_id) end)

      agent = init_agent(TRM, max_supervision_steps: 1, act_threshold: 0.99)

      start_instruction = %Jido.Instruction{
        action: TRM.start_action(),
        params: %{prompt: "What is 2+2?", request_id: request_id}
      }

      {agent, [%Directive.LLMStream{id: reasoning_call_id}]} = TRM.cmd(agent, [start_instruction], %{})
      flush_signal_casts()

      reasoning_instruction = %Jido.Instruction{
        action: TRM.llm_result_action(),
        params: %{call_id: reasoning_call_id, result: {:ok, %{text: "The answer is 4"}}, phase: :reasoning}
      }

      {agent, [%Directive.LLMStream{id: supervision_call_id}]} = TRM.cmd(agent, [reasoning_instruction], %{})

      supervision_instruction = %Jido.Instruction{
        action: TRM.llm_result_action(),
        params: %{
          call_id: supervision_call_id,
          result: {:ok, %{text: "Score: 0.7. Looks correct."}},
          phase: :supervising
        }
      }

      {agent, [%Directive.LLMStream{id: improvement_call_id}]} = TRM.cmd(agent, [supervision_instruction], %{})

      improvement_instruction = %Jido.Instruction{
        action: TRM.llm_result_action(),
        params: %{
          call_id: improvement_call_id,
          result:
            {:ok,
             %{text: "2 + 2 = 4 because adding two and two gives four.", usage: %{input_tokens: 4, output_tokens: 8}}},
          phase: :improving
        }
      }

      {_agent, []} = TRM.cmd(agent, [improvement_instruction], %{})

      assert_receive {:"$gen_cast", {:signal, request_completed}}, 200
      assert request_completed.type == "ai.request.completed"
      assert request_completed.data.request_id == request_id
      assert request_completed.data.result == "The answer is 4"

      assert_receive {:telemetry_event, [:jido, :ai, :request, :complete], measurements, %{request_id: ^request_id}},
                     200

      assert measurements.total_tokens == 12
    end
  end

  defp init_agent(strategy, strategy_opts) do
    agent = %Jido.Agent{id: "agent-#{strategy}", name: "test", state: %{}}
    {agent, _directives} = strategy.init(agent, %{strategy_opts: strategy_opts})
    agent
  end

  defp attach_request_handler(test_pid, events) do
    handler_id = "request-parity-handler-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach_many(
        handler_id,
        events,
        &__MODULE__.handle_telemetry/4,
        test_pid
      )

    handler_id
  end

  def handle_telemetry(event, measurements, metadata, test_pid) do
    send(test_pid, {:telemetry_event, event, measurements, metadata})
  end

  defp flush_signal_casts do
    receive do
      {:"$gen_cast", {:signal, _signal}} -> flush_signal_casts()
    after
      0 -> :ok
    end
  end
end
