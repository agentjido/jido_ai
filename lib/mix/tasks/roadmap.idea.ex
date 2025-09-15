defmodule Mix.Tasks.Roadmap.Idea do
  @moduledoc """
  Quickly capture ideas to roadmap files.

  ## Examples

      mix roadmap.idea "offline mode for meetings"
      mix roadmap.idea "refactor auth system" --project jido
      mix roadmap.idea "new feature idea" --open

  """

  use Mix.Task

  alias JidoWorkspace.Roadmap.Writer

  @shortdoc "Capture a quick idea"

  @switches [
    project: :string,
    open: :boolean
  ]

  def run(args) do
    {opts, args} = OptionParser.parse!(args, switches: @switches)

    case args do
      [idea] when is_binary(idea) ->
        project = opts[:project] || "workspace"
        capture_idea(idea, project, opts[:open])
      
      [] ->
        Mix.raise("Please provide an idea to capture: mix roadmap.idea \"your idea here\"")
      
      _ ->
        Mix.raise("Please provide a single quoted idea")
    end
  end

  defp capture_idea(idea, project, open_after?) do
    ideas_file = get_ideas_file(project)
    
    # Ensure the file exists with proper structure
    ensure_ideas_file(ideas_file, project)
    
    # Add the idea
    timestamp = Date.utc_today() |> Date.to_string()
    idea_line = "- #{idea} (#{timestamp})"
    
    case Writer.append_to_section(ideas_file, "Ideas Brain Dump", idea_line) do
      :ok ->
        Mix.shell().info("💡 Idea captured in #{ideas_file}")
        
        if open_after? do
          open_file(ideas_file)
        end
      
      {:error, reason} ->
        Mix.raise("Failed to write idea: #{reason}")
    end
  end

  defp get_ideas_file("workspace") do
    "roadmap/workspace/ideas.md"
  end

  defp get_ideas_file(project) do
    "roadmap/projects/#{project}/ideas.md"
  end

  defp ensure_ideas_file(path, project) do
    unless File.exists?(path) do
      # Ensure directory exists
      Path.dirname(path) |> File.mkdir_p!()
      
      # Create from template
      default_meta = %{
        "project" => project,
        "type" => "ideas",
        "owner" => get_git_author(),
        "status" => "active",
        "review" => "ongoing"
      }
      
      case Writer.ensure_frontmatter(path, default_meta) do
        :ok -> 
          # Add basic structure
          content = """

# Ideas – #{String.capitalize(project)}

## Ideas Brain Dump
> Raw ideas, concepts, and inspiration - no structure required

- 

## Architecture Ideas
> Big picture improvements and refactoring thoughts

- 

## Feature Ideas
> New features and enhancements

- 

## Technical Ideas
> Development workflow and tooling improvements

- 
"""
          File.write!(path, File.read!(path) <> content)
        
        {:error, reason} ->
          Mix.raise("Failed to create ideas file: #{reason}")
      end
    end
  end

  defp open_file(path) do
    editor = System.get_env("EDITOR") || "nano"
    
    case System.cmd(editor, [path], into: IO.stream(:stdio, :line)) do
      {_, 0} -> :ok
      {_, _} -> Mix.shell().info("Note: Could not open editor. File saved at #{path}")
    end
  end

  defp get_git_author do
    case System.cmd("git", ["config", "--get", "user.name"]) do
      {name, 0} -> "@#{String.trim(name)}"
      _ -> "@user"
    end
  end
end
