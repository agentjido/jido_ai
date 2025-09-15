defmodule JidoWorkspace.Roadmap.Writer do
  @moduledoc """
  Utilities for safely writing and updating roadmap markdown files.
  """

  @doc """
  Writes content to a file atomically using a temporary file.
  """
  def write_file(path, content) do
    tmp_path = path <> ".tmp"
    
    with :ok <- File.write(tmp_path, content),
         :ok <- File.rename(tmp_path, path) do
      :ok
    else
      error ->
        File.rm(tmp_path)
        error
    end
  end

  @doc """
  Appends a line to a file atomically.
  """
  def append_line(path, line) do
    case File.read(path) do
      {:ok, content} ->
        new_content = content <> "\n" <> line
        write_file(path, new_content)
      
      {:error, :enoent} ->
        write_file(path, line <> "\n")
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Ensures a file has proper YAML front-matter.
  """
  def ensure_frontmatter(path, default_meta) do
    case File.read(path) do
      {:ok, content} ->
        if String.starts_with?(String.trim(content), "---") do
          :ok  # Already has front-matter
        else
          yaml = build_yaml_frontmatter(default_meta)
          new_content = yaml <> "\n\n" <> content
          write_file(path, new_content)
        end
      
      {:error, :enoent} ->
        # File doesn't exist, create with front-matter
        yaml = build_yaml_frontmatter(default_meta)
        content = yaml <> "\n\n# " <> Map.get(default_meta, "title", "New File") <> "\n\n"
        write_file(path, content)
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Appends content to a specific section in a markdown file.
  """
  def append_to_section(path, section_header, content) do
    case File.read(path) do
      {:ok, file_content} ->
        lines = String.split(file_content, "\n")
        
        case find_section(lines, section_header) do
          {start_idx, _end_idx} ->
            new_lines = 
              Enum.take(lines, start_idx + 1) ++
              [content] ++
              Enum.drop(lines, start_idx + 1)
            
            new_content = Enum.join(new_lines, "\n")
            write_file(path, new_content)
          
          nil ->
            # Section not found, append at end
            new_content = file_content <> "\n\n## " <> section_header <> "\n\n" <> content
            write_file(path, new_content)
        end
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Updates the YAML front-matter of a file.
  """
  def update_frontmatter(path, updates) do
    case File.read(path) do
      {:ok, content} ->
        {current_meta, body_lines} = parse_content_for_update(content)
        updated_meta = Map.merge(current_meta, updates)
        
        yaml = build_yaml_frontmatter(updated_meta)
        body = Enum.join(body_lines, "\n")
        new_content = yaml <> "\n\n" <> body
        
        write_file(path, new_content)
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Creates a new file from a template, replacing placeholders.
  """
  def create_from_template(template_path, target_path, replacements) do
    case File.read(template_path) do
      {:ok, template_content} ->
        new_content = replace_template_vars(template_content, replacements)
        write_file(target_path, new_content)
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private function to build YAML front-matter
  defp build_yaml_frontmatter(meta) do
    yaml_lines = 
      meta
      |> Enum.map(fn {key, value} -> "#{key}: #{format_yaml_value(value)}" end)
    
    "---\n" <> Enum.join(yaml_lines, "\n") <> "\n---"
  end

  # Private function to format values for YAML
  defp format_yaml_value(value) when is_binary(value) do
    if String.contains?(value, " ") or String.contains?(value, ":") do
      "\"#{value}\""
    else
      value
    end
  end
  defp format_yaml_value(value), do: inspect(value)

  # Private function to parse content for updating
  defp parse_content_for_update(content) do
    lines = String.split(content, "\n")
    
    case lines do
      ["---" | rest] ->
        case Enum.find_index(rest, &(&1 == "---")) do
          nil ->
            {%{}, lines}
          
          end_index ->
            yaml_lines = Enum.take(rest, end_index)
            body_lines = Enum.drop(rest, end_index + 1)
            
            yaml_content = Enum.join(yaml_lines, "\n")
            meta = parse_yaml_to_map(yaml_content)
            
            {meta, body_lines}
        end
      
      _ ->
        {%{}, lines}
    end
  end

  # Private function to parse YAML to string-keyed map
  defp parse_yaml_to_map(""), do: %{}
  defp parse_yaml_to_map(yaml_content) do
    case YamlElixir.read_from_string(yaml_content) do
      {:ok, meta} when is_map(meta) -> meta
      {:ok, _} -> %{}
      {:error, _} -> %{}
    end
  end

  # Private function to find a section in markdown
  defp find_section(lines, header) do
    Enum.find_index(lines, fn line ->
      trimmed = String.trim(line)
      String.starts_with?(trimmed, "##") and String.contains?(trimmed, header)
    end)
    |> case do
      nil -> nil
      idx -> {idx, idx}  # For now, just return the header line index
    end
  end

  # Private function to replace template variables
  defp replace_template_vars(content, replacements) do
    Enum.reduce(replacements, content, fn {key, value}, acc ->
      String.replace(acc, "{{#{key}}}", to_string(value))
    end)
  end
end
