defmodule JidoAI.Examples.CatalogTest do
  use ExUnit.Case, async: true
  @moduletag :example

  @root Path.expand("../../..", __DIR__)

  test "example guides link to existing local files" do
    missing =
      for guide <- guides(),
          [_, link] <- Regex.scan(~r/\]\(([^)]+)\)/, File.read!(guide)),
          URI.parse(link).scheme == nil,
          path = link |> String.split("#", parts: 2) |> hd(),
          path != "",
          not File.exists?(Path.expand(path, Path.dirname(guide))) do
        "#{Path.relative_to(guide, @root)}: #{link}"
      end

    assert missing == [], "Missing example links:\n#{Enum.join(missing, "\n")}"
  end

  test "test paths in example shell commands exist" do
    missing =
      for guide <- guides(),
          [_, block] <- Regex.scan(~r/```(?:sh|bash)\n(.*?)```/s, File.read!(guide)),
          [path] <- Regex.scan(~r/\btest\/[\w.\/-]+/, block),
          not File.exists?(Path.join(@root, path)) do
        "#{Path.relative_to(guide, @root)}: #{path}"
      end

    assert missing == [], "Missing example test paths:\n#{Enum.join(missing, "\n")}"
  end

  test "each feature guide has a matching executable test group" do
    features = Path.wildcard(Path.join(@root, "examples/[0-9][0-9]_*/*/README.md"))
    assert features != []

    for guide <- features do
      relative = guide |> Path.dirname() |> Path.relative_to(Path.join(@root, "examples"))
      tests = Path.wildcard(Path.join([@root, "test/examples", relative, "*_test.exs"]))
      assert tests != [], "No example tests for #{relative}"
    end
  end

  defp guides, do: Path.wildcard(Path.join(@root, "examples/**/README.md"))

  test "numbered folders have unique IDs, guides, and matching test folders" do
    folders = Path.wildcard(Path.join(@root, "examples/[0-9][0-9]_*/[0-9][0-9]_*"))
    ids = Enum.map(folders, &(Path.basename(&1) |> String.slice(0, 5)))
    assert length(ids) == length(Enum.uniq(ids))

    for folder <- folders do
      section = folder |> Path.dirname() |> Path.basename()
      feature = Path.basename(folder)
      assert String.starts_with?(feature, String.slice(section, 0, 2) <> "_")
      assert File.exists?(Path.join(folder, "README.md"))
      assert File.dir?(Path.join([@root, "test/examples", section, feature]))
      assert File.read!(Path.join([@root, "examples", section, "README.md"])) =~ feature
    end

    for folder <- Path.wildcard(Path.join(@root, "test/examples/[0-9][0-9]_*/[0-9][0-9]_*")) do
      relative = Path.relative_to(folder, Path.join(@root, "test/examples"))
      assert File.dir?(Path.join([@root, "examples", relative])), "Orphan test group: #{relative}"
    end
  end

  test "feature guides state how to read, run, and limit the lesson" do
    for guide <- Path.wildcard(Path.join(@root, "examples/[0-9][0-9]_*/[0-9][0-9]_*/README.md")) do
      text = File.read!(guide)

      for heading <- ["## Read the code", "## Run it", "## Limits", "## Files"] do
        assert text =~ heading, "#{guide} is missing #{heading}"
      end

      assert text =~ "mix test test/examples/"
      assert text =~ ~r/[Ee]xpected/
    end
  end

  test "application example source contains no test observers or process barriers" do
    for path <- Path.wildcard(Path.join(@root, "examples/[0-9][0-9]_*/**/*.ex")) do
      source = File.read!(path)
      refute source =~ ~r/\b(?:send|receive)\b/, "Move the process barrier to test support: #{path}"
      refute source =~ ~r/(?:context\.observer|Process\.sleep)/, "Move test observation to test support: #{path}"
    end
  end

  test "stable example tests are not skipped" do
    for path <- Path.wildcard(Path.join(@root, "test/examples/[0-9][0-9]_*/**/*_test.exs")) do
      source = File.read!(path)
      # Fresh-VM fingerprints differ only under coverage instrumentation. The
      # normal example run must execute this test, as well as every other test.
      source =
        if Path.basename(path) == "14_03_checkpoint_resume_test.exs",
          do: String.replace(source, "@tag skip: @coverage_skip_reason", ""),
          else: source

      refute source =~ ~r/@(?:tag|moduletag)\s+.*\bskip\b/,
             "Fix or explicitly reclassify the skipped lesson: #{path}"
    end
  end
end
