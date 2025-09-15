defmodule JidoWorkspace.Roadmap.Scanner do
  @moduledoc """
  Scans the roadmap directory structure to find and enumerate markdown files.
  """

  alias JidoWorkspace.Roadmap.Parser
  alias JidoWorkspace.Roadmap.File, as: RoadmapFile

  @roadmap_root "roadmap"

  @doc """
  Scans for all roadmap markdown files.
  """
  def scan_all do
    scan_pattern("**/*.md")
  end

  @doc """
  Scans for files matching a specific pattern.
  """
  def scan_pattern(pattern) do
    full_pattern = Path.join(@roadmap_root, pattern)
    
    Path.wildcard(full_pattern)
    |> Enum.filter(&String.ends_with?(&1, ".md"))
    |> Enum.sort()
  end

  @doc """
  Scans files for a specific project.
  """
  def scan_project(project_name) when project_name == "workspace" do
    scan_pattern("workspace/*.md")
  end

  def scan_project(project_name) do
    scan_pattern("projects/#{project_name}/*.md")
  end

  @doc """
  Scans for milestone files across all projects.
  """
  def scan_milestones do
    scan_pattern("**/milestone-*.md")
  end

  @doc """
  Scans for backlog files across all projects.
  """
  def scan_backlogs do
    scan_pattern("**/backlog.md")
  end

  @doc """
  Scans for ideas files across all projects.
  """
  def scan_ideas do
    scan_pattern("**/ideas.md")
  end

  @doc """
  Loads and parses all roadmap files, returning File structs.
  """
  def load_all_files do
    scan_all()
    |> Enum.map(&Parser.parse_file/1)
    |> Enum.filter(fn
      {:ok, _} -> true
      {:error, _} -> false
    end)
    |> Enum.map(fn {:ok, file} -> file end)
  end

  @doc """
  Loads files with only front-matter (for performance).
  """
  def load_metadata_only do
    scan_all()
    |> Enum.map(fn path ->
      case Parser.parse_frontmatter_only(path) do
        {:ok, meta} -> 
          %RoadmapFile{
            path: path,
            meta: meta,
            body_lines: [],
            tasks: []
          }
        {:error, _} -> 
          nil
      end
    end)
    |> Enum.filter(&(&1 != nil))
  end

  @doc """
  Gets all available projects by scanning the directory structure.
  """
  def available_projects do
    workspace_projects = if File.exists?(Path.join(@roadmap_root, "workspace")), do: ["workspace"], else: []
    
    project_dirs = 
      Path.join(@roadmap_root, "projects")
      |> File.ls!()
      |> Enum.filter(fn name -> 
        File.dir?(Path.join([@roadmap_root, "projects", name]))
      end)
    
    workspace_projects ++ project_dirs
  rescue
    _ -> ["workspace"]  # fallback if projects dir doesn't exist
  end

  @doc """
  Gets the next milestone number for a given project.
  """
  def next_milestone_number(project) do
    project
    |> scan_project()
    |> Enum.filter(&String.contains?(Path.basename(&1), "milestone-"))
    |> Enum.map(fn path ->
      Path.basename(path, ".md")
      |> String.replace_prefix("milestone-", "")
      |> String.to_integer()
    end)
    |> case do
      [] -> 1
      numbers -> Enum.max(numbers) + 1
    end
  rescue
    _ -> 1
  end
end
