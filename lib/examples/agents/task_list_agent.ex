defmodule Jido.AI.Examples.TaskListAgent do
  @moduledoc """
  Agent for task list management and execution (`Jido.AI.Agent`, ReAct strategy implied).

  Demonstrates iterative task planning and execution:
  1. Receives a goal or objective from the user
  2. Decomposes it into concrete, actionable tasks
  3. Stores tasks in the agent's Memory `:tasks` space
  4. Works through each task systematically
  5. Reports progress and results

  **Why ReAct?** Task management is inherently iterative - you plan, execute,
  discover blockers, re-prioritize, and adapt. ReAct enables:
  plan → execute → observe → adjust → complete.

  ## Usage

      # Start the agent
      {:ok, pid} = Jido.AgentServer.start(agent: Jido.AI.Examples.TaskListAgent)

      # Give it a goal
      {:ok, result} = Jido.AI.Examples.TaskListAgent.ask_sync(pid,
        "Plan and execute a code review process for a new PR")

      # Or check task state
      {:ok, result} = Jido.AI.Examples.TaskListAgent.ask_sync(pid,
        "What tasks are remaining?")

  ## CLI Usage

      mix jido_ai --agent Jido.AI.Examples.TaskListAgent \\
        "Create a plan to set up a CI/CD pipeline for an Elixir project"

      mix jido_ai --agent Jido.AI.Examples.TaskListAgent \\
        "Help me organize a product launch - what needs to happen?"

  ## How It Works

  The agent uses Memory's `:tasks` list space as persistent storage:

  1. `on_before_cmd/2` loads tasks from Memory and injects them into `tool_context`
  2. The LLM uses task list tools to plan and track work
  3. `on_after_cmd/3` processes tool results and syncs state back to Memory
  4. Tasks persist across ReAct iterations within a request

  Task state flows: Memory → tool_context → tools → LLM → tool calls → Memory
  """

  alias Jido.Memory.Agent, as: MemoryAgent

  use Jido.AI.Agent,
    name: "task_list_agent",
    description: "Task planning and execution agent that breaks goals into tasks and works through them",
    tools: [
      Jido.AI.Examples.Tools.TaskList.AddTasks,
      Jido.AI.Examples.Tools.TaskList.GetState,
      Jido.AI.Examples.Tools.TaskList.NextTask,
      Jido.AI.Examples.Tools.TaskList.StartTask,
      Jido.AI.Examples.Tools.TaskList.CompleteTask,
      Jido.AI.Examples.Tools.TaskList.BlockTask,
      Jido.AI.Examples.Tools.TaskList.UpdateTask
    ],
    system_prompt: """
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
    """,
    max_iterations: 25

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

  # --- Lifecycle Callbacks ---

  @impl true
  def on_before_cmd(agent, {:ai_react_start, %{query: _query} = params} = _action) do
    {request_id, params} = Request.ensure_request_id(params)

    agent = MemoryAgent.ensure(agent)

    tasks = load_tasks(agent)

    existing_context = Map.get(params, :tool_context, %{})
    new_context = Map.merge(existing_context, %{tasks: tasks, request_id: request_id})
    updated_params = Map.put(params, :tool_context, new_context)

    agent = Request.start_request(agent, request_id, params[:query])

    {:ok, agent, {:ai_react_start, updated_params}}
  end

  @impl true
  def on_before_cmd(agent, action), do: {:ok, agent, action}

  @impl true
  def on_after_cmd(agent, {:ai_react_start, %{request_id: request_id}}, directives) do
    snap = strategy_snapshot(agent)
    agent = sync_tasks_from_conversation(agent, snap)
    agent = refresh_tool_context_tasks(agent)

    agent =
      if snap.done? do
        Request.complete_request(agent, request_id, snap.result)
      else
        agent
      end

    {:ok, agent, directives}
  end

  @impl true
  def on_after_cmd(agent, _action, directives) do
    snap = strategy_snapshot(agent)
    agent = sync_tasks_from_conversation(agent, snap)
    agent = refresh_tool_context_tasks(agent)

    agent =
      if snap.done? do
        agent = %{
          agent
          | state:
              Map.merge(agent.state, %{
                last_answer: snap.result || "",
                completed: true
              })
        }

        case agent.state[:last_request_id] do
          nil -> agent
          request_id -> Request.complete_request(agent, request_id, snap.result)
        end
      else
        agent
      end

    {:ok, agent, directives}
  end

  # --- Private Helpers ---

  defp load_tasks(agent) do
    case MemoryAgent.space(agent, :tasks) do
      %{data: tasks} when is_list(tasks) -> tasks
      _ -> []
    end
  end

  defp sync_tasks_from_conversation(agent, snap) do
    details = Map.get(snap, :details, %{})
    conversation = Map.get(details, :conversation, [])

    tasks = extract_tasks_from_conversation(conversation, load_tasks(agent))
    persist_tasks(agent, tasks)
  end

  defp extract_tasks_from_conversation(conversation, current_tasks) do
    tool_results =
      conversation
      |> Enum.filter(fn msg ->
        case msg do
          %{role: :tool} -> true
          %{"role" => "tool"} -> true
          _ -> false
        end
      end)
      |> Enum.flat_map(fn msg ->
        content = Map.get(msg, :content) || Map.get(msg, "content", "")
        parse_tool_results(content)
      end)

    Enum.reduce(tool_results, current_tasks, &apply_task_action/2)
  end

  defp parse_tool_results(content) when is_binary(content) do
    case Jason.decode(content) do
      {:ok, decoded} -> extract_actionable(decoded)
      _ -> []
    end
  end

  defp parse_tool_results(content) when is_map(content), do: extract_actionable(content)
  defp parse_tool_results(_), do: []

  defp extract_actionable(%{"action" => _} = result), do: [result]
  defp extract_actionable(%{"created_tasks" => _} = result), do: [result]
  defp extract_actionable(_), do: []

  defp apply_task_action(%{"action" => "tasks_added", "created_tasks" => new_tasks}, current_tasks) do
    existing_ids = MapSet.new(current_tasks, & &1["id"])
    to_add = Enum.reject(new_tasks, fn t -> MapSet.member?(existing_ids, t["id"]) end)
    current_tasks ++ to_add
  end

  defp apply_task_action(%{"created_tasks" => new_tasks}, current_tasks) do
    existing_ids = MapSet.new(current_tasks, & &1["id"])
    to_add = Enum.reject(new_tasks, fn t -> MapSet.member?(existing_ids, t["id"]) end)
    current_tasks ++ to_add
  end

  defp apply_task_action(%{"action" => action, "task" => updated_task}, current_tasks)
       when action in ["task_started", "task_completed", "task_blocked", "task_updated"] do
    task_id = updated_task["id"]

    Enum.map(current_tasks, fn t ->
      if t["id"] == task_id, do: updated_task, else: t
    end)
  end

  defp apply_task_action(_, current_tasks), do: current_tasks

  defp refresh_tool_context_tasks(agent) do
    tasks = load_tasks(agent)
    strategy_state = agent.state[:__strategy__] || %{}
    run_ctx = Map.get(strategy_state, :run_tool_context, %{})
    updated_ctx = Map.put(run_ctx, :tasks, tasks)
    updated_strategy = Map.put(strategy_state, :run_tool_context, updated_ctx)
    %{agent | state: Map.put(agent.state, :__strategy__, updated_strategy)}
  end

  defp persist_tasks(agent, tasks) do
    agent = MemoryAgent.ensure(agent)

    MemoryAgent.update_space(agent, :tasks, fn space ->
      %{space | data: tasks}
    end)
  end
end
