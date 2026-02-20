defmodule Jido.AI.StableSmokeTest do
  use ExUnit.Case, async: true

  @moduletag :stable_smoke
  @moduletag :unit

  test "backlog scaffold files exist" do
    files = [
      "specs/stories/00_traceability_matrix.md",
      "specs/stories/01_ops_examples_core.md",
      "specs/stories/02_skills_runtime_cli.md",
      "specs/stories/03_strategies.md",
      "specs/stories/04_plugins.md",
      "specs/stories/05_actions.md",
      "specs/stories/06_quality.md"
    ]

    Enum.each(files, fn file ->
      assert File.exists?(file), "expected #{file} to exist"
    end)
  end

  test "weather strategy overview includes cod parity" do
    agents = Jido.AI.Examples.Weather.Overview.agents()

    assert Map.has_key?(agents, :cod)
    assert agents.cod == Jido.AI.Examples.Weather.CoDAgent
    assert map_size(agents) == 8
  end

  test "mix aliases expose precommit and fast test gate" do
    aliases = Mix.Project.config()[:aliases] || []

    assert Keyword.has_key?(aliases, :precommit)
    assert Keyword.has_key?(aliases, :"test.fast")
  end
end
