defmodule Jido.AI.Skill.Loader do
  @moduledoc """
  Parses SKILL.md files into `Jido.AI.Skill.Spec` structs.

  Supports the agentskills.io format with YAML frontmatter.
  """

  alias Jido.AI.Skill.{Spec, Error}

  @name_regex ~r/^[a-z0-9]+(-[a-z0-9]+)*$/
  @max_name_length 64
  @max_description_length 1024
  @max_compatibility_length 500

  @doc """
  Loads a skill from a SKILL.md file path.

  Returns `{:ok, spec}` or `{:error, reason}`.
  """
  @spec load(String.t()) :: {:ok, Spec.t()} | {:error, term()}
  def load(path) do
    with {:ok, content} <- File.read(path),
         {:ok, {frontmatter, body}} <- parse_frontmatter(content, path) do
      build_spec(frontmatter, body, path)
    end
  end

  @doc """
  Loads a skill from a SKILL.md file path, raising on error.
  """
  @spec load!(String.t()) :: Spec.t()
  def load!(path) do
    case load(path) do
      {:ok, spec} -> spec
      {:error, error} -> raise Error.to_error(error)
    end
  end

  @doc """
  Parses SKILL.md content string into a spec.
  """
  @spec parse(String.t(), String.t()) :: {:ok, Spec.t()} | {:error, term()}
  def parse(content, source_path \\ "inline") do
    with {:ok, {frontmatter, body}} <- parse_frontmatter(content, source_path) do
      build_spec(frontmatter, body, source_path)
    end
  end

  defp parse_frontmatter(content, path) do
    case Regex.run(~r/\A---\r?\n(.*?)\r?\n---\r?\n(.*)\z/s, content) do
      [_, yaml, body] ->
        case YamlElixir.read_from_string(yaml) do
          {:ok, frontmatter} -> {:ok, {frontmatter, String.trim(body)}}
          {:error, reason} -> {:error, %Error.Parse.InvalidYaml{file_path: path, reason: reason}}
        end

      nil ->
        {:error, %Error.Parse.NoFrontmatter{file_path: path}}
    end
  end

  defp build_spec(frontmatter, body, path) do
    with {:ok, name} <- validate_name(frontmatter["name"]),
         {:ok, description} <- validate_description(frontmatter["description"]) do
      spec = %Spec{
        name: name,
        description: description,
        license: frontmatter["license"],
        compatibility: validate_compatibility(frontmatter["compatibility"]),
        metadata: frontmatter["metadata"],
        allowed_tools: parse_allowed_tools(frontmatter["allowed-tools"]),
        source: {:file, path},
        body_ref: {:inline, body},
        actions: [],
        plugins: [],
        vsn: frontmatter["vsn"] || frontmatter["version"],
        tags: List.wrap(frontmatter["tags"])
      }

      {:ok, spec}
    end
  end

  defp validate_name(nil), do: {:error, %Error.Validation.MissingField{field: :name}}

  defp validate_name(name) when is_binary(name) do
    cond do
      String.length(name) > @max_name_length ->
        {:error, %Error.Validation.InvalidName{name: name}}

      not Regex.match?(@name_regex, name) ->
        {:error, %Error.Validation.InvalidName{name: name}}

      true ->
        {:ok, name}
    end
  end

  defp validate_name(_), do: {:error, %Error.Validation.MissingField{field: :name}}

  defp validate_description(nil), do: {:error, %Error.Validation.MissingField{field: :description}}

  defp validate_description(desc) when is_binary(desc) do
    if String.length(desc) > @max_description_length do
      {:ok, String.slice(desc, 0, @max_description_length)}
    else
      {:ok, desc}
    end
  end

  defp validate_description(_), do: {:error, %Error.Validation.MissingField{field: :description}}

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
