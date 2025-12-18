# Data Flow

This guide explains how data flows through the Jido AI system, from user input to LLM response and back.

## High-Level Data Flow

```mermaid
graph TB
    subgraph Input["User Input"]
        UserPrompt["User Message"]
        ModelSpec["Model Specification"]
        Tools["Tools (Optional)"]
    end

    subgraph Processing["Jido AI Processing"]
        Model["Model.from/1"]
        Prompt["Prompt.new/1"]
        Action["ChatCompletion"]
    end

    subgraph External["External Services"]
        ReqLLM["ReqLLM"]
        Provider["LLM Provider"]
    end

    subgraph Output["Response"]
        Content["Text Content"]
        ToolCalls["Tool Calls"]
        Stream["Stream Chunks"]
    end

    UserPrompt --> Prompt
    ModelSpec --> Model
    Tools --> Action

    Model --> Action
    Prompt --> Action

    Action --> ReqLLM
    ReqLLM --> Provider
    Provider --> ReqLLM
    ReqLLM --> Action

    Action --> Content
    Action --> ToolCalls
    Action --> Stream
```

## Basic Chat Completion Flow

### 1. Model Creation

```mermaid
sequenceDiagram
    participant User
    participant Model as Jido.AI.Model
    participant ReqLLM as ReqLLM.Model

    User->>Model: from({:anthropic, [model: "claude-3-5-sonnet"]})
    Model->>Model: Validate provider
    Model->>Model: Extract model name
    Model->>ReqLLM: ReqLLM.Model.from({provider, model, opts})
    ReqLLM-->>Model: %ReqLLM.Model{}
    Model-->>User: {:ok, %ReqLLM.Model{}}
```

**Data transformations:**
- Input: `{:anthropic, [model: "claude-3-5-sonnet"]}`
- Internal: Provider atom + options keyword list
- Output: `%ReqLLM.Model{provider: :anthropic, model: "claude-3-5-sonnet", ...}`

### 2. Prompt Creation and Rendering

```mermaid
sequenceDiagram
    participant User
    participant Prompt as Jido.AI.Prompt
    participant MsgItem as MessageItem
    participant Engine as Template Engine

    User->>Prompt: new(%{messages: [...], params: %{...}})
    Prompt->>MsgItem: MessageItem.new/1 for each message
    MsgItem-->>Prompt: [%MessageItem{}, ...]
    Prompt-->>User: %Prompt{}

    User->>Prompt: render(prompt)
    loop For each message
        Prompt->>Engine: Apply template (EEx/Liquid/None)
        Engine-->>Prompt: Rendered content
    end
    Prompt-->>User: [%{role: :user, content: "..."}]
```

**Data transformations:**
- Input: `%{messages: [%{role: :user, content: "Hello <%= @name %>", engine: :eex}], params: %{name: "Alice"}}`
- Internal: `[%MessageItem{role: :user, content: "Hello <%= @name %>", engine: :eex}]`
- Rendered: `[%{role: :user, content: "Hello Alice"}]`

### 3. Action Execution

```mermaid
sequenceDiagram
    participant User
    participant Action as ChatCompletion
    participant Validate as Validation
    participant ReqLLM
    participant Provider

    User->>Action: run(%{model: model, prompt: prompt}, context)

    Action->>Validate: on_before_validate_params
    Validate->>Validate: Model.validate_model_opts
    Validate->>Validate: Prompt.validate_prompt_opts
    Validate-->>Action: {:ok, validated_params}

    Action->>Action: render(prompt) -> messages
    Action->>Action: build_req_llm_options

    Action->>ReqLLM: generate_text("anthropic:claude-3-5-sonnet", messages, opts)
    ReqLLM->>Provider: HTTP POST /v1/messages
    Provider-->>ReqLLM: JSON response
    ReqLLM-->>Action: {:ok, %{content: "...", tool_calls: [...]}}

    Action->>Action: format_response
    Action-->>User: {:ok, %{content: "...", tool_results: []}}
```

## Tool Calling Flow

```mermaid
sequenceDiagram
    participant User
    participant Action as ChatCompletion
    participant Manager as Tools.Manager
    participant SchemaConv as SchemaConverter
    participant ReqLLM
    participant ToolAction as Jido Action

    User->>Action: run(%{..., tools: [MyTool]}, context)

    Action->>SchemaConv: action_to_tool(MyTool)
    SchemaConv-->>Action: %{name: "my_tool", parameters: {...}}

    Action->>Manager: process(model, messages, tools, action_map)

    loop Until no tool calls
        Manager->>ReqLLM: generate_text with tools
        ReqLLM-->>Manager: %{tool_calls: [%{name: "my_tool", arguments: {...}}]}

        Manager->>Manager: Lookup action in action_map
        Manager->>ToolAction: run(arguments, context)
        ToolAction-->>Manager: {:ok, tool_result}

        Manager->>Manager: Append tool result to messages
    end

    Manager-->>Action: {:ok, final_response}
    Action-->>User: {:ok, %{content: "...", tool_results: [...]}}
```

**Tool schema transformation:**
```elixir
# Jido Action schema
schema: [
  city: [type: :string, required: true, doc: "City name"],
  unit: [type: {:in, ["celsius", "fahrenheit"]}, default: "celsius"]
]

# Converted to JSON Schema
%{
  type: "function",
  function: %{
    name: "get_weather",
    description: "Get weather for a city",
    parameters: %{
      type: "object",
      properties: %{
        "city" => %{type: "string", description: "City name"},
        "unit" => %{type: "string", enum: ["celsius", "fahrenheit"]}
      },
      required: ["city"]
    }
  }
}
```

## Streaming Flow

```mermaid
sequenceDiagram
    participant User
    participant Action as ChatCompletion
    participant ReqLLM
    participant Provider

    User->>Action: run(%{..., stream: true}, context)
    Action->>ReqLLM: stream_text(model_id, messages, opts)
    ReqLLM->>Provider: HTTP POST with stream: true

    Provider-->>ReqLLM: SSE chunk 1
    ReqLLM-->>Action: %{content: "Hello"}

    Provider-->>ReqLLM: SSE chunk 2
    ReqLLM-->>Action: %{content: " world"}

    Provider-->>ReqLLM: SSE [DONE]
    ReqLLM-->>Action: Stream end

    Action-->>User: {:ok, stream}

    User->>User: Enum.each(stream, &process/1)
```

## Runner Flow (Chain-of-Thought)

```mermaid
sequenceDiagram
    participant Agent
    participant CoT as ChainOfThought
    participant Config as Config Builder
    participant Prompt as ReasoningPrompt
    participant LLM as TextCompletion
    participant Parser
    participant Exec as Executor

    Agent->>CoT: run(agent, opts)

    CoT->>Config: build_config(agent, opts)
    Note over Config: Merge state config with opts
    Config-->>CoT: %Config{}

    CoT->>CoT: get_pending_instructions(agent)

    CoT->>Prompt: zero_shot(instructions, state)
    Prompt-->>CoT: %Prompt{}

    CoT->>LLM: run(reasoning_prompt)
    LLM-->>CoT: {:ok, reasoning_text}

    CoT->>Parser: parse(reasoning_text)
    Parser-->>CoT: %ReasoningPlan{steps: [...]}

    loop For each instruction
        CoT->>Exec: execute_instruction_with_context
        Exec-->>CoT: {:ok, result}

        CoT->>CoT: validate_outcome(result, step)
    end

    CoT-->>Agent: {:ok, updated_agent, directives}
```

## Conversation Flow

```mermaid
sequenceDiagram
    participant User
    participant Manager as Conversation.Manager
    participant ETS
    participant Action as ChatCompletion

    User->>Manager: create(model, system_prompt: "...")
    Manager->>ETS: Insert conversation
    ETS-->>Manager: :ok
    Manager-->>User: {:ok, conv_id}

    User->>Manager: add_message(conv_id, :user, "Hello")
    Manager->>ETS: Update conversation
    ETS-->>Manager: :ok
    Manager-->>User: :ok

    User->>Manager: get_messages_for_llm(conv_id)
    Manager->>ETS: Lookup conversation
    ETS-->>Manager: %Conversation{}
    Manager-->>User: {:ok, [%{role: :system, ...}, %{role: :user, ...}]}

    User->>Action: run(%{model: model, prompt: messages_prompt})
    Action-->>User: {:ok, %{content: response}}

    User->>Manager: add_message(conv_id, :assistant, response)
```

## Configuration Flow

```mermaid
sequenceDiagram
    participant User
    participant API as Jido.AI
    participant Keyring
    participant ReqLLM
    participant Env as Environment

    User->>API: api_key(:openai)
    API->>Keyring: get(:openai_api_key)

    Keyring->>Keyring: Check session value (ETS)
    alt Session value exists
        Keyring-->>API: session_value
    else No session value
        Keyring->>ReqLLM: get_key(:openai_api_key)
        alt ReqLLM has key
            ReqLLM-->>Keyring: value
        else No ReqLLM key
            Keyring->>Env: Check environment (Dotenvy)
            Env-->>Keyring: env_value
        end
        Keyring-->>API: value
    end

    API-->>User: api_key
```

**Configuration priority:**
1. Session values (per-process overrides)
2. ReqLLM key resolution
3. Environment variables (via Dotenvy)
4. Application environment
5. Default values

## Context Window Management

```mermaid
sequenceDiagram
    participant User
    participant CW as ContextWindow
    participant Tokenizer
    participant Strategy

    User->>CW: validate(messages, model)
    CW->>Tokenizer: count_tokens(messages, provider)
    Tokenizer-->>CW: token_count

    CW->>CW: Check against model.context_length

    alt Within limits
        CW-->>User: {:ok, messages}
    else Exceeds limits
        CW->>Strategy: truncate(messages, strategy)
        Strategy-->>CW: truncated_messages
        CW-->>User: {:ok, truncated_messages, :truncated}
    end
```

**Truncation strategies:**
- `:keep_recent` - Keep most recent messages
- `:keep_bookends` - Keep first and last messages
- `:sliding_window` - Fixed window size
- `:smart_truncate` - Intelligent content reduction

## Complete Request Lifecycle

```mermaid
graph TB
    subgraph Setup["1. Setup"]
        ModelCreate["Model.from/1"]
        PromptCreate["Prompt.new/1"]
        ToolSetup["Tools Setup"]
    end

    subgraph Validation["2. Validation"]
        ModelVal["Model Validation"]
        PromptVal["Prompt Validation"]
        ParamVal["Parameter Validation"]
    end

    subgraph Preparation["3. Preparation"]
        Render["Render Prompt"]
        BuildOpts["Build Options"]
        ConvertTools["Convert Tool Schemas"]
    end

    subgraph Execution["4. Execution"]
        ReqLLM["ReqLLM Call"]
        ToolLoop["Tool Loop (if needed)"]
    end

    subgraph Response["5. Response"]
        Format["Format Response"]
        Return["Return to User"]
    end

    ModelCreate --> ModelVal
    PromptCreate --> PromptVal
    ToolSetup --> ParamVal

    ModelVal --> Render
    PromptVal --> Render
    ParamVal --> BuildOpts

    Render --> ReqLLM
    BuildOpts --> ReqLLM
    ConvertTools --> ReqLLM

    ReqLLM --> ToolLoop
    ToolLoop --> Format
    Format --> Return
```

## Data Structures Summary

### Input → Internal → Output

| Stage | Data Structure |
|-------|----------------|
| Model Input | `{:provider, [model: "name"]}` or `"provider:model"` |
| Model Internal | `%ReqLLM.Model{}` |
| Prompt Input | `%{messages: [...], params: %{}}` |
| Prompt Internal | `%Jido.AI.Prompt{messages: [%MessageItem{}]}` |
| Messages Rendered | `[%{role: :user, content: "..."}]` |
| Action Params | `%{model: model, prompt: prompt, ...}` |
| ReqLLM Request | HTTP POST with JSON body |
| ReqLLM Response | `%{content: "...", tool_calls: [...]}` |
| Action Result | `{:ok, %{content: "...", tool_results: [...]}}` |

### Tool Data Flow

| Stage | Data Structure |
|-------|----------------|
| Jido Action | Module with `use Jido.Action` |
| Tool Schema | JSON Schema object |
| Tool Call | `%{name: "tool", arguments: %{...}}` |
| Tool Result | `{:ok, result}` from action |
| Tool Message | `%{role: :tool, content: result, tool_call_id: "..."}` |
