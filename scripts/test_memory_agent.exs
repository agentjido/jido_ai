# Memory Agent Demo
#
# Demonstrates that Jido.AI.Memory persists across separate conversations
# on the same agent instance.
#
# Run with: mix run scripts/test_memory_agent.exs
#
# Flow:
#   1. Store facts via natural language (agent uses memory_store tool)
#   2. Ask about stored facts in a NEW conversation (agent uses memory_recall tool)
#   3. Forget a fact, then confirm it's gone
#   4. Verify the ETS backend directly to show what's stored

Logger.configure(level: :warning)

defmodule Colors do
  def cyan(text), do: "\e[36m#{text}\e[0m"
  def green(text), do: "\e[32m#{text}\e[0m"
  def yellow(text), do: "\e[33m#{text}\e[0m"
  def red(text), do: "\e[31m#{text}\e[0m"
  def dim(text), do: "\e[2m#{text}\e[0m"
  def bold(text), do: "\e[1m#{text}\e[0m"
end

# Attach telemetry handler for streaming tokens
:telemetry.attach(
  "memory-agent-stream",
  [:jido, :agent_server, :signal, :start],
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

IO.puts("\n" <> Colors.bold("=" |> String.duplicate(60)))
IO.puts(Colors.bold("  Jido.AI.Memory Demo — Cross-Conversation Recall"))
IO.puts(Colors.bold("=" |> String.duplicate(60)))

# Start Jido and the memory agent
{:ok, _jido} = Jido.start_link(name: MemoryDemo.Jido)
alias Jido.AI.Examples.MemoryAgent
{:ok, pid} = Jido.start_agent(MemoryDemo.Jido, MemoryAgent)
IO.puts(Colors.green("✓ MemoryAgent started\n"))

timeout = [timeout: 60_000]

# ── Phase 1: Store facts ──────────────────────────────────────────────
IO.puts(Colors.cyan("━━━ Phase 1: Storing facts ━━━"))

store_prompts = [
  "My name is Alice and I live in Portland.",
  "My favorite color is teal and I love hiking."
]

for {prompt, i} <- Enum.with_index(store_prompts, 1) do
  IO.puts("\n" <> Colors.yellow("[Store #{i}] ") <> prompt)
  IO.puts(Colors.dim("─" |> String.duplicate(50)))

  case MemoryAgent.ask_sync(pid, prompt, timeout) do
    {:ok, reply} ->
      IO.puts("\n" <> Colors.green("Agent: ") <> reply)

    {:error, reason} ->
      IO.puts("\n" <> Colors.red("ERROR: #{inspect(reason)}"))
  end

  IO.puts("")
end

# ── Phase 2: Recall in new conversations ──────────────────────────────
IO.puts(Colors.cyan("━━━ Phase 2: Recalling across conversations ━━━"))
IO.puts(Colors.dim("(Each ask is a fresh ReAct conversation — memory persists in ETS)"))

recall_prompts = [
  "What is my name?",
  "Where do I live?",
  "What's my favorite color and hobby?"
]

for {prompt, i} <- Enum.with_index(recall_prompts, 1) do
  IO.puts("\n" <> Colors.yellow("[Recall #{i}] ") <> prompt)
  IO.puts(Colors.dim("─" |> String.duplicate(50)))

  case MemoryAgent.ask_sync(pid, prompt, timeout) do
    {:ok, reply} ->
      IO.puts("\n" <> Colors.green("Agent: ") <> reply)

    {:error, reason} ->
      IO.puts("\n" <> Colors.red("ERROR: #{inspect(reason)}"))
  end

  IO.puts("")
end

# ── Phase 3: Forget and verify ────────────────────────────────────────
IO.puts(Colors.cyan("━━━ Phase 3: Forget and verify ━━━"))

IO.puts("\n" <> Colors.yellow("[Forget] ") <> "Forget my favorite color.")
IO.puts(Colors.dim("─" |> String.duplicate(50)))

case MemoryAgent.ask_sync(pid, "Forget my favorite color.", timeout) do
  {:ok, reply} ->
    IO.puts("\n" <> Colors.green("Agent: ") <> reply)

  {:error, reason} ->
    IO.puts("\n" <> Colors.red("ERROR: #{inspect(reason)}"))
end

IO.puts("")

IO.puts("\n" <> Colors.yellow("[Verify] ") <> "What is my favorite color?")
IO.puts(Colors.dim("─" |> String.duplicate(50)))

case MemoryAgent.ask_sync(pid, "What is my favorite color?", timeout) do
  {:ok, reply} ->
    IO.puts("\n" <> Colors.green("Agent: ") <> reply)

  {:error, reason} ->
    IO.puts("\n" <> Colors.red("ERROR: #{inspect(reason)}"))
end

# ── Phase 4: Inspect ETS directly ─────────────────────────────────────
IO.puts("\n\n" <> Colors.cyan("━━━ Phase 4: Raw ETS contents ━━━"))
IO.puts(Colors.dim("(Direct view of what the agent stored in memory)\n"))

case :ets.whereis(:jido_ai_memory) do
  :undefined ->
    IO.puts(Colors.yellow("  No ETS table found (nothing was stored)"))

  _tid ->
    entries = :ets.tab2list(:jido_ai_memory)

    if entries == [] do
      IO.puts(Colors.yellow("  Table exists but is empty"))
    else
      for {{agent_id, key}, entry} <- Enum.sort(entries) do
        IO.puts(
          "  #{Colors.dim(agent_id)} │ " <>
            Colors.bold(key) <>
            " = #{inspect(entry.value)}" <>
            if(entry.tags != [], do: "  #{Colors.dim("tags: #{inspect(entry.tags)}")}", else: "")
        )
      end
    end
end

# Cleanup
IO.puts("")
GenServer.stop(pid)
IO.puts(Colors.green("✓ Agent stopped"))
IO.puts(Colors.bold("=" |> String.duplicate(60)) <> "\n")
