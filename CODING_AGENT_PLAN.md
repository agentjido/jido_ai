# Coding Agent Port Plan: TypeScript → Elixir/Jido
## ⚡ UPDATED - LEVERAGING JIDO'S BUILT-IN LOOPING ACTIONS

## Overview

This document outlines the plan for porting the TypeScript coding agent (`simple_coding_agent.ts`) to Elixir using the Jido framework (`coding_agent.exs`). 

**🎯 KEY INSIGHT**: All required functionality already exists in Jido! We can reuse existing Actions, create a Skill to bundle them, AND use Jido's built-in `While` action for looping instead of custom OTP message handling.

## Architecture Comparison

### TypeScript Implementation
- **Pattern**: Stateless function with local message array
- **Loop**: Simple `for` loop with `generateText()` calls
- **Tools**: Mock implementations of `writeFile`, `readFile`, `runCode`
- **Termination**: Continues until "TASK_COMPLETE" or max iterations
- **State Management**: Messages array maintained in function scope

### Elixir/Jido Target Architecture (REVISED - WITH BUILT-IN LOOPING)
- **Pattern**: Stateful OTP Agent with signal-based communication  
- **Loop**: ✅ **Use `Jido.Actions.While` with a lightweight iteration action**
- **Tools**: ✅ **REUSE existing Actions via a Skill**
- **Termination**: Same - "TASK_COMPLETE" or max iterations
- **State Management**: Minimal agent state - loop state managed by While action params

## ✅ Available Components (No Implementation Needed!)

| Capability          | Status | Existing Module                     |
|---------------------|--------|-------------------------------------|
| ✅ Read file        | Ready  | `Jido.Tools.Files.ReadFile`        |
| ✅ Write file       | Ready  | `Jido.Tools.Files.WriteFile`       |
| ✅ Delete file      | Ready  | `Jido.Tools.Files.DeleteFile`      |
| ✅ Copy file        | Ready  | `Jido.Tools.Files.CopyFile`        |
| ✅ Move file        | Ready  | `Jido.Tools.Files.MoveFile`        |
| ✅ Make directory   | Ready  | `Jido.Tools.Files.MakeDirectory`   |
| ✅ List directory   | Ready  | `Jido.Tools.Files.ListDirectory`   |
| ✅ Execute code     | Ready  | `JidoAI.Actions.RunCode`            |
| ✅ While loop       | Ready  | `Jido.Actions.While`                |
| ✅ Iterator loop    | Ready  | `Jido.Actions.Iterator`             |  
| ✅ Enumerable loop  | Ready  | `Jido.Actions.Enumerable`           |

**Result**: Almost zero custom Actions needed! Just one tiny iteration action! 🎉

### ✅ Tool Schema Utilities (Already Available)

- `Jido.Action.Tool.to_tool/1` - Converts individual Actions to tool format
- `Jido.Skill.to_tools/0` - Auto-generates tool schemas from Skill actions  
- `Jido.Skill.execute_tool/3` - Executes tools by name with validation

## 🏗️ REVISED IMPLEMENTATION STRATEGY (NOW WITH BUILT-IN LOOPING!)

### 1. Create a Coding Tools Skill (Only New Code Needed!)

```elixir
# lib/coding_demo/coding_tools_skill.ex
defmodule CodingDemo.CodingToolsSkill do
  use Jido.Skill,
    name: "coding_tools",
    description: "File I/O and code execution helpers for coding agent",
    category: "developer_tools", 
    tags: ["file", "code", "exec"],
    vsn: "0.1.0",
    opts_key: :coding_tools,
    # Just list existing actions - no custom implementation!
    actions: [
      Jido.Tools.Files.ReadFile,
      Jido.Tools.Files.WriteFile,
      Jido.Tools.Files.DeleteFile,
      Jido.Tools.Files.MakeDirectory,
      JidoAI.Actions.RunCode
    ]
end
```

**That's it!** The Skill automatically provides:
- `CodingToolsSkill.to_tools()` - LLM-compatible tool schemas
- `CodingToolsSkill.execute_tool(name, params, ctx)` - Tool execution

### 2. Create a Single Iteration Action (NEW - Replaces Custom Loop Logic!)

```elixir
# lib/coding_demo/actions/coding_iteration.ex
defmodule CodingDemo.Actions.CodingIteration do
  use Jido.Action,
    name: "coding_iteration",
    description: "Runs one LLM conversation turn and decides whether to continue",
    schema: [
      messages: [type: {:list, :map}, required: true],
      iteration: [type: :pos_integer, default: 0],
      max_iterations: [type: :pos_integer, default: 10],
      continue: [type: :boolean, default: true]
    ],
    output_schema: [
      iteration: [type: :pos_integer, required: true],
      continue: [type: :boolean, required: true],
      final: [type: :boolean]
    ]

  @coding_skill CodingDemo.CodingToolsSkill

  @impl true
  def run(%{continue: false} = params, _ctx) do
    {:ok, %{iteration: params.iteration, continue: false, final: true}}
  end

  def run(%{iteration: iteration, max_iterations: max} = params, _ctx) 
      when iteration >= max do
    {:ok, %{iteration: iteration, continue: false, final: true}}
  end

  def run(%{messages: messages} = params, _ctx) do
    case Jido.AI.generate_text("openai:gpt-4o", messages, 
           tools: @coding_skill.to_tools(),
           temperature: 0.1) do
      {:ok, %{text: text, tool_calls: tool_calls}} ->
        # Add assistant message
        new_messages = messages ++ [%{role: "assistant", content: text}]
        
        # Execute tool calls if any
        {final_messages, _results} = execute_tool_calls(tool_calls, new_messages)
        
        # Check for completion
        continue? = not String.contains?(text, "TASK_COMPLETE")
        
        {:ok, 
         %{iteration: params.iteration, continue: continue?},
         [],  # no directives
         %{next_params: %{params | 
           iteration: params.iteration + 1,
           messages: final_messages,
           continue: continue?}}}
           
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp execute_tool_calls([], messages), do: {messages, []}
  defp execute_tool_calls(tool_calls, messages) do
    # Execute each tool call and add results to messages
    # Implementation details...
    {messages, []}  # Simplified for now
  end
end
```

### 3. Ultra-Simplified Agent Implementation (Replaces All Loop Logic!) 

```elixir
defmodule CodingDemo.Agent do
  use Jido.Agent, name: "coding_agent"
  
  def handle_signal("run_task", %{"task" => task}, _ctx, state) do
    # Build the system prompt
    system_prompt = build_system_prompt(task)
    initial_messages = [%{role: "user", content: system_prompt}]
    
    # Create the While loop instruction
    while_instruction = %Jido.Agent.Directive.Enqueue{
      action: Jido.Actions.While,
      params: %{
        body: CodingDemo.Actions.CodingIteration,
        params: %{
          messages: initial_messages,
          iteration: 0,
          max_iterations: 10,
          continue: true
        },
        condition_field: :continue,
        max_iterations: 20  # Safety belt around runaway LLMs
      }
    }
    
    {:reply, {:ok, "Task started"}, state, [while_instruction]}
  end
  
  defp build_system_prompt(task) do
    """
    You are a coding assistant. Your task is: #{task}
    
    You have access to file operations and code execution tools.
    When you complete the task, respond with "TASK_COMPLETE" in your message.
    """
  end
end
```

## 🎯 REVISED IMPLEMENTATION STEPS (MUCH SIMPLER WITH BUILT-IN LOOPING!)

### Step 1: Create the Coding Tools Skill (5 minutes)
Just one small module - all functionality comes from existing Actions!

### Step 2: Create the Coding Iteration Action (20 minutes)
Single action that handles one LLM conversation turn and tool execution.

### Step 3: Ultra-Simplified Agent Implementation (10 minutes)  
- Replace ALL custom loop logic with one `Jido.Actions.While` enqueue
- Delete `handle_info(:iterate)`, iteration tracking, message state management
- Agent becomes a simple signal handler that starts the While loop

### Step 4: Delete Unnecessary Code (2 minutes)
- Remove custom loop logic, counters, message passing
- Remove manual tool schema registries
- Clean up imports

### Step 5: Test Integration (10 minutes)
- Verify While loop executes iterations correctly
- Test "TASK_COMPLETE" termination
- Validate max_iterations safety mechanism

## ✅ Advantages of This Approach (NOW WITH BUILT-IN LOOPING!)

### Code Reuse
- **Almost zero custom Actions** - leverage battle-tested file/exec operations + built-in While loop
- **Built-in validation** - Actions already handle schema validation
- **Consistent patterns** - follows established Jido conventions

### Maintainability  
- **Single source of truth** - Skill bundles all coding capabilities
- **Idiomatic loop logic** - Uses Jido's proven While action instead of custom OTP messaging
- **Type safety** - Actions provide schema validation out-of-box
- **Easy debugging** - Each iteration is a separate action in Jido's trace system

### Performance & Safety
- **No overhead** - direct delegation to existing Actions
- **Double safety belts** - max_iterations in both the iteration action AND the While wrapper
- **Cancellation support** - Can pause/cancel between iterations
- **Observability** - Built-in tracing of each loop iteration

## 📊 Current Status (UPDATED WITH BUILT-IN LOOPING)

- ✅ Basic agent structure defined
- ✅ All tool Actions available (reusing existing)
- ✅ All looping Actions available (reusing Jido.Actions.While)
- ✅ Tool schema utilities available (`Jido.Skill.to_tools`)
- ✅ Tool execution utilities available (`Jido.Skill.execute_tool`)
- 🔨 Need to create CodingToolsSkill module
- 🔨 Need to create CodingIteration action
- 🔨 Need to update Agent to use While+Skill pattern
- ✅ Demo script mostly ready

## 🚀 Next Immediate Actions (EVEN MORE SIMPLIFIED!)

1. **Create `CodingDemo.CodingToolsSkill`** - 1 module, ~20 lines
2. **Create `CodingDemo.Actions.CodingIteration`** - 1 action, ~50 lines  
3. **Update Agent implementation** - replace ALL loop logic with While action
4. **Test the complete flow** - should work immediately!

**Estimated time**: 45 minutes vs 3+ hours for custom implementation

This revised approach leverages Jido's existing ecosystem INCLUDING built-in looping to create a robust coding agent with almost zero custom code while following established patterns perfectly.
