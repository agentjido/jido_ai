defmodule Jido.AI.CLI.WorkflowsGuideTest do
  use ExUnit.Case, async: true

  alias Jido.AI.CLI.Adapter

  @guide_path "guides/user/cli_workflows.md"

  describe "CLI workflow coverage" do
    test "documents one-shot, stdin, and agent-module modes" do
      guide = File.read!(@guide_path)

      assert guide =~ "## One-Shot Query"
      assert guide =~ "## Batch Mode From Stdin"
      assert guide =~ "## Run With Existing Agent Module"
      assert guide =~ "mix jido_ai --stdin"
      assert guide =~ "mix jido_ai --agent"
    end

    test "includes strategy sweep block aligned with supported adapter types" do
      guide = File.read!(@guide_path)

      assert guide =~ "for strategy in react aot cod cot tot got trm adaptive; do"

      Enum.each(Adapter.supported_types(), fn strategy ->
        assert guide =~ strategy
      end)
    end
  end

  describe "CLI guide contract safety" do
    test "uses only supported flags" do
      guide = File.read!(@guide_path)

      supported_flags =
        MapSet.new([
          "--agent",
          "--body",
          "--format",
          "--json",
          "--max-iterations",
          "--model",
          "--quiet",
          "--stdin",
          "--strict",
          "--system",
          "--timeout",
          "--tools",
          "--trace",
          "--type"
        ])

      used_flags =
        Regex.scan(~r/--[a-z][a-z-]*/, guide)
        |> List.flatten()
        |> MapSet.new()

      assert MapSet.subset?(used_flags, supported_flags)
    end

    test "has no stale markdown links" do
      guide = File.read!(@guide_path)
      guide_dir = Path.dirname(@guide_path)

      links =
        Regex.scan(~r/\[[^\]]+\]\(([^)]+)\)/, guide, capture: :all_but_first)
        |> List.flatten()
        |> Enum.reject(&String.starts_with?(&1, "http"))

      Enum.each(links, fn relative_path ->
        resolved_path = Path.expand(relative_path, guide_dir)
        assert File.exists?(resolved_path), "Missing linked file: #{relative_path}"
      end)
    end
  end
end
