defmodule Jido.AI.Reasoning.GraphOfThoughts.StructureEnforcementTest do
  use ExUnit.Case, async: true

  @forbidden_globs [
    "lib/jido_ai/strategies/graph_of_thoughts.ex",
    "lib/jido_ai/strategies/graph_of_thoughts/**/*.ex",
    "lib/jido_ai/reasoning/strategies/graph_of_thoughts.ex",
    "lib/jido_ai/cli/adapters/got.ex"
  ]

  @legacy_namespace_patterns [
    ~r/Jido\.AI\.Strategies\.GraphOfThoughts(\b|\.)/,
    ~r/Jido\.AI\.Reasoning\.Strategies\.GraphOfThoughts(\b|\.)/,
    ~r/Jido\.AI\.GraphOfThoughts\.Machine(\b|\.)/,
    ~r/Jido\.AI\.CLI\.Adapters\.GoT(\b|\.)/
  ]

  test "legacy GoT file locations are removed" do
    leftovers =
      @forbidden_globs
      |> Enum.flat_map(&Path.wildcard/1)
      |> Enum.uniq()
      |> Enum.sort()

    assert leftovers == [],
           "expected GoT implementation to be consolidated under lib/jido_ai/reasoning/graph_of_thoughts/, found legacy files: #{inspect(leftovers)}"
  end

  test "legacy GoT namespaces do not appear in source tree" do
    offenders =
      "lib/**/*.ex"
      |> Path.wildcard()
      |> Enum.filter(fn file ->
        content = File.read!(file)
        Enum.any?(@legacy_namespace_patterns, &Regex.match?(&1, content))
      end)

    assert offenders == [],
           "expected no legacy GoT namespaces in source tree, found: #{inspect(offenders)}"
  end
end
