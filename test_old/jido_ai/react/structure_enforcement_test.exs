defmodule Jido.AI.Reasoning.ReAct.StructureEnforcementTest do
  use ExUnit.Case, async: true

  @forbidden_globs [
    "lib/jido_ai/actions/react/*.ex",
    "lib/jido_ai/cli/adapters/react.ex",
    "lib/jido_ai/signals/react_event.ex",
    "lib/jido_ai/reasoning/legacy/react*.ex",
    "lib/jido_ai/reasoning/legacy/react/**/*.ex",
    "lib/jido_ai/reasoning/legacy/strategies/react*.ex",
    "lib/jido_ai/reasoning/legacy/agents/internal/react_worker_agent.ex",
    "lib/jido_ai/reasoning/strategies/react.ex",
    "lib/jido_ai/reasoning/workers/react.ex"
  ]

  defp legacy_namespace_patterns do
    [
      ~r/Jido\.AI\.ReAct(\b|\.)/,
      ~r/Jido\.AI\.Strategies\.ReAct(\b|\.)/,
      ~r/Jido\.AI\.Actions\.ReAct(\b|\.)/,
      ~r/Jido\.AI\.Signal\.ReactEvent(\b|\.)/,
      ~r/Jido\.AI\.CLI\.Adapters\.ReAct(\b|\.)/,
      ~r/Jido\.AI\.Agents\.Internal\.ReActWorkerAgent(\b|\.)/,
      ~r/Jido\.AI\.Reasoning\.Strategies\.ReAct(\b|\.)/,
      ~r/Jido\.AI\.Reasoning\.Workers\.ReAct(\b|\.)/
    ]
  end

  test "legacy ReAct file locations are removed" do
    leftovers =
      @forbidden_globs
      |> Enum.flat_map(&Path.wildcard/1)
      |> Enum.uniq()
      |> Enum.sort()

    assert leftovers == [],
           "expected ReAct implementation to be consolidated under lib/jido_ai/reasoning/react/, found legacy files: #{inspect(leftovers)}"
  end

  test "legacy namespaces do not appear in source tree" do
    offenders =
      "lib/**/*.ex"
      |> Path.wildcard()
      |> Enum.filter(fn file ->
        content = File.read!(file)
        Enum.any?(legacy_namespace_patterns(), &Regex.match?(&1, content))
      end)

    assert offenders == [],
           "expected no legacy ReAct namespaces in source tree, found: #{inspect(offenders)}"
  end
end
