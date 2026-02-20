# Task List Agent Demo
#
# Demonstrates a `Jido.AI.Agent` that breaks goals into tasks,
# stores them in Memory's :tasks space, and works through
# each one to completion.
#
# Run with: mix run lib/examples/scripts/task_list_demo.exs
#
# Expected behavior:
# - Turn 1: Agent decomposes goal into tasks, stores in memory, executes each
# - Turn 2: Agent checks status (tasks persist via Memory plugin)
# - Turn 3: Agent resumes / handles a follow-up goal

Logger.configure(level: :warning)

defmodule Colors do
  def cyan(text), do: "\e[36m#{text}\e[0m"
  def green(text), do: "\e[32m#{text}\e[0m"
  def yellow(text), do: "\e[33m#{text}\e[0m"
  def red(text), do: "\e[31m#{text}\e[0m"
  def dim(text), do: "\e[2m#{text}\e[0m"
  def bold(text), do: "\e[1m#{text}\e[0m"
end

defmodule TaskLogger do
  @moduledoc false

  def print_tasks(pid) do
    alias Jido.Memory.Agent, as: MemoryAgent

    {:ok, server_state} = Jido.AgentServer.state(pid)
    agent = server_state.agent

    strategy_state = agent.state[:__strategy__] || %{}
    conversation = Map.get(strategy_state, :conversation, [])

    tool_msgs =
      Enum.filter(conversation, fn msg ->
        case msg do
          %{role: :tool} -> true
          %{"role" => "tool"} -> true
          _ -> false
        end
      end)

    assistant_tool_calls =
      Enum.filter(conversation, fn msg ->
        case msg do
          %{role: :assistant, tool_calls: tc} when is_list(tc) and tc != [] -> true
          _ -> false
        end
      end)

    if assistant_tool_calls != [] do
      IO.puts(
        Colors.dim(
          "  (#{length(assistant_tool_calls)} assistant turns with tool calls, #{length(tool_msgs)} tool result messages)"
        )
      )

      Enum.take(tool_msgs, 3)
      |> Enum.each(fn msg ->
        content = Map.get(msg, :content) || Map.get(msg, "content", "")
        preview = if is_binary(content), do: String.slice(content, 0, 120), else: inspect(content, limit: 3)
        IO.puts(Colors.dim("    sample: #{preview}"))
      end)
    else
      IO.puts(Colors.dim("  (LLM did not use any task tools)"))
    end

    agent = MemoryAgent.ensure(agent)

    case MemoryAgent.space(agent, :tasks) do
      %{data: tasks} when is_list(tasks) and tasks != [] ->
        IO.puts("\n" <> Colors.yellow("  ┌─ Task List (#{length(tasks)} tasks)"))

        tasks
        |> Enum.sort_by(&(&1["priority"] || 100))
        |> Enum.each(fn task ->
          status_icon = status_icon(task["status"])
          priority = task["priority"] || "-"
          title = task["title"] || "Untitled"
          id = String.slice(task["id"] || "", 0, 8)

          IO.puts(
            Colors.yellow("  │") <>
              "  #{status_icon} " <>
              Colors.dim("[#{id}] ") <>
              Colors.bold(title) <>
              Colors.dim(" (p:#{priority})")
          )

          if task["result"] do
            result_preview = String.slice(task["result"], 0, 80)

            result_preview =
              if String.length(task["result"]) > 80,
                do: result_preview <> "...",
                else: result_preview

            IO.puts(Colors.yellow("  │") <> "     " <> Colors.dim("→ #{result_preview}"))
          end

          if task["blocked_reason"] do
            IO.puts(
              Colors.yellow("  │") <>
                "     " <> Colors.red("⚠ #{task["blocked_reason"]}")
            )
          end
        end)

        summary = summarize(tasks)
        IO.puts(Colors.yellow("  └─ ") <> Colors.dim(summary))

      _ ->
        IO.puts(Colors.dim("  (no tasks in memory)"))
    end

    IO.puts("")
  end

  defp status_icon("done"), do: Colors.green("✓")
  defp status_icon("in_progress"), do: Colors.cyan("◉")
  defp status_icon("blocked"), do: Colors.red("✗")
  defp status_icon("pending"), do: Colors.dim("○")
  defp status_icon(_), do: "?"

  defp summarize(tasks) do
    done = Enum.count(tasks, &(&1["status"] == "done"))
    pending = Enum.count(tasks, &(&1["status"] == "pending"))
    blocked = Enum.count(tasks, &(&1["status"] == "blocked"))
    in_progress = Enum.count(tasks, &(&1["status"] == "in_progress"))

    parts =
      [
        if(done > 0, do: "#{done} done"),
        if(in_progress > 0, do: "#{in_progress} in progress"),
        if(pending > 0, do: "#{pending} pending"),
        if(blocked > 0, do: "#{blocked} blocked")
      ]
      |> Enum.reject(&is_nil/1)

    Enum.join(parts, " · ")
  end
end

# Telemetry: stream LLM tokens and log tool calls
:telemetry.attach_many(
  "task-list-agent-telemetry",
  [
    [:jido, :agent_server, :signal, :start]
  ],
  fn _event, _measurements, metadata, _config ->
    case metadata do
      %{signal_type: "react.llm.delta"} ->
        if delta = get_in(metadata, [:signal, :data, :delta]) do
          IO.write(delta)
        end

      _ ->
        :ok
    end
  end,
  nil
)

# --- Start ---
{:ok, _} = Jido.start()
IO.puts(Colors.green("✓ Jido started"))

alias Jido.AI.Examples.TaskListAgent

IO.puts("Starting TaskListAgent...")
{:ok, pid} = Jido.start_agent(Jido.default_instance(), TaskListAgent)
IO.puts(Colors.green("✓ Agent started: #{inspect(pid)}"))

# --- Turn 1: Plan and execute a goal ---
IO.puts("\n" <> String.duplicate("=", 60))
IO.puts(Colors.cyan("Turn 1: Plan and execute a goal"))
IO.puts(String.duplicate("=", 60))
IO.puts(Colors.dim("Goal: Write a short technical design doc for adding"))
IO.puts(Colors.dim("      user authentication to a web API"))
IO.puts("")

case TaskListAgent.execute(
       pid,
       "Write a short technical design document for adding user authentication to a web API. Cover the approach, key decisions, and security considerations.",
       timeout: 180_000
     ) do
  {:ok, _result} ->
    IO.puts("\n" <> Colors.green("✓ Goal execution complete"))
    TaskLogger.print_tasks(pid)

  {:error, reason} ->
    IO.puts("\n" <> Colors.red("[ERROR] #{inspect(reason)}"))
end

# --- Turn 2: Check task status ---
IO.puts(String.duplicate("=", 60))
IO.puts(Colors.cyan("Turn 2: Check persisted task status"))
IO.puts(String.duplicate("=", 60))
IO.puts(Colors.dim("(Tasks should persist in Memory across requests)"))
IO.puts("")

case TaskListAgent.status(pid, timeout: 60_000) do
  {:ok, _status} ->
    IO.puts("\n" <> Colors.green("✓ Status check complete"))
    TaskLogger.print_tasks(pid)

  {:error, reason} ->
    IO.puts("\n" <> Colors.red("[ERROR] #{inspect(reason)}"))
end

# --- Turn 3: Follow-up request ---
IO.puts(String.duplicate("=", 60))
IO.puts(Colors.cyan("Turn 3: Add new tasks and execute them"))
IO.puts(String.duplicate("=", 60))
IO.puts(Colors.dim("Follow-up: Also cover rate limiting and API key management"))
IO.puts("")

case TaskListAgent.ask_sync(
       pid,
       "Now add tasks to also cover rate limiting and API key management, then execute those new tasks.",
       timeout: 180_000
     ) do
  {:ok, _result} ->
    IO.puts("\n" <> Colors.green("✓ Follow-up complete"))
    TaskLogger.print_tasks(pid)

  {:error, reason} ->
    IO.puts("\n" <> Colors.red("[ERROR] #{inspect(reason)}"))
end

# --- Done ---
IO.puts(String.duplicate("=", 60))
IO.puts(Colors.green("Done - all turns complete!"))
IO.puts(String.duplicate("=", 60) <> "\n")

Jido.stop_agent(Jido.default_instance(), pid)
IO.puts(Colors.green("✓ Agent stopped"))
Jido.stop()
IO.puts(Colors.green("✓ Jido stopped"))
