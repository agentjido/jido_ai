defmodule Jido.AI.Reasoning.AlgorithmOfThoughts.StrategyTest do
  use ExUnit.Case, async: true

  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.AI.Reasoning.AlgorithmOfThoughts.Strategy, as: AlgorithmOfThoughts

  defp create_agent(opts \\ []) do
    %Jido.Agent{id: "test-agent", name: "test", state: %{}}
    |> then(fn agent ->
      ctx = %{strategy_opts: opts}
      {agent, []} = AlgorithmOfThoughts.init(agent, ctx)
      agent
    end)
  end

  describe "init/2" do
    test "initializes machine state and config" do
      agent = create_agent()
      state = StratState.get(agent, %{})

      assert state[:status] == :idle
      assert state[:config].model == "anthropic:claude-haiku-4-5"
      assert state[:config].profile == :standard
      assert state[:config].search_style == :dfs
      assert state[:config].temperature == 0.0
      assert state[:config].max_tokens == 2048
      assert state[:config].require_explicit_answer == true
    end

    test "accepts custom AoT options" do
      agent = create_agent(profile: :short, search_style: :bfs, max_tokens: 4096, temperature: 0.1)
      state = StratState.get(agent, %{})

      assert state[:config].profile == :short
      assert state[:config].search_style == :bfs
      assert state[:config].max_tokens == 4096
      assert state[:config].temperature == 0.1
    end
  end

  describe "action_spec/1" do
    test "returns specs for strategy actions" do
      assert AlgorithmOfThoughts.action_spec(:aot_start).name == "aot.start"
      assert AlgorithmOfThoughts.action_spec(:aot_llm_result).name == "aot.llm_result"
      assert AlgorithmOfThoughts.action_spec(:aot_llm_partial).name == "aot.llm_partial"
      assert AlgorithmOfThoughts.action_spec(:aot_request_error).name == "aot.request_error"
      assert is_nil(AlgorithmOfThoughts.action_spec(:unknown))
    end
  end

  describe "signal_routes/1" do
    test "routes expected AoT signals" do
      routes = Map.new(AlgorithmOfThoughts.signal_routes(%{}))

      assert routes["ai.aot.query"] == {:strategy_cmd, :aot_start}
      assert routes["ai.llm.response"] == {:strategy_cmd, :aot_llm_result}
      assert routes["ai.llm.delta"] == {:strategy_cmd, :aot_llm_partial}
      assert routes["ai.request.error"] == {:strategy_cmd, :aot_request_error}
    end
  end

  describe "cmd/3" do
    test "start instruction emits LLMStream directive" do
      agent = create_agent()

      instruction = %Jido.Instruction{action: :aot_start, params: %{prompt: "Solve this"}}
      {agent, directives} = AlgorithmOfThoughts.cmd(agent, [instruction], %{})

      state = StratState.get(agent, %{})
      assert state[:status] == :exploring
      assert state[:prompt] == "Solve this"
      assert length(directives) == 1
      assert hd(directives).__struct__ == Jido.AI.Directive.LLMStream
    end

    test "llm result instruction transitions to completed with parsed output" do
      agent = create_agent()

      {agent, _} =
        AlgorithmOfThoughts.cmd(agent, [%Jido.Instruction{action: :aot_start, params: %{prompt: "Solve"}}], %{})

      call_id = StratState.get(agent, %{})[:current_call_id]

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

      instruction =
        %Jido.Instruction{
          action: :aot_llm_result,
          params: %{call_id: call_id, result: {:ok, %{text: response, usage: %{input_tokens: 4, output_tokens: 9}}}}
        }

      {agent, []} = AlgorithmOfThoughts.cmd(agent, [instruction], %{})

      state = StratState.get(agent, %{})
      assert state[:status] == :completed
      assert state[:result][:answer] == "(4 + (8 - 6)) * 4 = 24"
      assert state[:result][:usage][:total_tokens] == 13
    end
  end

  describe "snapshot/2" do
    test "returns idle snapshot for new agent" do
      agent = create_agent()
      snapshot = AlgorithmOfThoughts.snapshot(agent, %{})

      assert snapshot.status == :idle
      assert snapshot.done? == false
    end

    test "returns running snapshot after start" do
      agent = create_agent(profile: :long)

      {agent, _} =
        AlgorithmOfThoughts.cmd(agent, [%Jido.Instruction{action: :aot_start, params: %{prompt: "Test"}}], %{})

      snapshot = AlgorithmOfThoughts.snapshot(agent, %{})
      assert snapshot.status == :running
      assert snapshot.done? == false
      assert snapshot.details[:profile] == :long
    end
  end

  describe "action helpers" do
    test "returns expected action atoms" do
      assert AlgorithmOfThoughts.start_action() == :aot_start
      assert AlgorithmOfThoughts.llm_result_action() == :aot_llm_result
      assert AlgorithmOfThoughts.llm_partial_action() == :aot_llm_partial
      assert AlgorithmOfThoughts.request_error_action() == :aot_request_error
    end
  end
end
