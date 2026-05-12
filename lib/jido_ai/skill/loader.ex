defmodule Jido.AI.Skill.Loader do
  @moduledoc """
  Parses SKILL.md files into `Jido.AI.Skill.Spec` structs.

  Supports the agentskills.io format with YAML frontmatter.

  ## Lenient Parsing Mode

  When `lenient: true` is passed to load functions:
  - Non-fatal warnings are collected instead of causing failures
  - Parent directory name mismatches generate warnings
  - Cosmetic naming violations are noted
  - Returns both the spec and diagnostics

  ## Diagnostics

  All parse operations can track diagnostics via the `:diagnostics`
  option or by using `load_with_diagnostics/2`:

      {:ok, spec, diagnostics} = Loader.load_with_diagnostics(path)
  """

  alias Jido.AI.Skill.{Spec, Error, Diagnostics}

  @name_regex ~r/^[a-z0-9]+(-[a-z0-9]+)*$/
  @max_name_length 64
  @max_description_length 1024
  @max_compatibility_length 500

  @doc """
  Loads a skill from a SKILL.md file path.

  Returns `{:ok, spec}` or `{:error, reason}`.

  ## Options

  - `:lenient` - When true, non-fatal issues become warnings instead of errors (default: false)
  - `:diagnostics` - Pass an existing Diagnostics struct to accumulate warnings
  """
  @spec load(String.t(), keyword()) :: {:ok, Spec.t()} | {:error, term()}
  def load(path, opts \\ []) do
    lenient = Keyword.get(opts, :lenient, false)
    diagnostics = Keyword.get(opts, :diagnostics, Diagnostics.new())

    with {:ok, content} <- File.read(path),
         {:ok, {frontmatter, body}, diagnostics} <- parse_frontmatter(content, path, diagnostics, lenient) do
      build_spec(frontmatter, body, path, diagnostics, lenient)
    end
  end

  @doc """
  Loads a skill with full diagnostics tracking.

  Returns `{:ok, spec, diagnostics}` or `{:error, reason, diagnostics}`.
  Always returns diagnostics even on failure, allowing inspection of warnings.

  ## Examples

      {:ok, spec, diagnostics} = Loader.load_with_diagnostics(path)
      Enum.each(diagnostics.warnings, &IO.puts/1)
  """
  @spec load_with_diagnostics(String.t(), keyword()) ::
          {:ok, Spec.t(), Diagnostics.t()} | {:error, term(), Diagnostics.t()}
  def load_with_diagnostics(path, opts \\ []) do
    lenient = Keyword.get(opts, :lenient, true)
    diagnostics = Diagnostics.new()

    case load(path, lenient: lenient, diagnostics: diagnostics) do
      {:ok, spec} -> {:ok, spec, diagnostics}
      {:error, reason} -> {:error, reason, diagnostics}
    end
  end

  @doc """
  Loads a skill from a SKILL.md file path, raising on error.
  """
  @spec load!(String.t(), keyword()) :: Spec.t()
  def load!(path, opts \\ []) do
    case load(path, opts) do
      {:ok, spec} -> spec
      {:error, error} -> raise Error.to_error(error)
    end
  end

  @doc """
  Parses SKILL.md content string into a spec.

  ## Options

  - `:lenient` - When true, non-fatal issues become warnings instead of errors
  - `:diagnostics` - Pass an existing Diagnostics struct to accumulate warnings
  """
  @spec parse(String.t(), String.t(), keyword()) :: {:ok, Spec.t()} | {:error, term()}
  def parse(content, source_path \\ "inline", opts \\ []) do
    lenient = Keyword.get(opts, :lenient, false)
    diagnostics = Keyword.get(opts, :diagnostics, Diagnostics.new())

    with {:ok, {frontmatter, body}, diagnostics} <- parse_frontmatter(content, source_path, diagnostics, lenient) do
      build_spec(frontmatter, body, source_path, diagnostics, lenient)
    end
  end

  defp parse_frontmatter(content, path, diagnostics, lenient) do
    case Regex.run(~r/\A---\r?\n(.*?)\r?\n---\r?\n(.*)\z/s, content) do
      [_, yaml, body] ->
        case YamlElixir.read_from_string(yaml) do
          {:ok, frontmatter} -> {:ok, {frontmatter, String.trim(body)}, diagnostics}
          {:error, reason} ->
            if lenient do
              diagnostics = Diagnostics.add_error(diagnostics, %Error.Parse.InvalidYaml{file_path: path, reason: reason})
              # Return empty frontmatter to continue in lenient mode
              {:ok, {%{}, String.trim(body)}, diagnostics}
            else
              {:error, %Error.Parse.InvalidYaml{file_path: path, reason: reason}}
            end
        end

      nil ->
        if lenient do
          diagnostics = Diagnostics.add_error(diagnostics, %Error.Parse.NoFrontmatter{file_path: path})
          {:ok, {%{}, String.trim(content)}, diagnostics}
        else
          {:error, %Error.Parse.NoFrontmatter{file_path: path}}
        end
    end
  end

  defp build_spec(frontmatter, body, path, diagnostics, lenient) do
    # Check for parent directory name mismatch (non-fatal warning)
    diagnostics = check_directory_name_match(frontmatter["name"], path, diagnostics, lenient)

    # Validate fields, allowing lenient mode to proceed with defaults
    with {:ok, name, diagnostics} <- validate_name(frontmatter["name"], diagnostics, lenient),
         {:ok, description, diagnostics} <- validate_description(frontmatter["description"], diagnostics, lenient) do
      spec = %Spec{
        name: name,
        description: description,
        license: frontmatter["license"],
        compatibility: validate_compatibility(frontmatter["compatibility"]),
        metadata: Map.put(frontmatter["metadata"] || %{}, :diagnostics, Diagnostics.to_map(diagnostics)),
        allowed_tools: parse_allowed_tools(frontmatter["allowed-tools"]),
        source: {:file, path},
        body_ref: {:inline, body},
        actions: [],
        plugins: [],
        vsn: frontmatter["vsn"] || frontmatter["version"],
        tags: List.wrap(frontmatter["tags"]),
        diagnostics: diagnostics
      }

      {:ok, spec}
    end
  end

  # Check if the directory name matches the declared skill name
  defp check_directory_name_match(nil, _path, diagnostics, _lenient), do: diagnostics

  defp check_directory_name_match(name, path, diagnostics, lenient) do
    parent_dir = path |> Path.dirname() |> Path.basename()

    # Normalize for comparison (kebab-case variations allowed)
    normalized_dir = String.downcase(parent_dir) |> String.replace("_", "-")
    normalized_name = String.downcase(name)

    if normalized_dir != normalized_name do
      warning = Diagnostics.Warning.new(
        :directory_name_mismatch,
        "Skill name '#{name}' does not match parent directory '#{parent_dir}'"
      )

      if lenient do
        Diagnostics.add_warning(diagnostics, warning)
      else
        # In strict mode, this could still be a warning but not fatal
        Diagnostics.add_warning(diagnostics, warning)
      end
    else
      diagnostics
    end
  end

  defp validate_name(nil, diagnostics, lenient) do
    error = %Error.Validation.MissingField{field: :name}

    if lenient do
      # Generate a fallback name from the path in lenient mode
      fallback = "unnamed-skill-#{:erlang.unique_integer([:positive])}"
      diagnostics = Diagnostics.add_warning(diagnostics, Diagnostics.Warning.new(:missing_name, "Missing required field: name, using fallback: #{fallback}"))
      {:ok, fallback, diagnostics}
    else
      {:error, error}
    end
  end

  defp validate_name(name, diagnostics, lenient) when is_binary(name) do
    cond do
      String.length(name) > @max_name_length ->
        error = %Error.Validation.InvalidName{name: name}

        if lenient do
          truncated = String.slice(name, 0, @max_name_length)
          warning = Diagnostics.Warning.new(:name_too_long, "Skill name exceeds #{@max_name_length} chars, truncated to: #{truncated}")
          diagnostics = Diagnostics.add_warning(diagnostics, warning)
          {:ok, truncated, diagnostics}
        else
          {:error, error}
        end

      not Regex.match?(@name_regex, name) ->
        error = %Error.Validation.InvalidName{name: name}

        if lenient do
          # Normalize the name (lowercase, replace invalid chars with hyphens)
          normalized = name
          |> String.downcase()
          |> String.replace(~r/[^a-z0-9]+/, "-")
          |> String.trim("-")

          warning = Diagnostics.Warning.new(:invalid_name_format, "Invalid skill name '#{name}', normalized to: #{normalized}")
          diagnostics = Diagnostics.add_warning(diagnostics, warning)
          {:ok, normalized, diagnostics}
        else
          {:error, error}
        end

      true ->
        {:ok, name, diagnostics}
    end
  end

  defp validate_name(_, diagnostics, lenient) do
    error = %Error.Validation.MissingField{field: :name}

    if lenient do
      fallback = "unnamed-skill-#{:erlang.unique_integer([:positive])}"
      diagnostics = Diagnostics.add_warning(diagnostics, Diagnostics.Warning.new(:invalid_name_type, "Invalid name type, using fallback: #{fallback}"))
      {:ok, fallback, diagnostics}
    else
      {:error, error}
    end
  end

  defp validate_description(nil, diagnostics, lenient) do
    if lenient do
      fallback = "No description provided"
      warning = Diagnostics.Warning.new(:missing_description, "Missing required field: description, using fallback")
      diagnostics = Diagnostics.add_warning(diagnostics, warning)
      {:ok, fallback, diagnostics}
    else
      {:error, %Error.Validation.MissingField{field: :description}}
    end
  end

  defp validate_description(desc, diagnostics, _lenient) when is_binary(desc) do
    if String.length(desc) > @max_description_length do
      # Always truncate long descriptions as a warning
      truncated = String.slice(desc, 0, @max_description_length)
      warning = Diagnostics.Warning.new(:description_too_long, "Description exceeds #{@max_description_length} chars, truncated")
      diagnostics = Diagnostics.add_warning(diagnostics, warning)
      {:ok, truncated, diagnostics}
    else
      {:ok, desc, diagnostics}
    end
  end

  defp validate_description(_, diagnostics, lenient) do
    if lenient do
      fallback = "No description provided"
      warning = Diagnostics.Warning.new(:invalid_description_type, "Invalid description type, using fallback")
      diagnostics = Diagnostics.add_warning(diagnostics, warning)
      {:ok, fallback, diagnostics}
    else
      {:error, %Error.Validation.MissingField{field: :description}}
    end
  end

  defp validate_compatibility(nil), do: nil

  defp validate_compatibility(compat) when is_binary(compat) do
    if String.length(compat) > @max_compatibility_length do
      String.slice(compat, 0, @max_compatibility_length)
    else
      compat
    end
  end

  defp validate_compatibility(_), do: nil

  defp parse_allowed_tools(nil), do: []
  defp parse_allowed_tools(tools) when is_list(tools), do: Enum.map(tools, &to_string/1)
  defp parse_allowed_tools(tools) when is_binary(tools), do: String.split(tools, ~r/\s+/, trim: true)
  defp parse_allowed_tools(_), do: []
end
