# ReqLLM Radical Simplification Plan

## Overview

This plan radically simplifies ReqLLM to be truly idiomatic Elixir - using basic data structures, eliminating cruft, and achieving Phoenix/Ecto-level simplicity. We're removing ~1200 LOC of complexity and replacing with ~150 LOC of clean, functional code.

## Oracle Analysis: Provider-Specific Considerations

**Key Finding**: Only one truly provider-specific pattern merits core data structure consideration: **reasoning tokens** (currently OpenAI-only, but emerging across providers as chain-of-thought becomes standard).

### Recommendation: Add `:reasoning` ContentPart Type
- **Current Issue**: Reasoning text is flattened into regular content (prefixed with 🧠), losing structural distinction
- **Future-Proof**: Other providers adding "rationale" streams (Cohere citations, Google safety explanations)  
- **Minimal Change**: Add `:reasoning` to ContentPart type enum, simple constructor
- **Clean Separation**: Apps can surface/discard reasoning independently from main content

## Current Problems

### 1. Over-Engineering
- **Builder Pattern**: Fluent builders are OO cruft that hide compile-time errors
- **Complex Abstractions**: Nested modules, complex protocols, unnecessary indirection
- **Polymorphic Data**: `Message.content` as string OR list creates branching logic everywhere
- **Duplicate Code**: Schema handling duplicated across 4+ modules (~300 LOC)

### 2. Fighting Elixir
- **Not Using Language Strengths**: Atoms, tuples, pattern matching underutilized  
- **Complex Validation**: Manual validation instead of leveraging compiler + NimbleOptions
- **Protocol Overuse**: Enumerable for Message with branching logic
- **Enterprise Patterns**: Factories, builders, managers - not functional style

### 3. Questionable Abstractions
- **ObjectGeneration**: 400 LOC that could be a simple tool
- **Schema/ObjectSchema**: Overlapping responsibilities, duplicate implementations
- **ContentPart Nesting**: Embedded modules for simple data structures
- **Messages vs Context**: Confusing naming, mixed concerns

## Radical Simplification Goals

1. **Kill All Builders**: Use compile-time struct validation, simple helper functions
2. **Basic Data Structures**: Tuples, atoms, lists - not complex nested modules
3. **Single Schema Source**: One place for all NimbleOptions ↔ JSON Schema logic
4. **Eliminate ObjectGeneration**: Replace with simple tool helper (~5 LOC)
5. **Idiomatic Elixir**: Pattern matching, `with`, atoms as enums
6. **Custom Inspect**: Readable debug output for large payloads

## Implementation Plan

### Phase 1: Kill The Builder Pattern & Polymorphism

#### 1.1 Simplify Message to Compile-Time Validation with TypedStruct
```elixir
defmodule ReqLLM.Message do
  use TypedStruct

  typedstruct enforce: true do
    field :role, :user | :assistant | :system | :tool, enforce: true
    field :content, [ContentPart.t()], default: []    # ALWAYS list of ContentPart - never string
    field :name, String.t() | nil
    field :tool_call_id, String.t() | nil 
    field :tool_calls, [term()] | nil
    field :metadata, map(), default: %{}
  end

  defimpl Inspect do
    import Inspect.Algebra
    def inspect(%{role: role, content: parts}, opts) do
      summary = parts |> Enum.map(& &1.type) |> Enum.join(",")
      concat ["#Message<", to_doc(role, opts), " ", summary, ">"]
    end
  end
end
```

#### 1.2 Remove Builder - Helpers Move to Context
- Delete `Message.Builder` module entirely
- Move all helper functions to `Context` (see Phase 3)
- Use `@enforce_keys` for compile-time validation

#### 1.3 Nest ContentPart with TypedStruct, Remove Embedded Modules
```elixir
defmodule ReqLLM.Message.ContentPart do
  use TypedStruct

  typedstruct enforce: true do
    field :type, :text | :image_url | :image | :file | :tool_call | :tool_result | :reasoning, enforce: true
    field :text, String.t() | nil
    field :url, String.t() | nil
    field :data, binary() | nil
    field :media_type, String.t() | nil
    field :filename, String.t() | nil
    # Tool data as simple fields, not nested structs
    field :tool_call_id, String.t() | nil
    field :tool_name, String.t() | nil
    field :input, term() | nil
    field :output, term() | nil
    field :metadata, map(), default: %{}
  end

  def text(content), do: %__MODULE__{type: :text, text: content}
  def reasoning(content), do: %__MODULE__{type: :reasoning, text: content}
  def image_url(url), do: %__MODULE__{type: :image_url, url: url}
  # ... simple constructors
end
```

#### 1.4 Delete Message.Builder Module Entirely
- Remove `lib/req_llm/message/builder.ex`
- Remove all Builder tests
- Update any usage to use simple helpers

### Phase 2: Radical Schema Consolidation  

#### 2.1 Single Schema Authority
```elixir
defmodule ReqLLM.Schema.JSON do
  @moduledoc "Single source for NimbleOptions ↔ JSON Schema conversion"
  
  def compile(keyword_schema) do
    NimbleOptions.new!(keyword_schema)  # Let it crash on invalid
  end
  
  def to_json(keyword_schema) do
    # Single implementation - used by everyone
    # ... consolidate all the duplicate logic here
  end
  
  def openai_function(name, description, params_kw) do
    %{
      "type" => "function", 
      "function" => %{
        "name" => name,
        "description" => description,
        "parameters" => to_json(params_kw)
      }
    }
  end
end
```

#### 2.2 Delete Duplicate Schema Modules
- Delete `ReqLLM.Schema` (just use `Schema.JSON`)  
- Delete `ReqLLM.ObjectSchema` (replaced by simple tool)
- Move any unique logic into `Schema.JSON`

### Phase 3: Context Replacement + Helpers

#### 3.1 Context with Canonical Message Helpers using TypedStruct
```elixir  
defmodule ReqLLM.Context do
  use TypedStruct
  
  alias ReqLLM.Message
  alias ReqLLM.Message.ContentPart

  typedstruct enforce: true do
    field :messages, [Message.t()], default: []
  end
  
  def new(list \\ []), do: %__MODULE__{messages: list}
  def to_list(%__MODULE__{messages: msgs}), do: msgs
  
  # Canonical message constructors - import ReqLLM.Context to use directly
  def text(role, content, meta \\ %{}) when is_binary(content) do
    %Message{
      role: role,
      content: [ContentPart.text(content)],
      metadata: meta
    }
  end
  
  def user(content, meta \\ %{}), do: text(:user, content, meta)
  def assistant(content, meta \\ %{}), do: text(:assistant, content, meta)
  def system(content, meta \\ %{}), do: text(:system, content, meta)
  
  def with_image(role, text, url, meta \\ %{}) do
    %Message{
      role: role,
      content: [ContentPart.text(text), ContentPart.image_url(url)],
      metadata: meta
    }
  end
  
  # Context validation
  def validate(%__MODULE__{messages: msgs} = context) do
    with :ok <- validate_system_messages(msgs),
         :ok <- validate_message_structure(msgs) do
      {:ok, context}
    end
  end
  
  def validate!(context) do
    case validate(context) do
      {:ok, context} -> context
      {:error, reason} -> raise ArgumentError, "Invalid context: #{reason}"
    end
  end
  
  defp validate_system_messages(messages) do
    system_count = Enum.count(messages, & &1.role == :system)
    case system_count do
      0 -> {:error, "Context should have exactly one system message, found 0"}
      1 -> :ok
      n -> {:error, "Context should have exactly one system message, found #{n}"}
    end
  end
  
  defp validate_message_structure(messages) do
    case Enum.all?(messages, &Message.valid?/1) do
      true -> :ok
      false -> {:error, "Context contains invalid messages"}
    end
  end
  
  defimpl Inspect do
    import Inspect.Algebra
    def inspect(%{messages: msgs}, opts) do
      roles = msgs |> Enum.map(& &1.role) |> Enum.join(",")
      concat ["#Context<", to_doc(length(msgs), opts), " msgs: ", roles, ">"]
    end
  end
end
```

#### 3.2 Delete ReqLLM.Messages Entirely
- Remove file `lib/req_llm/messages.ex` 
- Update all imports to use `Context`
- Remove Messages tests

### Phase 4: Tool Simplification

#### 4.1 Clean Tool Structure with TypedStruct + Provider Schema Formatters
```elixir
defmodule ReqLLM.Tool do
  use TypedStruct

  typedstruct enforce: true do
    field :name, String.t(), enforce: true
    field :description, String.t(), enforce: true
    field :parameter_schema, keyword(), default: []    # Renamed from :parameters
    field :compiled, term() | nil                      # Cache compiled schema
    field :callback, function(), enforce: true
  end

  @spec to_schema(t(), atom()) :: map()
  def to_schema(tool, provider \\ :openai) do
    mod = case provider do
      :openai    -> ReqLLM.ToolSchemaProvider.OpenAI
      :anthropic -> ReqLLM.ToolSchemaProvider.Anthropic
      other      -> raise ArgumentError, "Unknown provider #{inspect(other)}"
    end
    mod.format(tool)
  end

  # Backward compatibility - defaults to OpenAI format
  def to_json_schema(tool), do: to_schema(tool, :openai)
end
```

#### 4.2 Provider-Specific Schema Formatters
```elixir
defmodule ReqLLM.ToolSchemaProvider do
  @moduledoc "Behavior for provider-specific tool schema formatting"
  @callback format(ReqLLM.Tool.t()) :: map()
end

defmodule ReqLLM.ToolSchemaProvider.OpenAI do
  @behaviour ReqLLM.ToolSchemaProvider
  
  def format(tool) do
    %{
      "type" => "function",
      "function" => %{
        "name" => tool.name,
        "description" => tool.description,
        "parameters" => ReqLLM.Schema.JSON.to_json(tool.parameter_schema)
      }
    }
  end
end

defmodule ReqLLM.ToolSchemaProvider.Anthropic do
  @behaviour ReqLLM.ToolSchemaProvider
  
  def format(tool) do
    %{
      "name" => tool.name,
      "description" => tool.description,
      "input_schema" => ReqLLM.Schema.JSON.to_json(tool.parameter_schema)
    }
  end
end
```

#### 4.3 Replace ObjectGeneration with Simple Helper  
```elixir
defmodule ReqLLM.Tool.Passthrough do
  @moduledoc "Helper to create a 'return structured data' tool"
  
  def new(schema_kw) do
    ReqLLM.Tool.new!(
      name: "response_object",
      description: "Return the response as structured data",
      parameter_schema: schema_kw,
      callback: fn args -> {:ok, args} end
    )
  end
end
```

#### 4.4 Delete ObjectGeneration Module
- Remove `lib/req_llm/object_generation.ex` (~400 LOC)
- Replace with 5-line helper above
- Update tests to use simple tool pattern

### Phase 5: Final Cleanup

#### 5.1 Update Providers
- Remove string content handling (always list)
- Use `Schema.JSON` functions  
- Handle simplified ContentPart structure

#### 5.2 Remove Unnecessary Protocols
- Remove `Enumerable` for Message (no more polymorphism)
- Keep `Enumerable`/`Collectable` for Context only
- Add `Inspect` implementations for readable debugging

## Final Module Structure (Phoenix/Ecto Style)

```
ReqLLM/
├── message.ex               # Simple struct + Inspect  
│   └── content_part.ex     # Nested simple struct
├── context.ex              # Collection + canonical helpers + validation + Inspect
├── tool.ex                 # Tool definition + provider-agnostic schema dispatch
│   └── passthrough.ex      # Simple structured data helper  
├── tool_schema_provider.ex  # Behavior for provider formatters
│   ├── openai.ex           # OpenAI tool format
│   └── anthropic.ex        # Anthropic tool format
├── schema/
│   └── json.ex             # Single schema authority
└── providers/              # Unchanged, use new structs
```

## Canonical Usage Pattern

```elixir
import ReqLLM.Context

# Build messages directly with imported helpers
context = Context.new([
  system("You are a helpful assistant"),
  user("What's the weather like?"),  
  assistant("I'll check that for you"),
  user("Thanks!")
])

# Validate context (ensures single system message, etc.)
Context.validate!(context)

# Use with LLM
ReqLLM.generate_text(model, context, opts)
```

**Total Removal**: ~1200 LOC
**Total New Code**: ~170 LOC

## Implementation Timeline

1. **Phase 1**: Kill builders & polymorphism - clean Message structure
2. **Phase 2**: Consolidate all schema logic into single module  
3. **Phase 3**: Replace Messages with Context + helpers
4. **Phase 4**: Simplify Tool, delete ObjectGeneration 
5. **Phase 5**: Update providers, add Inspect implementations

## What Gets Deleted (Unreleased = No Deprecation)

### Modules Completely Removed
- `Message.Builder` (~200 LOC) - Replace with simple helpers
- `Messages` (~400 LOC) - Replace with `Context`  
- `ObjectGeneration` (~400 LOC) - Replace with 5-line tool helper
- `ObjectSchema` (~200 LOC) - Logic moves to `Schema.JSON`

### Cruft Eliminated  
- Polymorphic `Message.content` (string OR list)
- Embedded ToolCall/ToolResult modules (use simple fields)
- Duplicate schema functions across 4 modules (~300 LOC)
- Complex Enumerable protocol for Message
- Builder pattern with hidden state transformations

## Benefits of Radical Simplification

1. **Idiomatic Elixir**: Uses atoms, tuples, pattern matching - not enterprise patterns
2. **Compile-Time Safety**: TypedStruct + enforce catches missing fields and type errors immediately  
3. **No Surprises**: No hidden polymorphism or data transformations
4. **Single Schema Authority**: All NimbleOptions ↔ JSON in one place
5. **Readable Debug**: Custom Inspect shows structure, not giant payloads
6. **Phoenix/Ecto Feel**: TypedStruct, functional helpers, clear responsibility
7. **Massive LOC Reduction**: ~1200 LOC removed, ~170 LOC added
8. **Easier Testing**: No complex state machines or builders to mock
9. **Better Performance**: No protocol dispatch overhead for common cases
10. **Future Maintenance**: Less code = fewer bugs, easier changes
11. **Enhanced Reasoning Support**: First-class `:reasoning` ContentPart for chain-of-thought patterns
12. **Provider Flexibility**: Clean separation of tool logic from provider-specific formatting
13. **Simple Extensibility**: Adding new provider tool formats requires <20 LOC behavior implementation
