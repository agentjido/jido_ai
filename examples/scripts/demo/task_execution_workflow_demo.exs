Code.require_file(Path.expand("../shared/bootstrap.exs", __DIR__))

alias Jido.AI.Examples.Scripts.Bootstrap
alias Jido.AI.Examples.Tools.TaskList.{AddTasks, CompleteTask, GetState, NextTask, StartTask}

defmodule TaskExecutionWorkflowDemo.Helpers do
  def context(tasks), do: %{tasks: tasks}

  def replace_task(tasks, updated_task) do
    Enum.map(tasks, fn task ->
      if task["id"] == updated_task["id"], do: updated_task, else: task
    end)
  end
end

Bootstrap.init!()
Bootstrap.print_banner("Task Execution Workflow Demo")

seed_tasks = [
  %{
    "title" => "Validate release metadata",
    "description" => "Check mix.exs version, changelog notes, and package metadata.",
    "priority" => 10
  },
  %{
    "title" => "Run quality gates",
    "description" => "Run tests and quality checks before publishing.",
    "priority" => 20
  },
  %{
    "title" => "Publish beta package",
    "description" => "Perform dry run and publish to Hex with release notes.",
    "priority" => 30
  }
]

{:ok, add_result} = AddTasks.run(%{tasks: seed_tasks}, %{})
Bootstrap.assert!(add_result.action == "tasks_added", "Task workflow did not run tasklist_add_tasks.")

initial_tasks = add_result.created_tasks
Bootstrap.assert!(length(initial_tasks) == 3, "Task workflow did not create the expected task count.")

{final_tasks, lifecycle_events} =
  Enum.reduce_while(1..10, {initial_tasks, []}, fn step, {tasks, events} ->
    {:ok, next_task} = NextTask.run(%{}, TaskExecutionWorkflowDemo.Helpers.context(tasks))

    case next_task.status do
      "next_task" ->
        task = next_task.task
        {:ok, started} = StartTask.run(%{task_id: task["id"]}, TaskExecutionWorkflowDemo.Helpers.context(tasks))

        tasks = TaskExecutionWorkflowDemo.Helpers.replace_task(tasks, started.task)

        {:ok, completed} =
          CompleteTask.run(
            %{task_id: task["id"], result: "Completed workflow step #{step} for #{task["title"]}."},
            TaskExecutionWorkflowDemo.Helpers.context(tasks)
          )

        tasks = TaskExecutionWorkflowDemo.Helpers.replace_task(tasks, completed.task)
        events = events ++ [started.action, completed.action]
        {:cont, {tasks, events}}

      "all_complete" ->
        {:halt, {tasks, events}}

      other ->
        raise "Unexpected tasklist_next_task status: #{inspect(other)}"
    end
  end)

{:ok, state} = GetState.run(%{}, TaskExecutionWorkflowDemo.Helpers.context(final_tasks))

Bootstrap.assert!(
  "task_started" in lifecycle_events and "task_completed" in lifecycle_events,
  "Task workflow did not perform start/complete lifecycle transitions."
)

Bootstrap.assert!(
  Enum.all?(final_tasks, &(&1["status"] == "done")),
  "Task workflow did not finish all tasks."
)

Bootstrap.assert!(state.all_complete, "Task workflow did not reach all_complete state.")

IO.puts("✓ Tasks tracked: #{length(final_tasks)}")
IO.puts("✓ Lifecycle events: #{Enum.join(lifecycle_events, ", ")}")
IO.puts("✓ Task execution workflow demo passed semantic checks")
