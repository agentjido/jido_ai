defmodule Mix.Tasks.Quality.DialyzerIgnoresTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Quality.DialyzerIgnores

  test "passes when each ignore has reviewed metadata" do
    ignore_entries = [
      ~r/lib\/foo\.ex:1:pattern_match/,
      ~r/lib\/bar\.ex/
    ]

    metadata_entries = [
      %{
        pattern: ~r/lib\/foo\.ex:1:pattern_match/,
        owner: "core-team",
        rationale: "Known false positive.",
        cleanup_plan: "Remove after foo refactor.",
        reviewed_by: "alice",
        reviewed_on: "2026-02-16"
      },
      %{
        pattern: ~r/lib\/bar\.ex/,
        owner: "core-team",
        rationale: "Dependency typing gap.",
        cleanup_plan: "Remove after dependency update.",
        reviewed_by: "bob",
        reviewed_on: "2026-02-16"
      }
    ]

    assert :ok = DialyzerIgnores.validate(ignore_entries, metadata_entries)
  end

  test "fails when ignore is added without matching metadata" do
    ignore_entries = [~r/lib\/foo\.ex:1:pattern_match/]
    metadata_entries = []

    assert {:error, errors} = DialyzerIgnores.validate(ignore_entries, metadata_entries)

    assert Enum.any?(errors, fn error ->
             String.contains?(error, "Missing reviewed metadata")
           end)
  end

  test "fails when metadata is missing required fields" do
    ignore_entries = [~r/lib\/foo\.ex:1:pattern_match/]

    metadata_entries = [
      %{
        pattern: ~r/lib\/foo\.ex:1:pattern_match/,
        owner: "core-team",
        rationale: "Known false positive.",
        cleanup_plan: "Remove after foo refactor.",
        reviewed_by: "",
        reviewed_on: "not-a-date"
      }
    ]

    assert {:error, errors} = DialyzerIgnores.validate(ignore_entries, metadata_entries)

    assert Enum.any?(errors, fn error ->
             String.contains?(error, "missing required `reviewed_by`")
           end)

    assert Enum.any?(errors, fn error ->
             String.contains?(error, "invalid `reviewed_on` date")
           end)
  end
end
