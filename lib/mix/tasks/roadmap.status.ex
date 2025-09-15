defmodule Mix.Tasks.Roadmap.Status do
  @moduledoc """
  Shows the status of tasks across roadmap files.

  ## Examples

      mix roadmap.status
      mix roadmap.status --project jido
      mix roadmap.status --type milestone
      mix roadmap.status --owner @alice
      mix roadmap.status --json

  """

  use Mix.Task

  alias JidoWorkspace.Roadmap.{Scanner, Filters}

  @shortdoc "Show roadmap task status"

  @switches [
    project: :string,
    type: :string,
    milestone: :integer,
    owner: :string,
    due: :string,
    json: :boolean,
    completed: :boolean
  ]

  def run(args) do
    {opts, _args} = OptionParser.parse!(args, switches: @switches)

    files = 
      Scanner.load_all_files()
      |> apply_filters(opts)

    tasks = Filters.extract_all_tasks(files) |> Filters.sort_by_priority()

    if opts[:json] do
      output_json(tasks)
    else
      output_table(tasks, files, opts)
    end
  end

  defp apply_filters(files, opts) do
    files
    |> Filters.by_project(opts[:project] || "all")
    |> Filters.by_type(parse_type(opts[:type]))
    |> Filters.by_milestone(opts[:milestone])
    |> Filters.by_due_in_days(parse_due_days(opts[:due]))
    |> Filters.by_status(opts[:status])
  end

  defp output_table(tasks, files, opts) do
    if Enum.empty?(tasks) do
      Mix.shell().info("No tasks found matching the criteria.")
    else
      filtered_tasks = 
        tasks
        |> Filters.by_owner(opts[:owner])
        |> Filters.by_completed(opts[:completed])

      rows = 
        filtered_tasks
        |> Enum.map(&task_to_row/1)

      headers = ["ID", "Title", "File", "Owner", "Status", "Estimate"]
      
      TableRex.quick_render!(rows, headers)
      |> Mix.shell().info()

      # Summary
      total = length(filtered_tasks)
      completed = Enum.count(filtered_tasks, & &1.completed)
      pending = total - completed

      Mix.shell().info("\nSummary: #{total} tasks (#{completed} completed, #{pending} pending)")
      Mix.shell().info("Files: #{length(files)} roadmap files scanned")
    end
  end

  defp output_json(tasks) do
    json_data = 
      tasks
      |> Enum.map(fn task ->
        %{
          id: task.id,
          title: task.title,
          completed: task.completed,
          owner: task.owner,
          estimate: task.estimate,
          file_path: task.file_path,
          line_number: task.line_number
        }
      end)

    json_data
    |> Jason.encode!(pretty: true)
    |> Mix.shell().info()
  end

  defp task_to_row(task) do
    file_name = 
      task.file_path
      |> Path.basename()
      |> String.replace_suffix(".md", "")

    project = extract_project_from_path(task.file_path)
    file_display = "#{file_name} (#{project})"

    status = if task.completed, do: "✓ done", else: "pending"

    [
      task.id || "-",
      String.slice(task.title, 0, 40),
      file_display,
      task.owner || "-",
      status,
      task.estimate || "-"
    ]
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

  defp parse_type(nil), do: nil
  defp parse_type(type) when is_binary(type) do
    case String.downcase(type) do
      "milestone" -> :milestone
      "backlog" -> :backlog
      "ideas" -> :ideas
      "version" -> :version
      _ -> nil
    end
  end

  defp parse_due_days(nil), do: nil
  defp parse_due_days(days_str) when is_binary(days_str) do
    case Integer.parse(String.replace(days_str, "d", "")) do
      {days, _} -> days
      _ -> nil
    end
  end
end
