#!/usr/bin/env env elixir

# ReAct Strategy Example
#
# Run this example with:
#   mix run examples/strategies/react_agent.exs
#
# This example demonstrates the ReAct (Reason-Act) strategy which
# combines step-by-step reasoning with tool use.

Application.ensure_all_started(:jido_ai)

IO.puts("\n=== ReAct Strategy Example ===\n")

# Example 1: Understanding ReAct
IO.puts("Example 1: How ReAct works")
IO.puts("----------------------------")

IO.puts("""
ReAct (Reason-Act) combines:
1. Reasoning: Think step-by-step about the problem
2. Acting: Use tools when needed
3. Observing: Process tool results
4. Repeating: Continue until final answer

Flow:
  User Query → LLM (with tools) → Thought → Action → Observation → Thought → ... → Answer

Example:
  Thought: I need to calculate 15 * 23
  Action: calculator(a=15, b=23, operation="multiply")
  Observation: 345
  Thought: Now I have the answer
  Answer: 15 * 23 = 345
""")

# Example 2: Simple ReAct agent definition
IO.puts("\n\nExample 2: Defining a ReAct agent")
IO.puts("----------------------------------")

agent_definition = """
defmodule MyApp.CalculatorAgent do
  use Jido.AI.ReActAgent,
    name: "calculator_agent",
    tools: [
    MyApp.Actions.Calculator,
    MyApp.Actions.Search
  ],
    model: :fast,
    max_iterations: 10,
    system_prompt: \"\"\"
    You are a helpful assistant that can calculate things
    and search for information. Think step by step.
    \"\"\"
end
"""

IO.puts(agent_definition)

# Example 3: Calculator action
IO.puts("\n\nExample 3: Calculator action for tools")
IO.puts("---------------------------------------")

calculator_action = """
defmodule MyApp.Actions.Calculator do
  use Jido.Action,
    name: "calculator",
    description: "Performs arithmetic operations"

  @schema Zoi.struct(__MODULE__, %{
    a: Zoi.number(description: "First number") |> Zoi.required(),
    b: Zoi.number(description: "Second number") |> Zoi.required(),
    operation: Zoi.string(description: "Operation: add, subtract, multiply, divide")
      |> Zoi.default("add")
  }, coerce: true)

  def run(%{a: a, b: b, operation: op}, _context) do
    result = case op do
      "add" -> a + b
      "subtract" -> a - b
      "multiply" -> a * b
      "divide" -> a / b
      _ -> {:error, "Unknown operation"}
    end

    {:ok, %{result: result}}
  end
end
"""

IO.puts(calculator_action)

# Example 4: Starting and using the agent
IO.puts("\n\nExample 4: Starting and querying the agent")
IO.puts("----------------------------------------")

usage_example = """
# Start the agent
{:ok, pid} = MyApp.CalculatorAgent.start_link()

# Ask a question
{:ok, agent} = MyApp.CalculatorAgent.ask(pid, \"\"\"
  What is 15 * 23?
\"\"\")

# The agent will:
# 1. Generate reasoning about needing to multiply
# 2. Call the calculator tool
# 3. Process the result (345)
# 4. Return the final answer

IO.puts("Answer: \#{agent.result}")
"""

IO.puts(usage_example)

# Example 5: Dynamic tool registration
IO.puts("\n\nExample 5: Dynamic tool registration")
IO.puts("-------------------------------------")

dynamic_tools = """
# Register a tool at runtime
Jido.AgentServer.cast(agent_pid, %Jido.Signal{
  type: "react.register_tool",
  data: %{tool_module: MyApp.Actions.NewTool}
})

# Unregister a tool
Jido.AgentServer.cast(agent_pid, %Jido.Signal{
  type: "react.unregister_tool",
  data: %{tool_name: "old_tool"}
})
"""

IO.puts(dynamic_tools)

# Example 6: ReAct configuration options
IO.puts("\n\nExample 6: Configuration options")
IO.puts("-------------------------------")

IO.puts("""
Key options for ReAct:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| :tools | [module()] | Required | Actions to use as tools |
| :model | String.t() | :fast | Model to use |
| :system_prompt | String.t() | Default | Custom instructions |
| :max_iterations | integer() | 10 | Max reasoning steps |
| :use_registry | boolean() | false | Also check registry for tools |
""")

# Example 7: ReAct state
IO.puts("\n\nExample 7: ReAct agent state")
IO.puts("---------------------------")

IO.puts("""
The agent maintains state under __strategy__:

%{
  status: :idle | :awaiting_llm | :awaiting_tool | :completed | :error,
  iteration: 0,
  conversation: [...],           # LLM messages
  pending_tool_calls: [...],     # Tools being executed
  final_answer: nil,            # Final result when done
  current_llm_call_id: nil,     # For correlation
  termination_reason: nil,      # Why we finished
  config: %{...}
}

Access via:
  agent.state.__strategy__
""")

# Example 8: Signal routing
IO.puts("\n\nExample 8: Signal routing")
IO.puts("-------------------------")

IO.puts("""
ReAct automatically routes these signals:

| Signal Type | Action | Purpose |
|-------------|--------|---------|
| react.user_query | :react_start | Start new conversation |
| reqllm.result | :react_llm_result | Handle LLM response |
| reqllm.partial | :react_llm_partial | Handle streaming tokens |
| ai.tool_result | :react_tool_result | Handle tool results |

No manual routing needed - it's automatic!
""")

# Summary
IO.puts("\n=== Summary ===")
IO.puts("-----------")
IO.puts("ReAct strategy provides:")
IO.puts("  • Step-by-step reasoning")
IO.puts("  • Dynamic tool use")
IO.puts("  • Multi-turn problem solving")
IO.puts("  • Automatic signal routing")
IO.puts("\nBest for:")
IO.puts("  • Tasks requiring external information")
IO.puts("  • Multi-step problems with tools")
IO.puts("  • When you need both reasoning AND action")
IO.puts("\n")
