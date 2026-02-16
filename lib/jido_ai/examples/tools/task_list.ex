defmodule Jido.AI.Examples.Tools.TaskList do
  @moduledoc """
  LLM tools for task list management in a `Jido.AI.Agent`.

  These tools manage tasks stored in the agent's Memory `:tasks` space.
  The current task list is injected into `tool_context` by the agent's
  `on_before_cmd/2` callback, and task mutations are persisted back
  via `on_after_cmd/3`.

  ## Task Structure

  Each task is a map with these fields:
  - `id` - Unique identifier (auto-generated UUID)
  - `title` - Short description of the task
  - `description` - Detailed description (optional)
  - `status` - One of: "pending", "in_progress", "done", "blocked"
  - `result` - Completion result or notes (optional)
  - `blocked_reason` - Why the task is blocked (optional)
  - `priority` - Integer priority, lower is higher (optional)
  - `created_at` - ISO 8601 timestamp
  - `updated_at` - ISO 8601 timestamp
  """
end

defmodule Jido.AI.Examples.Tools.TaskList.AddTasks do
  @moduledoc "Add one or more tasks to the task list."

  use Jido.Action,
    name: "tasklist_add_tasks",
    description:
      "Add new tasks to the task list. Each task needs a title and optional description. Returns the created tasks with generated IDs.",
    schema:
      Zoi.object(%{
        tasks:
          Zoi.list(
            Zoi.object(%{
              title: Zoi.string(description: "Short title for the task"),
              description: Zoi.string(description: "Detailed description of the task") |> Zoi.optional(),
              priority:
                Zoi.integer(description: "Priority number, lower is higher priority (1-100)")
                |> Zoi.optional()
            }),
            description: "List of tasks to add. Each must have a title, optional description and priority."
          )
      })

  @impl true
  def run(%{tasks: tasks}, _context) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    created_tasks =
      Enum.map(tasks, fn task ->
        title = Map.get(task, :title) || Map.get(task, "title", "Untitled")
        desc = Map.get(task, :description) || Map.get(task, "description")
        pri = Map.get(task, :priority) || Map.get(task, "priority", 100)

        %{
          "id" => generate_id(),
          "title" => title,
          "description" => desc,
          "status" => "pending",
          "result" => nil,
          "blocked_reason" => nil,
          "priority" => pri,
          "created_at" => now,
          "updated_at" => now
        }
      end)

    {:ok,
     %{
       action: "tasks_added",
       created_tasks: created_tasks,
       count: length(created_tasks),
       message: "Added #{length(created_tasks)} task(s) to the list."
     }}
  end

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end
end

defmodule Jido.AI.Examples.Tools.TaskList.GetState do
  @moduledoc "Get the current state of the task list."

  use Jido.Action,
    name: "tasklist_get_state",
    description:
      "Get the current task list state including all tasks and summary counts. Use this to understand what tasks exist and their current status.",
    schema: [
      status_filter: [
        type: :string,
        required: false,
        doc: "Optional filter: 'pending', 'in_progress', 'done', 'blocked', or 'all' (default: 'all')"
      ]
    ]

  @impl true
  def run(params, context) do
    tasks = get_tasks_from_context(context)
    filter = Map.get(params, :status_filter, "all")

    filtered =
      if filter == "all" do
        tasks
      else
        Enum.filter(tasks, fn t -> t["status"] == filter end)
      end

    summary = %{
      total: length(tasks),
      pending: Enum.count(tasks, &(&1["status"] == "pending")),
      in_progress: Enum.count(tasks, &(&1["status"] == "in_progress")),
      done: Enum.count(tasks, &(&1["status"] == "done")),
      blocked: Enum.count(tasks, &(&1["status"] == "blocked"))
    }

    {:ok,
     %{
       tasks: filtered,
       summary: summary,
       all_complete:
         summary.pending == 0 and summary.in_progress == 0 and summary.blocked == 0 and
           summary.total > 0
     }}
  end

  defp get_tasks_from_context(context) do
    cond do
      is_list(context[:tasks]) -> context[:tasks]
      match?(%{tool_context: %{tasks: t}} when is_list(t), context) -> context.tool_context.tasks
      true -> []
    end
  end
end

defmodule Jido.AI.Examples.Tools.TaskList.NextTask do
  @moduledoc "Get the next task to work on."

  use Jido.Action,
    name: "tasklist_next_task",
    description:
      "Get the next pending task to work on (highest priority first). Returns the task details or indicates all tasks are complete.",
    schema: []

  @impl true
  def run(_params, context) do
    tasks = get_tasks_from_context(context)

    next =
      tasks
      |> Enum.filter(&(&1["status"] == "pending"))
      |> Enum.sort_by(&(&1["priority"] || 100))
      |> List.first()

    in_progress = Enum.filter(tasks, &(&1["status"] == "in_progress"))
    done_count = Enum.count(tasks, &(&1["status"] == "done"))
    total = length(tasks)

    case {next, in_progress} do
      {nil, []} when total == 0 ->
        {:ok, %{status: "no_tasks", message: "No tasks in the list. Add tasks first."}}

      {nil, []} ->
        {:ok,
         %{
           status: "all_complete",
           message: "All #{done_count} tasks are complete!",
           done: done_count,
           total: total
         }}

      {nil, in_prog} ->
        {:ok,
         %{
           status: "tasks_in_progress",
           in_progress: in_prog,
           message: "#{length(in_prog)} task(s) currently in progress."
         }}

      {task, _} ->
        remaining = Enum.count(tasks, &(&1["status"] == "pending"))

        {:ok,
         %{
           status: "next_task",
           task: task,
           remaining_pending: remaining,
           done: done_count,
           total: total
         }}
    end
  end

  defp get_tasks_from_context(context) do
    cond do
      is_list(context[:tasks]) -> context[:tasks]
      match?(%{tool_context: %{tasks: t}} when is_list(t), context) -> context.tool_context.tasks
      true -> []
    end
  end
end

defmodule Jido.AI.Examples.Tools.TaskList.StartTask do
  @moduledoc "Mark a task as in-progress."

  use Jido.Action,
    name: "tasklist_start_task",
    description: "Mark a task as in-progress. Use this before starting work on a task.",
    schema: [
      task_id: [type: :string, required: true, doc: "The ID of the task to start"]
    ]

  @impl true
  def run(%{task_id: task_id}, context) do
    tasks = get_tasks_from_context(context)

    case Enum.find(tasks, &(&1["id"] == task_id)) do
      nil ->
        {:ok,
         %{
           action: "task_not_found",
           task_id: task_id,
           message: "Task '#{task_id}' not found."
         }}

      task ->
        updated_task = %{
          task
          | "status" => "in_progress",
            "updated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        }

        {:ok,
         %{
           action: "task_started",
           task: updated_task,
           message: "Started task: #{task["title"]}"
         }}
    end
  end

  defp get_tasks_from_context(context) do
    cond do
      is_list(context[:tasks]) -> context[:tasks]
      match?(%{tool_context: %{tasks: t}} when is_list(t), context) -> context.tool_context.tasks
      true -> []
    end
  end
end

defmodule Jido.AI.Examples.Tools.TaskList.CompleteTask do
  @moduledoc "Mark a task as complete with an optional result."

  use Jido.Action,
    name: "tasklist_complete_task",
    description: "Mark a task as done. Include a result describing what was accomplished.",
    schema: [
      task_id: [type: :string, required: true, doc: "The ID of the task to complete"],
      result: [type: :string, required: false, doc: "Description of what was accomplished"]
    ]

  @impl true
  def run(%{task_id: task_id} = params, context) do
    tasks = get_tasks_from_context(context)
    result = Map.get(params, :result)

    case Enum.find(tasks, &(&1["id"] == task_id)) do
      nil ->
        {:ok,
         %{
           action: "task_not_found",
           task_id: task_id,
           message: "Task '#{task_id}' not found."
         }}

      task ->
        updated_task = %{
          task
          | "status" => "done",
            "result" => result,
            "updated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        }

        remaining =
          Enum.count(tasks, &(&1["status"] == "pending")) -
            if(task["status"] == "pending", do: 1, else: 0)

        {:ok,
         %{
           action: "task_completed",
           task: updated_task,
           remaining_pending: max(remaining, 0),
           message: "Completed task: #{task["title"]}"
         }}
    end
  end

  defp get_tasks_from_context(context) do
    cond do
      is_list(context[:tasks]) -> context[:tasks]
      match?(%{tool_context: %{tasks: t}} when is_list(t), context) -> context.tool_context.tasks
      true -> []
    end
  end
end

defmodule Jido.AI.Examples.Tools.TaskList.BlockTask do
  @moduledoc "Mark a task as blocked with a reason."

  use Jido.Action,
    name: "tasklist_block_task",
    description: "Mark a task as blocked when it cannot proceed. Provide a reason explaining the blocker.",
    schema: [
      task_id: [type: :string, required: true, doc: "The ID of the task to block"],
      reason: [type: :string, required: true, doc: "Why the task is blocked"]
    ]

  @impl true
  def run(%{task_id: task_id, reason: reason}, context) do
    tasks = get_tasks_from_context(context)

    case Enum.find(tasks, &(&1["id"] == task_id)) do
      nil ->
        {:ok,
         %{
           action: "task_not_found",
           task_id: task_id,
           message: "Task '#{task_id}' not found."
         }}

      task ->
        updated_task = %{
          task
          | "status" => "blocked",
            "blocked_reason" => reason,
            "updated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        }

        {:ok,
         %{
           action: "task_blocked",
           task: updated_task,
           message: "Blocked task '#{task["title"]}': #{reason}"
         }}
    end
  end

  defp get_tasks_from_context(context) do
    cond do
      is_list(context[:tasks]) -> context[:tasks]
      match?(%{tool_context: %{tasks: t}} when is_list(t), context) -> context.tool_context.tasks
      true -> []
    end
  end
end

defmodule Jido.AI.Examples.Tools.TaskList.UpdateTask do
  @moduledoc "Update a task's title, description, or priority."

  use Jido.Action,
    name: "tasklist_update_task",
    description: "Update a task's title, description, or priority.",
    schema: [
      task_id: [type: :string, required: true, doc: "The ID of the task to update"],
      title: [type: :string, required: false, doc: "New title for the task"],
      description: [type: :string, required: false, doc: "New description for the task"],
      priority: [type: :integer, required: false, doc: "New priority (lower = higher priority)"]
    ]

  @impl true
  def run(%{task_id: task_id} = params, context) do
    tasks = get_tasks_from_context(context)

    case Enum.find(tasks, &(&1["id"] == task_id)) do
      nil ->
        {:ok,
         %{
           action: "task_not_found",
           task_id: task_id,
           message: "Task '#{task_id}' not found."
         }}

      task ->
        updated_task =
          task
          |> maybe_update("title", params[:title])
          |> maybe_update("description", params[:description])
          |> maybe_update("priority", params[:priority])
          |> Map.put("updated_at", DateTime.utc_now() |> DateTime.to_iso8601())

        {:ok,
         %{
           action: "task_updated",
           task: updated_task,
           message: "Updated task: #{updated_task["title"]}"
         }}
    end
  end

  defp maybe_update(task, _key, nil), do: task
  defp maybe_update(task, key, value), do: Map.put(task, key, value)

  defp get_tasks_from_context(context) do
    cond do
      is_list(context[:tasks]) -> context[:tasks]
      match?(%{tool_context: %{tasks: t}} when is_list(t), context) -> context.tool_context.tasks
      true -> []
    end
  end
end
