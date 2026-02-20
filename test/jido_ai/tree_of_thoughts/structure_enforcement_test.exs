defmodule Jido.AI.Reasoning.TreeOfThoughts.StructureEnforcementTest do
  use ExUnit.Case, async: true

  @forbidden_globs [
    "lib/jido_ai/strategies/tree_of_thoughts.ex",
    "lib/jido_ai/strategies/tree_of_thoughts/**/*.ex",
    "lib/jido_ai/reasoning/strategies/tree_of_thoughts.ex",
    "lib/jido_ai/cli/adapters/tot.ex"
  ]

  defp legacy_namespace_patterns do
    [
      ~r/Jido\.AI\.Strategies\.TreeOfThoughts(\b|\.)/,
      ~r/Jido\.AI\.Reasoning\.Strategies\.TreeOfThoughts(\b|\.)/,
      ~r/Jido\.AI\.TreeOfThoughts\.Machine(\b|\.)/,
      ~r/Jido\.AI\.CLI\.Adapters\.ToT(\b|\.)/
    ]
  end

  test "legacy ToT file locations are removed" do
    leftovers =
      @forbidden_globs
      |> Enum.flat_map(&Path.wildcard/1)
      |> Enum.uniq()
      |> Enum.sort()

    assert leftovers == [],
           "expected ToT implementation to be consolidated under lib/jido_ai/reasoning/tree_of_thoughts/, found legacy files: #{inspect(leftovers)}"
  end

  test "legacy ToT namespaces do not appear in source tree" do
    offenders =
      "lib/**/*.ex"
      |> Path.wildcard()
      |> Enum.filter(fn file ->
        content = File.read!(file)
        Enum.any?(legacy_namespace_patterns(), &Regex.match?(&1, content))
      end)

    assert offenders == [],
           "expected no legacy ToT namespaces in source tree, found: #{inspect(offenders)}"
  end
end
