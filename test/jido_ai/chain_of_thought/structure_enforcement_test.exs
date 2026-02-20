defmodule Jido.AI.Reasoning.ChainOfThought.StructureEnforcementTest do
  use ExUnit.Case, async: true

  @forbidden_globs [
    "lib/jido_ai/strategies/chain_of_thought.ex",
    "lib/jido_ai/strategies/cot_worker.ex",
    "lib/jido_ai/strategies/chain_of_thought/**/*.ex",
    "lib/jido_ai/reasoning/strategies/chain_of_thought.ex",
    "lib/jido_ai/reasoning/workers/cot.ex",
    "lib/jido_ai/agents/internal/cot_worker_agent.ex",
    "lib/jido_ai/cli/adapters/cot.ex"
  ]

  defp legacy_namespace_patterns do
    [
      ~r/Jido\.AI\.Strategies\.ChainOfThought(\b|\.)/,
      ~r/Jido\.AI\.Strategies\.CoTWorker(\b|\.)/,
      ~r/Jido\.AI\.Reasoning\.Strategies\.ChainOfThought(\b|\.)/,
      ~r/Jido\.AI\.Reasoning\.Workers\.CoT(\b|\.)/,
      ~r/Jido\.AI\.Agents\.Internal\.CoTWorkerAgent(\b|\.)/,
      ~r/Jido\.AI\.ChainOfThought\.Machine(\b|\.)/,
      ~r/Jido\.AI\.CLI\.Adapters\.CoT(\b|\.)/
    ]
  end

  test "legacy CoT file locations are removed" do
    leftovers =
      @forbidden_globs
      |> Enum.flat_map(&Path.wildcard/1)
      |> Enum.uniq()
      |> Enum.sort()

    assert leftovers == [],
           "expected CoT implementation to be consolidated under lib/jido_ai/reasoning/chain_of_thought/, found legacy files: #{inspect(leftovers)}"
  end

  test "legacy CoT namespaces do not appear in source tree" do
    offenders =
      "lib/**/*.ex"
      |> Path.wildcard()
      |> Enum.filter(fn file ->
        content = File.read!(file)
        Enum.any?(legacy_namespace_patterns(), &Regex.match?(&1, content))
      end)

    assert offenders == [],
           "expected no legacy CoT namespaces in source tree, found: #{inspect(offenders)}"
  end
end
