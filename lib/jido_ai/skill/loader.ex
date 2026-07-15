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
      # load/2 accumulates diagnostics inside the spec; pull them back out
      # so the documented {:ok, spec, diagnostics} contract is honored.
      {:ok, spec} -> {:ok, spec, spec.diagnostics || diagnostics}
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
          {:ok, frontmatter} ->
            {:ok, {frontmatter, String.trim(body)}, diagnostics}

          {:error, reason} ->
            if lenient do
              diagnostics =
                Diagnostics.add_error(diagnostics, %Error.Parse.InvalidYaml{file_path: path, reason: reason})

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
    # Validate fields, allowing lenient mode to proceed with defaults
    with {:ok, name, diagnostics} <- validate_name(frontmatter["name"], diagnostics, lenient),
         {:ok, diagnostics} <- check_directory_name_match(name, path, diagnostics, lenient),
         {:ok, description, diagnostics} <- validate_description(frontmatter["description"], diagnostics, lenient),
         {:ok, license, diagnostics} <- validate_license(frontmatter["license"], diagnostics, lenient),
         {:ok, compatibility, diagnostics} <-
           validate_compatibility(frontmatter["compatibility"], diagnostics, lenient),
         {:ok, metadata, diagnostics} <- parse_metadata(frontmatter["metadata"], diagnostics, lenient),
         {:ok, allowed_tools, diagnostics} <-
           validate_allowed_tools(frontmatter["allowed-tools"], diagnostics, lenient) do
      spec = %Spec{
        name: name,
        description: description,
        license: license,
        compatibility: compatibility,
        metadata: metadata,
        allowed_tools: allowed_tools,
        source: {:file, path},
        body_ref: {:inline, body},
        actions: [],
        plugins: [],
        vsn: optional_string(frontmatter["vsn"] || frontmatter["version"]),
        tags: parse_tags(frontmatter["tags"]),
        diagnostics: diagnostics
      }

      {:ok, spec}
    end
  end

  # Check if the directory name exactly matches the validated skill name.
  # Inline parse sources do not have a filesystem directory to compare.
  defp check_directory_name_match(_name, path, diagnostics, _lenient)
       when not is_binary(path),
       do: {:ok, diagnostics}

  defp check_directory_name_match(name, path, diagnostics, lenient) when is_binary(name) do
    if Path.basename(path) != "SKILL.md" do
      {:ok, diagnostics}
    else
      do_check_directory_name_match(name, path, diagnostics, lenient)
    end
  end

  defp do_check_directory_name_match(name, path, diagnostics, lenient) do
    parent_dir = path |> Path.expand() |> Path.dirname() |> Path.basename()

    if parent_dir != name do
      warning =
        Diagnostics.Warning.new(
          :directory_name_mismatch,
          "Skill name '#{name}' does not match parent directory '#{parent_dir}'"
        )

      if lenient do
        {:ok, Diagnostics.add_warning(diagnostics, warning)}
      else
        {:error,
         %Error.Validation.InvalidField{
           field: :name,
           reason: :directory_name_mismatch,
           value: name
         }}
      end
    else
      {:ok, diagnostics}
    end
  end

  defp validate_name(nil, diagnostics, lenient) do
    error = %Error.Validation.MissingField{field: :name}

    if lenient do
      # Generate a fallback name from the path in lenient mode
      fallback = fallback_name()

      diagnostics =
        Diagnostics.add_warning(
          diagnostics,
          Diagnostics.Warning.new(:missing_name, "Missing required field: name, using fallback: #{fallback}")
        )

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
          normalized =
            name
            |> normalize_skill_name()
            |> String.slice(0, @max_name_length)
            |> String.trim("-")

          normalize_or_fallback_name(
            name,
            normalized,
            diagnostics,
            :name_too_long,
            "Skill name exceeds #{@max_name_length} chars, truncated to: "
          )
        else
          {:error, error}
        end

      not Regex.match?(@name_regex, name) ->
        error = %Error.Validation.InvalidName{name: name}

        if lenient do
          normalize_or_fallback_name(
            name,
            normalize_skill_name(name),
            diagnostics,
            :invalid_name_format,
            "Invalid skill name '#{name}', normalized to: "
          )
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
      fallback = fallback_name()

      diagnostics =
        Diagnostics.add_warning(
          diagnostics,
          Diagnostics.Warning.new(:invalid_name_type, "Invalid name type, using fallback: #{fallback}")
        )

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

  defp validate_description(desc, diagnostics, lenient) when is_binary(desc) do
    cond do
      String.trim(desc) == "" ->
        if lenient do
          fallback = "No description provided"
          warning = Diagnostics.Warning.new(:blank_description, "Blank required field: description, using fallback")
          diagnostics = Diagnostics.add_warning(diagnostics, warning)
          {:ok, fallback, diagnostics}
        else
          {:error, %Error.Validation.MissingField{field: :description}}
        end

      String.length(desc) > @max_description_length ->
        if lenient do
          truncated = String.slice(desc, 0, @max_description_length)

          warning =
            Diagnostics.Warning.new(
              :description_too_long,
              "Description exceeds #{@max_description_length} chars, truncated"
            )

          diagnostics = Diagnostics.add_warning(diagnostics, warning)
          {:ok, truncated, diagnostics}
        else
          {:error,
           %Error.Validation.InvalidField{
             field: :description,
             reason: :too_long,
             value: desc
           }}
        end

      true ->
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

  defp validate_license(nil, diagnostics, _lenient), do: {:ok, nil, diagnostics}
  defp validate_license(license, diagnostics, _lenient) when is_binary(license), do: {:ok, license, diagnostics}

  defp validate_license(license, diagnostics, lenient) do
    invalid_optional_string(:license, license, :invalid_type, diagnostics, lenient)
  end

  defp validate_compatibility(nil, diagnostics, _lenient), do: {:ok, nil, diagnostics}

  defp validate_compatibility(compat, diagnostics, lenient) when is_binary(compat) do
    cond do
      String.trim(compat) == "" ->
        invalid_optional_string(:compatibility, compat, :empty, diagnostics, lenient)

      String.length(compat) > @max_compatibility_length ->
        if lenient do
          warning =
            Diagnostics.Warning.new(
              :compatibility_too_long,
              "Compatibility exceeds #{@max_compatibility_length} chars, truncated"
            )

          {:ok, String.slice(compat, 0, @max_compatibility_length), Diagnostics.add_warning(diagnostics, warning)}
        else
          {:error,
           %Error.Validation.InvalidField{
             field: :compatibility,
             reason: :too_long,
             value: compat
           }}
        end

      true ->
        {:ok, compat, diagnostics}
    end
  end

  defp validate_compatibility(compat, diagnostics, lenient) do
    invalid_optional_string(:compatibility, compat, :invalid_type, diagnostics, lenient)
  end

  defp validate_allowed_tools(nil, diagnostics, _lenient), do: {:ok, [], diagnostics}

  defp validate_allowed_tools(tools, diagnostics, _lenient) when is_binary(tools) do
    {:ok, String.split(tools, ~r/\s+/, trim: true), diagnostics}
  end

  defp validate_allowed_tools(tools, diagnostics, true) when is_list(tools) do
    warning =
      Diagnostics.Warning.new(
        :invalid_allowed_tools_type,
        "allowed-tools must be a space-separated string; list entries were normalized"
      )

    {:ok, Enum.map(tools, &metadata_string/1), Diagnostics.add_warning(diagnostics, warning)}
  end

  defp validate_allowed_tools(_tools, diagnostics, true) do
    warning = Diagnostics.Warning.new(:invalid_allowed_tools_type, "Invalid allowed-tools; field omitted")
    {:ok, [], Diagnostics.add_warning(diagnostics, warning)}
  end

  defp validate_allowed_tools(tools, _diagnostics, false) do
    {:error,
     %Error.Validation.InvalidField{
       field: :allowed_tools,
       reason: :invalid_type,
       value: tools
     }}
  end

  defp parse_metadata(nil, diagnostics, _lenient), do: {:ok, %{}, diagnostics}

  defp parse_metadata(metadata, diagnostics, _lenient)
       when is_map(metadata) and map_size(metadata) == 0,
       do: {:ok, metadata, diagnostics}

  defp parse_metadata(metadata, diagnostics, lenient) when is_map(metadata) do
    if Enum.all?(metadata, fn {key, value} -> is_binary(key) and is_binary(value) end) do
      {:ok, metadata, diagnostics}
    else
      if lenient do
        warning =
          Diagnostics.Warning.new(
            :invalid_metadata_entries,
            "Metadata keys and values must be strings; invalid entries were normalized"
          )

        {:ok, normalize_metadata(metadata), Diagnostics.add_warning(diagnostics, warning)}
      else
        {:error,
         %Error.Validation.InvalidField{
           field: :metadata,
           reason: :invalid_metadata,
           value: metadata
         }}
      end
    end
  end

  defp parse_metadata(_metadata, diagnostics, true) do
    diagnostics =
      Diagnostics.add_warning(
        diagnostics,
        Diagnostics.Warning.new(:invalid_metadata_type, "Invalid metadata type, using empty metadata")
      )

    {:ok, %{}, diagnostics}
  end

  defp parse_metadata(metadata, _diagnostics, false) do
    {:error,
     %Error.Validation.InvalidField{
       field: :metadata,
       reason: :invalid_type,
       value: metadata
     }}
  end

  defp invalid_optional_string(field, _value, _reason, diagnostics, true) do
    warning = Diagnostics.Warning.new(invalid_field_warning(field), "Invalid #{field}; field omitted")
    {:ok, nil, Diagnostics.add_warning(diagnostics, warning)}
  end

  defp invalid_optional_string(field, value, reason, _diagnostics, false) do
    {:error, %Error.Validation.InvalidField{field: field, reason: reason, value: value}}
  end

  defp normalize_metadata(metadata) do
    Map.new(metadata, fn {key, value} -> {metadata_string(key), metadata_string(value)} end)
  end

  defp metadata_string(value) when is_binary(value), do: value
  defp metadata_string(value) when is_atom(value) or is_number(value), do: to_string(value)
  defp metadata_string(value), do: inspect(value)

  defp invalid_field_warning(:compatibility), do: :invalid_compatibility
  defp invalid_field_warning(:license), do: :invalid_license

  defp parse_tags(nil), do: []
  defp parse_tags(tags) when is_list(tags), do: Enum.map(tags, &to_string/1)
  defp parse_tags(tag) when is_binary(tag), do: [tag]
  defp parse_tags(tag), do: [to_string(tag)]

  defp optional_string(value) when is_binary(value), do: value
  defp optional_string(_value), do: nil

  defp normalize_or_fallback_name(original, "", diagnostics, _warning_type, _message_prefix) do
    fallback = fallback_name()

    warning =
      Diagnostics.Warning.new(
        :invalid_name_format,
        "Invalid skill name '#{original}', using fallback: #{fallback}"
      )

    {:ok, fallback, Diagnostics.add_warning(diagnostics, warning)}
  end

  defp normalize_or_fallback_name(_original, normalized, diagnostics, warning_type, message_prefix) do
    warning = Diagnostics.Warning.new(warning_type, message_prefix <> normalized)
    {:ok, normalized, Diagnostics.add_warning(diagnostics, warning)}
  end

  defp normalize_skill_name(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.replace(~r/-+/, "-")
    |> String.trim("-")
  end

  defp fallback_name do
    "unnamed-skill-#{:erlang.unique_integer([:positive])}"
  end
end
