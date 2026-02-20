defmodule Jido.AI.Reasoning.Adaptive.StructureEnforcementTest do
  use ExUnit.Case, async: true

  @forbidden_globs [
    "lib/jido_ai/strategies/adaptive.ex",
    "lib/jido_ai/reasoning/strategies/adaptive.ex",
    "lib/jido_ai/cli/adapters/adaptive.ex"
  ]

  defp legacy_namespace_patterns do
    [
      ~r/Jido\.AI\.Strategies\.Adaptive(\b|\.)/,
      ~r/Jido\.AI\.Reasoning\.Strategies\.Adaptive(\b|\.)/,
      ~r/Jido\.AI\.CLI\.Adapters\.Adaptive(\b|\.)/
    ]
  end

  test "legacy Adaptive file locations are removed" do
    leftovers =
      @forbidden_globs
      |> Enum.flat_map(&Path.wildcard/1)
      |> Enum.uniq()
      |> Enum.sort()

    assert leftovers == [],
           "expected Adaptive implementation to be consolidated under lib/jido_ai/reasoning/adaptive/, found legacy files: #{inspect(leftovers)}"
  end

  test "legacy Adaptive namespaces do not appear in source tree" do
    offenders =
      "lib/**/*.ex"
      |> Path.wildcard()
      |> Enum.filter(fn file ->
        content = File.read!(file)
        Enum.any?(legacy_namespace_patterns(), &Regex.match?(&1, content))
      end)

    assert offenders == [],
           "expected no legacy Adaptive namespaces in source tree, found: #{inspect(offenders)}"
  end
end
