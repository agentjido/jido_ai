defmodule Jido.AI.Reasoning.TRM.StructureEnforcementTest do
  use ExUnit.Case, async: true

  @forbidden_globs [
    "lib/jido_ai/strategies/trm.ex",
    "lib/jido_ai/strategies/trm/**/*.ex",
    "lib/jido_ai/reasoning/strategies/trm.ex",
    "lib/jido_ai/cli/adapters/trm.ex"
  ]

  @legacy_namespace_patterns [
    ~r/Jido\.AI\.Strategies\.TRM(\b|\.)/,
    ~r/Jido\.AI\.Reasoning\.Strategies\.TRM(\b|\.)/,
    ~r/Jido\.AI\.TRM\.Machine(\b|\.)/,
    ~r/Jido\.AI\.TRM\.ACT(\b|\.)/,
    ~r/Jido\.AI\.TRM\.Helpers(\b|\.)/,
    ~r/Jido\.AI\.TRM\.Reasoning(\b|\.)/,
    ~r/Jido\.AI\.TRM\.Supervision(\b|\.)/,
    ~r/Jido\.AI\.CLI\.Adapters\.TRM(\b|\.)/
  ]

  test "legacy TRM file locations are removed" do
    leftovers =
      @forbidden_globs
      |> Enum.flat_map(&Path.wildcard/1)
      |> Enum.uniq()
      |> Enum.sort()

    assert leftovers == [],
           "expected TRM implementation to be consolidated under lib/jido_ai/reasoning/trm/, found legacy files: #{inspect(leftovers)}"
  end

  test "legacy TRM namespaces do not appear in source tree" do
    offenders =
      "lib/**/*.ex"
      |> Path.wildcard()
      |> Enum.filter(fn file ->
        content = File.read!(file)
        Enum.any?(@legacy_namespace_patterns, &Regex.match?(&1, content))
      end)

    assert offenders == [],
           "expected no legacy TRM namespaces in source tree, found: #{inspect(offenders)}"
  end
end
