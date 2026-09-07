defmodule Jido.AI.Examples.TaskListAgent do
  @moduledoc """
  Plans and completes tasks through a native AI Flow.

  The Agent stores tasks in its schema. Each successful tool result proposes
  the next task list. The Agent validates and commits that state before the
  next tool reads it. Tasks remain available across requests and checkpoints.

      {:ok, pid} = Jido.AgentServer.start(agent: __MODULE__)
      {:ok, result} = __MODULE__.execute(pid, "Review a new pull request")
  """
  use Jido.Agent, name: "task_list_agent", extensions: [Jido.AI.DSL]
  @behaviour Jido.AI.ToolInterceptor

  agent do
    schema(
      Zoi.object(%{
        tasks: Zoi.list(Zoi.map()) |> Zoi.default([]),
        last_answer: Zoi.string() |> Zoi.default(""),
        messages: Zoi.list(Zoi.any()) |> Zoi.default([])
      })
    )

    ai :assistant do
      instructions("""
      You are a task planning and execution agent. You MUST use the tasklist tools
      to manage your work. NEVER skip the tools and answer directly.

      IMPORTANT: Call exactly ONE tool per message. Never batch multiple tool calls
      in a single response. Wait for each tool's result before calling the next tool.

      MANDATORY WORKFLOW (you MUST follow these steps every time):
      1. Call tasklist_get_state to check for existing tasks
      2. If no tasks exist for this goal, call tasklist_add_tasks to create 3-7 tasks
      3. Call tasklist_next_task to get the next pending task
      4. For each task:
       a. Call tasklist_start_task with the task_id
       b. Do the work (reason, research, produce output)
       c. Call tasklist_complete_task with the task_id and a substantive result
      5. Call tasklist_next_task again for the next task
      6. Repeat steps 4-5 until tasklist_next_task returns "all_complete"
      7. Only THEN provide your final summary

      CRITICAL RULES:
      - Call exactly ONE tool per message, never multiple
      - You MUST call tasklist_start_task before working on each task
      - You MUST call tasklist_complete_task after finishing each task
      - NEVER produce a final answer without first completing all tasks via tools
      - If a task cannot be completed, call tasklist_block_task with the reason
      - Provide detailed, substantive results when completing tasks
      - Use lower priority numbers (1-10) for prerequisite tasks
      - Use medium priority (11-50) for core work
      - Use higher priority (51-100) for polish/optional tasks

      REQUIRED ARGUMENT SHAPES:
      - tasklist_add_tasks expects:
      {"tasks":[{"title":"...", "description":"...", "priority":10}]}
      - tasklist_start_task expects:
      {"task_id":"<id>"}
      - tasklist_complete_task expects:
      {"task_id":"<id>", "result":"what was accomplished"}
      """)

      effect_policy(%{allow: [Jido.AI.Effects.State]})

      models do
        model(:answer, :fast)
      end

      reasoning :react do
        model(:answer)
        tool_concurrency(1)
        effect_policy(%{mode: :allow_all})
      end

      controls do
        max_iterations(25)
      end

      tools do
        action(Jido.AI.Examples.Tools.TaskList.AddTasks, as: :tasklist_add_tasks, forward_context: [:agent_state])
        action(Jido.AI.Examples.Tools.TaskList.GetState, as: :tasklist_get_state, forward_context: [:agent_state])
        action(Jido.AI.Examples.Tools.TaskList.NextTask, as: :tasklist_next_task, forward_context: [:agent_state])
        action(Jido.AI.Examples.Tools.TaskList.StartTask, as: :tasklist_start_task, forward_context: [:agent_state])

        action(Jido.AI.Examples.Tools.TaskList.CompleteTask,
          as: :tasklist_complete_task,
          forward_context: [:agent_state]
        )

        action(Jido.AI.Examples.Tools.TaskList.BlockTask, as: :tasklist_block_task, forward_context: [:agent_state])
        action(Jido.AI.Examples.Tools.TaskList.UpdateTask, as: :tasklist_update_task, forward_context: [:agent_state])
      end

      requests do
        mode(:session)
      end

      memory do
        history(:messages)
      end

      result(nil, into: :last_answer)
    end
  end

  routes do
    route("ai.react.query", ai(:assistant))
  end

  def ask(server, query, opts \\ []) do
    Jido.AI.Request.create_and_send(
      server,
      query,
      Keyword.merge(opts, signal_type: "ai.react.query", source: "/examples/task-list")
    )
  end

  def await(request, opts \\ []), do: Jido.AI.Request.await(request, opts)

  def ask_sync(server, query, opts \\ []) do
    with {:ok, request} <- ask(server, query, opts), do: await(request, opts)
  end

  def cli_adapter, do: Jido.AI.Reasoning.ReAct.CLIAdapter

  @default_timeout 120_000

  @doc """
  Plan tasks for a goal without executing them.

  ## Examples

      {:ok, plan} = TaskListAgent.plan(pid, "Set up a Phoenix project")

  """
  @spec plan(pid(), String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def plan(pid, goal, opts \\ []) do
    query = """
    Plan the following goal by creating a task list, but DO NOT execute the tasks yet.
    Just create the plan and show me the task list.

    Goal: #{goal}
    """

    ask_sync(pid, query, Keyword.put_new(opts, :timeout, @default_timeout))
  end

  @doc """
  Execute a goal by planning and completing all tasks.

  ## Examples

      {:ok, result} = TaskListAgent.execute(pid, "Write a README for a new library")

  """
  @spec execute(pid(), String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def execute(pid, goal, opts \\ []) do
    query = """
    Plan and execute the following goal. Break it into tasks, then work through
    each task to completion. Provide the results of each task as you complete it.

    Goal: #{goal}
    """

    ask_sync(pid, query, Keyword.put_new(opts, :timeout, @default_timeout))
  end

  @doc """
  Check the current status of all tasks.

  ## Examples

      {:ok, status} = TaskListAgent.status(pid)

  """
  @spec status(pid(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def status(pid, opts \\ []) do
    ask_sync(
      pid,
      "Show me the current status of all tasks. Include task IDs, titles, and statuses.",
      Keyword.put_new(opts, :timeout, @default_timeout)
    )
  end

  @doc """
  Resume working on remaining tasks.

  ## Examples

      {:ok, result} = TaskListAgent.resume(pid)

  """
  @spec resume(pid(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def resume(pid, opts \\ []) do
    ask_sync(
      pid,
      "Check the current task list and continue working on any pending or in-progress tasks until all are complete.",
      Keyword.put_new(opts, :timeout, @default_timeout)
    )
  end

  @impl true
  def after_tool_call(_call, {:ok, result, effects}, %{agent_state: state}) when is_map(result) do
    next_tasks = apply_task_action(result, state.tasks)
    next = Jido.AI.Effects.state(%{state | tasks: next_tasks})
    {:ok, {:ok, result, effects ++ [next]}}
  end

  def after_tool_call(_call, result, _context), do: {:ok, result}

  defp apply_task_action(%{created_tasks: tasks}, current) do
    ids = MapSet.new(current, & &1["id"])
    current ++ Enum.reject(tasks, &MapSet.member?(ids, &1["id"]))
  end

  defp apply_task_action(%{action: action, task: updated}, current)
       when action in ["task_started", "task_completed", "task_blocked", "task_updated"] do
    Enum.map(current, fn task -> if task["id"] == updated["id"], do: updated, else: task end)
  end

  defp apply_task_action(_, current), do: current
end
