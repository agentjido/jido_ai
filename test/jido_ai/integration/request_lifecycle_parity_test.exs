defmodule Jido.AI.Integration.RequestLifecycleParityTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Directive
  alias Jido.AI.Reasoning.ChainOfThought.Strategy, as: ChainOfThought
  alias Jido.AI.Reasoning.Adaptive.Strategy, as: Adaptive
  alias Jido.AI.Reasoning.GraphOfThoughts.Strategy, as: GraphOfThoughts
  alias Jido.AI.Reasoning.TRM.Strategy, as: TRM
  alias Jido.AI.Reasoning.TreeOfThoughts.Strategy, as: TreeOfThoughts

  @strategies [
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

  defp init_agent(strategy, strategy_opts) do
    agent = %Jido.Agent{id: "agent-#{strategy}", name: "test", state: %{}}
    {agent, _directives} = strategy.init(agent, %{strategy_opts: strategy_opts})
    agent
  end

  defp flush_signal_casts do
    receive do
      {:"$gen_cast", {:signal, _signal}} -> flush_signal_casts()
    after
      0 -> :ok
    end
  end
end
