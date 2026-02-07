defmodule Jido.AI.Skill.Error do
  @moduledoc """
  Splode-based error handling for skill operations.
  """

  use Splode,
    error_classes: [
      parse: Jido.AI.Skill.Error.Parse,
      validation: Jido.AI.Skill.Error.Validation
    ],
    unknown_error: Jido.AI.Skill.Error.Unknown
end

defmodule Jido.AI.Skill.Error.Parse do
  @moduledoc "Parse-level errors for SKILL.md files"

  use Splode.ErrorClass,
    class: :parse
end

defmodule Jido.AI.Skill.Error.Validation do
  @moduledoc "Validation errors for skill specs"

  use Splode.ErrorClass,
    class: :validation
end

defmodule Jido.AI.Skill.Error.Unknown do
  @moduledoc "Fallback error for unknown error types"

  use Splode.Error,
    fields: [:error],
    class: :unknown

  @impl true
  def message(%{error: error}), do: "Unknown skill error: #{inspect(error)}"
end

# ============================================================================
# Parse Error Types
# ============================================================================

defmodule Jido.AI.Skill.Error.Parse.NoFrontmatter do
  @moduledoc "No YAML frontmatter found in SKILL.md"

  use Splode.Error,
    fields: [:file_path],
    class: :parse

  @impl true
  def message(%{file_path: file_path}), do: "No YAML frontmatter in #{file_path}"
end

defmodule Jido.AI.Skill.Error.Parse.InvalidYaml do
  @moduledoc "Invalid YAML in frontmatter"

  use Splode.Error,
    fields: [:file_path, :reason],
    class: :parse

  @impl true
  def message(%{file_path: file_path, reason: reason}), do: "Invalid YAML in #{file_path}: #{inspect(reason)}"
end

# ============================================================================
# Validation Error Types
# ============================================================================

defmodule Jido.AI.Skill.Error.Validation.InvalidName do
  @moduledoc "Invalid skill name format"

  use Splode.Error,
    fields: [:name],
    class: :validation

  @impl true
  def message(%{name: name}),
    do: "Invalid skill name '#{name}': must be 1-64 chars, lowercase alphanumeric with hyphens"
end

defmodule Jido.AI.Skill.Error.Validation.MissingField do
  @moduledoc "Required field missing"

  use Splode.Error,
    fields: [:field],
    class: :validation

  @impl true
  def message(%{field: field}), do: "Missing required field: #{field}"
end

defmodule Jido.AI.Skill.Error.NotFound do
  @moduledoc "Skill not found in registry"

  use Splode.Error,
    fields: [:name],
    class: :validation

  @impl true
  def message(%{name: name}), do: "Skill not found: #{name}"
end
