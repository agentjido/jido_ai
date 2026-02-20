defmodule Jido.AI.StableSmokeTest do
  use ExUnit.Case, async: true

  @moduletag :stable_smoke
  @moduletag :unit

  @required_story_sections [
    "Goal",
    "Scope",
    "Acceptance Criteria",
    "Stable Test Gate",
    "Docs Gate",
    "Example Gate",
    "Dependencies"
  ]

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

  test "story cards include the required section contract" do
    story_files = Path.wildcard("specs/stories/0[1-6]_*.md")

    Enum.each(story_files, fn file ->
      cards =
        file
        |> File.read!()
        |> parse_story_cards()

      assert cards != [], "expected #{file} to include at least one story card"

      Enum.each(cards, fn %{id: story_id, sections: sections} ->
        assert sections == @required_story_sections,
               "expected #{story_id} in #{file} to use required section headings"
      end)
    end)
  end

  test "traceability matrix includes one row per story id" do
    story_ids =
      "specs/stories/0[1-6]_*.md"
      |> Path.wildcard()
      |> Enum.flat_map(fn file ->
        file
        |> File.read!()
        |> extract_story_ids()
      end)
      |> Enum.uniq()
      |> Enum.sort()

    matrix_ids =
      "specs/stories/00_traceability_matrix.md"
      |> File.read!()
      |> extract_matrix_ids()

    assert matrix_ids == Enum.uniq(matrix_ids),
           "expected traceability rows to avoid duplicate story ids"

    assert Enum.sort(matrix_ids) == story_ids
  end

  test "loop usage text references the repository-local executable path" do
    loop_script = File.read!("ralph_wiggum_loop.sh")

    assert loop_script =~ "Usage: ./ralph_wiggum_loop.sh [options]"
    assert loop_script =~ "  ./ralph_wiggum_loop.sh --dry-run"
    assert loop_script =~ "  ./ralph_wiggum_loop.sh --start-at ST-OPS-001 --max 3"
    assert loop_script =~ "  ./ralph_wiggum_loop.sh --only ST-OPS-001 --no-push"
  end

  test "ops backlog story examples reference real repo paths" do
    ops_story = File.read!("specs/stories/01_ops_examples_core.md")

    Enum.each(
      ["specs/stories", "specs/stories/00_traceability_matrix.md", "ralph_wiggum_loop.sh"],
      fn path ->
        assert ops_story =~ "`#{path}`"
        assert File.exists?(path), "expected #{path} to exist"
      end
    )
  end

  test "weather strategy overview includes cod parity" do
    agents = Jido.AI.Examples.Weather.Overview.agents()

    assert Map.has_key?(agents, :cod)
    assert agents.cod == Jido.AI.Examples.Weather.CoDAgent
    assert map_size(agents) == 8
  end

  test "mix aliases expose the dual stable gate contract" do
    aliases = Mix.Project.config()[:aliases] || []

    assert Keyword.fetch!(aliases, :test) == "test --exclude flaky"

    assert Keyword.fetch!(aliases, :"test.fast") ==
             "cmd env MIX_ENV=test mix test --exclude flaky --only stable_smoke"

    precommit_steps = Keyword.fetch!(aliases, :precommit)
    assert is_list(precommit_steps)
    assert "test.fast" in precommit_steps
  end

  test "docs define dual gate behavior with runtime budgets and command sets" do
    contributing = File.read!("CONTRIBUTING.md")
    examples_index = File.read!("lib/examples/README.md")
    ops_story = File.read!("specs/stories/01_ops_examples_core.md")

    assert contributing =~ "Dual Stable Gates (One-Story Loop)"
    assert contributing =~ "Fast per-story gate"
    assert contributing =~ "Full checkpoint gate"
    assert contributing =~ "under 90 seconds"
    assert contributing =~ "under 10 minutes"
    assert contributing =~ "mix precommit"
    assert contributing =~ "mix test.fast"
    assert contributing =~ "mix test"

    assert examples_index =~ "Story Loop Gates"
    assert examples_index =~ "Fast per-story gate command set"
    assert examples_index =~ "Full checkpoint gate command set"
    assert examples_index =~ "under 90 seconds"
    assert examples_index =~ "under 10 minutes"
    assert examples_index =~ "mix precommit"
    assert examples_index =~ "mix test.fast"
    assert examples_index =~ "mix test"

    assert ops_story =~ "Loop runtime budgets are explicit"
    assert ops_story =~ "under 90 seconds"
    assert ops_story =~ "under 10 minutes"
    assert ops_story =~ "Fast per-story command set"
    assert ops_story =~ "mix precommit"
    assert ops_story =~ "mix test.fast"
    assert ops_story =~ "Full checkpoint command set"
    assert ops_story =~ "mix test"
  end

  defp parse_story_cards(markdown) do
    markdown
    |> String.split("\n")
    |> Enum.reduce([], fn line, cards ->
      cond do
        String.match?(line, ~r/^### (ST-[A-Z]+-[0-9]{3}) /) ->
          [id] = Regex.run(~r/^### (ST-[A-Z]+-[0-9]{3}) /, line, capture: :all_but_first)
          [%{id: id, sections: []} | cards]

        String.match?(line, ~r/^#### /) and cards != [] ->
          [card | rest] = cards
          section = String.replace_prefix(line, "#### ", "")
          [%{card | sections: card.sections ++ [section]} | rest]

        true ->
          cards
      end
    end)
    |> Enum.reverse()
  end

  defp extract_story_ids(markdown) do
    Regex.scan(~r/^### (ST-[A-Z]+-[0-9]{3}) /m, markdown, capture: :all_but_first)
    |> List.flatten()
  end

  defp extract_matrix_ids(markdown) do
    Regex.scan(~r/^\| (ST-[A-Z]+-[0-9]{3}) \|/m, markdown, capture: :all_but_first)
    |> List.flatten()
  end
end
