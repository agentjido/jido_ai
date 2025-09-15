defmodule JidoWorkspace.Roadmap.Parser do
  @moduledoc """
  Parses roadmap markdown files, extracting YAML front-matter and tasks.
  """

  alias JidoWorkspace.Roadmap.Task
  alias JidoWorkspace.Roadmap.File, as: RoadmapFile

  @doc """
  Parses a markdown file, returning a Roadmap.File struct with metadata and tasks.
  """
  def parse_file(path) do
    case File.read(path) do
      {:ok, content} ->
        {meta, body_lines} = parse_content(content)
        tasks = extract_tasks(body_lines, path)
        
        {:ok, %RoadmapFile{
          path: path,
          meta: meta,
          body_lines: body_lines,
          tasks: tasks
        }}
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Parses file content, separating YAML front-matter from body.
  """
  def parse_content(content) do
    lines = String.split(content, "\n")
    
    case lines do
      ["---" | rest] ->
        parse_with_frontmatter(rest)
      
      _ ->
        {%{}, lines}
    end
  end

  @doc """
  Extracts tasks from body lines.
  """
  def extract_tasks(lines, file_path) do
    lines
    |> Enum.with_index(1)
    |> Enum.filter(fn {line, _idx} -> Task.task_line?(line) end)
    |> Enum.map(fn {line, idx} -> Task.parse(line, idx, file_path) end)
    |> Enum.filter(&(&1 != nil))
  end

  @doc """
  Gets only the front-matter metadata without parsing the full body.
  Useful for performance when you only need metadata.
  """
  def parse_frontmatter_only(path) do
    case File.read(path) do
      {:ok, content} ->
        lines = String.split(content, "\n")
        
        case lines do
          ["---" | rest] ->
            {meta, _} = parse_with_frontmatter(rest)
            {:ok, meta}
          
          _ ->
            {:ok, %{}}
        end
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private function to parse content with YAML front-matter
  defp parse_with_frontmatter(lines) do
    case Enum.find_index(lines, &(&1 == "---")) do
      nil ->
        # No closing ---, treat everything as front-matter
        yaml_content = Enum.join(lines, "\n")
        meta = parse_yaml(yaml_content)
        {meta, []}
      
      end_index ->
        yaml_lines = Enum.take(lines, end_index)
        body_lines = Enum.drop(lines, end_index + 1)
        
        yaml_content = Enum.join(yaml_lines, "\n")
        meta = parse_yaml(yaml_content)
        
        {meta, body_lines}
    end
  end

  # Private function to parse YAML content
  defp parse_yaml(""), do: %{}
  defp parse_yaml(yaml_content) do
    case YamlElixir.read_from_string(yaml_content) do
      {:ok, meta} when is_map(meta) -> 
        # Convert string keys to atoms for easier access
        Map.new(meta, fn {k, v} -> {String.to_atom(k), v} end)
      
      {:ok, _} -> 
        %{}
      
      {:error, _} -> 
        %{}
    end
  end
end
