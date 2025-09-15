defmodule Mix.Tasks.Roadmap.Todo do
  @moduledoc """
  Show personal todo list from roadmap tasks.

  ## Examples

      mix roadmap.todo
      mix roadmap.todo --owner @alice
      mix roadmap.todo --project jido

  """

  use Mix.Task

  alias JidoWorkspace.Roadmap.{Scanner, Filters}

  @shortdoc "Show personal todo list"

  @switches [
    owner: :string,
    project: :string,
    all: :boolean
  ]

  def run(args) do
    {opts, _args} = OptionParser.parse!(args, switches: @switches)

    owner = opts[:owner] || get_git_author()
    
    files = 
      Scanner.load_all_files()
      |> Filters.by_project(opts[:project] || "all")
      |> Filters.by_status("in-progress")

    tasks = 
      Filters.extract_all_tasks(files)
      |> Filters.by_owner(owner)
      |> Filters.by_completed(false)
      |> Filters.sort_by_priority()

    if Enum.empty?(tasks) do
      Mix.shell().info("🎉 No pending tasks assigned to #{owner}!")
    else
      display_todo_list(tasks, owner)
    end
  end

  defp display_todo_list(tasks, owner) do
    Mix.shell().info("📋 Todo List for #{owner}")
    Mix.shell().info("═" <> String.duplicate("═", 40))
    
    tasks
    |> Enum.group_by(&extract_project_from_path(&1.file_path))
    |> Enum.each(fn {project, project_tasks} ->
      Mix.shell().info("\n#{String.upcase(project)}:")
      
      project_tasks
      |> Enum.each(fn task ->
        status = if task.id, do: "[#{task.id}]", else: "[ ]"
        estimate = if task.estimate, do: " (#{task.estimate})", else: ""
        
        Mix.shell().info("  #{status} #{task.title}#{estimate}")
      end)
    end)
    
    total_tasks = length(tasks)
    Mix.shell().info("\n📊 Total: #{total_tasks} tasks")
    
    # Show quick stats
    by_type = 
      tasks
      |> Enum.group_by(fn task ->
        if task.id do
          task.id |> String.split("-") |> List.first()
        else
          "OTHER"
        end
      end)
      |> Enum.map(fn {type, type_tasks} -> "#{type}: #{length(type_tasks)}" end)
      |> Enum.join(", ")
    
    if by_type != "" do
      Mix.shell().info("🏷️  By type: #{by_type}")
    end
  end

  defp extract_project_from_path(path) do
    cond do
      String.contains?(path, "roadmap/workspace/") -> "workspace"
      String.contains?(path, "roadmap/projects/") ->
        path
        |> String.split("/")
        |> Enum.drop_while(&(&1 != "projects"))
        |> Enum.at(1, "unknown")
      true -> "unknown"
    end
  end

  defp get_git_author do
    case System.cmd("git", ["config", "--get", "user.name"]) do
      {name, 0} -> "@#{String.trim(name)}"
      _ -> "@user"
    end
  end
end
