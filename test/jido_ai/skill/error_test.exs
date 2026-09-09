defmodule Jido.AI.Skill.ErrorTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Skill.Error

  test "formats parse and lookup errors" do
    assert Exception.message(Error.Unknown.exception(error: :boom)) ==
             "Unknown skill error: :boom"

    assert Exception.message(Error.Parse.NoFrontmatter.exception(file_path: "/tmp/SKILL.md")) ==
             "No YAML frontmatter in /tmp/SKILL.md"

    assert Exception.message(Error.Parse.InvalidYaml.exception(file_path: "/tmp/SKILL.md", reason: :bad_indent)) ==
             "Invalid YAML in /tmp/SKILL.md: :bad_indent"

    assert Exception.message(Error.NotFound.exception(name: "missing")) ==
             "Skill not found: missing"
  end

  test "formats name and required-field validation errors" do
    assert Exception.message(Error.Validation.InvalidName.exception(name: "Bad Name")) ==
             "Invalid skill name 'Bad Name': must be 1-64 chars, lowercase alphanumeric with hyphens"

    assert Exception.message(Error.Validation.MissingField.exception(field: :description)) ==
             "Missing required field: description"
  end

  test "formats all invalid-field reasons" do
    assert Exception.message(
             Error.Validation.InvalidField.exception(
               field: :frontmatter,
               reason: :unsupported_top_level_fields,
               value: [:extra, "other"]
             )
           ) == "Unsupported top-level frontmatter fields: :extra, \"other\""

    expected = [
      directory_name_mismatch: "must match the parent directory name",
      invalid_skill_filename: "file must be named exactly SKILL.md",
      too_long: "exceeds the maximum length",
      empty: "must not be empty",
      invalid_type: "has an invalid type",
      invalid_metadata: "must contain only string keys and string values",
      custom_reason: ":custom_reason"
    ]

    for {reason, text} <- expected do
      error = Error.Validation.InvalidField.exception(field: :description, reason: reason)
      assert Exception.message(error) == "Invalid description: #{text}"
    end
  end
end
