defmodule JidoWorkspace.Roadmap.Filters do
  @moduledoc """
  Filtering utilities for roadmap files and tasks.
  """

  alias JidoWorkspace.Roadmap.File

  @doc """
  Filters files by project name.
  """
  def by_project(files, "all"), do: files
  def by_project(files, project) when is_binary(project) do
    Enum.filter(files, fn file ->
      File.project(file) == project
    end)
  end

  @doc """
  Filters files by file type.
  """
  def by_type(files, nil), do: files
  def by_type(files, type) when is_atom(type) do
    Enum.filter(files, fn file ->
      File.file_type(file) == type
    end)
  end

  @doc """
  Filters files by milestone number.
  """
  def by_milestone(files, nil), do: files
  def by_milestone(files, milestone) when is_integer(milestone) do
    Enum.filter(files, fn file ->
      File.milestone_number(file) == milestone
    end)
  end

  @doc """
  Filters tasks by owner.
  """
  def by_owner(tasks, nil), do: tasks
  def by_owner(tasks, owner) when is_binary(owner) do
    Enum.filter(tasks, fn task ->
      task.owner == owner or task.owner == "@#{owner}"
    end)
  end

  @doc """
  Filters tasks by completion status.
  """
  def by_completed(tasks, nil), do: tasks
  def by_completed(tasks, completed) when is_boolean(completed) do
    Enum.filter(tasks, fn task ->
      task.completed == completed
    end)
  end

  @doc """
  Filters tasks that have a review date within the specified number of days.
  """
  def by_due_in_days(files, nil), do: files
  def by_due_in_days(files, days) when is_integer(days) do
    target_date = Date.add(Date.utc_today(), days)
    
    Enum.filter(files, fn file ->
      case Map.get(file.meta, :review) do
        nil -> false
        date_string when is_binary(date_string) ->
          case Date.from_iso8601(date_string) do
            {:ok, date} -> Date.compare(date, target_date) != :gt
            _ -> false
          end
        _ -> false
      end
    end)
  end

  @doc """
  Filters tasks by status (from file metadata).
  """
  def by_status(files, nil), do: files
  def by_status(files, status) when is_binary(status) do
    status_atom = String.to_atom(status)
    
    Enum.filter(files, fn file ->
      Map.get(file.meta, :status) == status_atom
    end)
  end

  @doc """
  Extracts all tasks from a list of files.
  """
  def extract_all_tasks(files) do
    Enum.flat_map(files, fn file ->
      file.tasks
    end)
  end

  @doc """
  Filters tasks by task ID pattern.
  """
  def by_task_id(tasks, nil), do: tasks
  def by_task_id(tasks, id_pattern) when is_binary(id_pattern) do
    Enum.filter(tasks, fn task ->
      task.id && String.contains?(String.downcase(task.id), String.downcase(id_pattern))
    end)
  end

  @doc """
  Sorts tasks by priority (based on ID prefix: BUG > FEAT > DOC > others).
  """
  def sort_by_priority(tasks) do
    priority_order = %{"BUG" => 1, "FEAT" => 2, "DOC" => 3, "TRK" => 4}
    
    Enum.sort(tasks, fn task1, task2 ->
      priority1 = get_priority(task1.id, priority_order)
      priority2 = get_priority(task2.id, priority_order)
      
      cond do
        priority1 != priority2 -> priority1 <= priority2
        true -> task1.title <= task2.title
      end
    end)
  end

  # Private helper to get task priority based on ID prefix
  defp get_priority(nil, _), do: 99
  defp get_priority(id, priority_map) do
    prefix = id |> String.split("-") |> List.first()
    Map.get(priority_map, prefix, 99)
  end
end
