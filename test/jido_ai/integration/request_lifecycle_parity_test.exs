defmodule Jido.AI.Integration.RequestLifecycleParityTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Directive
  alias Jido.AI.Strategies.{Adaptive, ChainOfThought, GraphOfThoughts, TRM, TreeOfThoughts}

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
                 Map.get(directive, :id) == "req_1"
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

  defp init_agent(strategy, strategy_opts) do
    agent = %Jido.Agent{id: "agent-#{strategy}", name: "test", state: %{}}
    {agent, _directives} = strategy.init(agent, %{strategy_opts: strategy_opts})
    agent
  end
end
