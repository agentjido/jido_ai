# ReqLLM Module Dependency Tree Report

## Executive Summary

ReqLLM follows a layered architecture with clear separation of concerns, structured around a facade pattern that delegates to specialized core modules. The project demonstrates excellent dependency management with minimal external dependencies and strong testing isolation capabilities.

## 1. Compile-time Dependencies

### Core Data Structures Layer
```
ReqLLM.Model ← ReqLLM.Core.Generation
ReqLLM.Message ← ReqLLM.Core.Messages
ReqLLM.Tool ← ReqLLM.Core.Generation
ReqLLM.ContentPart ← ReqLLM.Message
```

### Provider System Layer
```
ReqLLM.Provider.DSL ← ReqLLM.Provider.BuiltIns.*
ReqLLM.Provider.Registry ← ReqLLM.Provider.DSL (@after_compile hook)
ReqLLM.Provider.Spec ← ReqLLM.Provider.DSL
ReqLLM.Provider.Adapter ← ReqLLM.Provider.BuiltIns.*
```

### Core Business Logic Layer
```
ReqLLM.Core.Generation ← ReqLLM (facade)
ReqLLM.Core.Embedding ← ReqLLM (facade)
ReqLLM.ObjectGeneration ← ReqLLM (facade)
ReqLLM.Core.Config ← ReqLLM (facade)
ReqLLM.Core.Messages ← ReqLLM.Core.Generation
ReqLLM.Core.Utils ← ReqLLM.Core.Generation
```

### HTTP and Response Processing
```
ReqLLM.Core.Http.Default ← ReqLLM.Core.Generation
ReqLLM.Core.Response.Parser ← ReqLLM.Core.Generation
ReqLLM.Core.Response.Stream ← ReqLLM.Core.Generation
```

### Plugin System
```
ReqLLM.Plugins.* ← ReqLLM.Core.Http.Default
- TokenUsage
- Kagi
- Stream
- Splode
```

## 2. Runtime Dependencies

### Provider Auto-Registration Pattern
```
Application.start/2 → ReqLLM.Application
                   → ReqLLM.Provider.Registry.initialize/0
                   → Auto-discovers provider modules
                   → Registers via :persistent_term
```

### Dynamic Provider Lookup
```
ReqLLM.generate_text/3 → ReqLLM.Model.from/1
                       → ReqLLM.Provider.Registry.fetch/1
                       → Provider module lookup (O(1))
                       → Provider.generate_text/3
```

### Configuration Resolution Chain
```
ReqLLM.config/2 → ReqLLM.Core.Config
                → Kagi keyring
                → Mix.Config
                → System.get_env/1
                → Default values
```

### Metadata Enhancement Pipeline
```
ReqLLM.Model.from/1 → Model parsing
                    → ReqLLM.Model.with_metadata/1
                    → Load priv/models_dev/*.json
                    → Enhance with capabilities/pricing
```

## 3. External Dependencies

### Core Runtime Dependencies
- **`req ~> 0.5`** - HTTP client for API requests
  - Role: Primary HTTP interface to AI providers
  - Impact: Core functionality depends entirely on Req

- **`jason ~> 1.4`** - JSON encoding/decoding
  - Role: Request/response serialization
  - Impact: All provider communication requires JSON

- **`nimble_options ~> 1.1`** - Schema validation
  - Role: API parameter validation and documentation
  - Impact: All public APIs use NimbleOptions schemas

- **`typed_struct ~> 0.3.0`** - Compile-time type checking
  - Role: Data structure definitions with types
  - Impact: All major structs (Model, Message, Tool, etc.)

- **`splode ~> 0.2.3`** - Structured error handling
  - Role: Consistent error types and formatting
  - Impact: All error conditions use Splode definitions

- **`server_sent_event ~> 1.0`** - SSE parsing for streaming
  - Role: Parse streaming responses from providers
  - Impact: All streaming functionality depends on this

### Local Workspace Dependency
- **`kagi path: "../kagi"`** - Configuration keyring
  - Role: Secure configuration management
  - Impact: All configuration resolution goes through Kagi

## 4. Dependency Layers

### Layer 1: External Interface (Facade)
```
ReqLLM (main facade module)
├── Delegates to Core modules
├── Provides public API consistency  
└── Minimal business logic
```

### Layer 2: Core Business Logic
```
ReqLLM.Core.*
├── Generation - Text generation orchestration
├── Embedding - Vector embedding generation
├── Config - Configuration management
├── Messages - Message collection handling
├── Utils - Utility functions
├── Http.Default - HTTP request orchestration
├── Response.Parser - Response parsing logic
└── Response.Stream - Streaming response handling
```

### Layer 3: Domain Objects and Schema
```
Data Structures          Schema & Validation
├── ReqLLM.Model        ├── ReqLLM.Schema
├── ReqLLM.Message      ├── ReqLLM.ObjectSchema
├── ReqLLM.Tool         ├── ReqLLM.Core.ObjectSchema
├── ReqLLM.ContentPart  └── NimbleOptions integration
└── ReqLLM.Provider
```

### Layer 4: Provider Infrastructure
```
ReqLLM.Provider.*
├── Registry - Provider auto-registration
├── DSL - Provider definition macros
├── Spec - Provider specification
├── Adapter - Provider behavior interface
├── Utils - Provider utilities
└── BuiltIns.* - Concrete provider implementations
```

### Layer 5: Cross-cutting Concerns
```
Plugins (Req middleware)     Error Handling
├── TokenUsage              ├── ReqLLM.Error
├── Kagi (auth injection)   ├── ReqLLM.Error.SchemaValidation
├── Stream (SSE handling)   └── ReqLLM.Error.ObjectGeneration
└── Splode (error mapping)
```

### Layer 6: External Integration
```
Mix Tasks                External Data
├── mix req_llm.verify   ├── priv/models_dev/*.json
├── mix req_llm.model_sync   (models.dev metadata)
└── mix req_llm.stream_text
```

## 5. Critical Paths

### Primary Text Generation Path
```
1. ReqLLM.generate_text/3 (facade entry)
2. ReqLLM.Core.Generation.generate_text/3 (orchestration)
3. ReqLLM.Model.from/1 (model parsing)
4. ReqLLM.Provider.Registry.fetch/1 (provider lookup)
5. Provider.generate_text/3 (provider-specific logic)
6. ReqLLM.Core.Http.Default.request/3 (HTTP orchestration)
7. Req plugin stack (Kagi → TokenUsage → Stream → Splode)
8. HTTP request to AI provider
9. ReqLLM.Core.Response.Parser.parse/2 (response parsing)
10. Return {:ok, result} or {:error, reason}
```

### Provider Registration Path (Critical for Runtime)
```
1. Application.start/2
2. ReqLLM.Application.start/2
3. ReqLLM.Provider.Registry.initialize/0
4. Auto-discover provider modules
5. Code.ensure_loaded/1 for each provider
6. Provider.spec/0 call
7. Registry.register/2 via :persistent_term
8. Runtime lookup via Registry.fetch/1 (O(1))
```

### Configuration Resolution Path
```
1. ReqLLM.config/2 call
2. ReqLLM.Core.Config delegation
3. Kagi keyring lookup
4. Fall back to Mix.Config
5. Fall back to System.get_env/1
6. Return default value if all fail
```

## 6. Testing Implications

### High Isolation Modules (Easy to Test)
- **Data Structures**: `Model`, `Message`, `Tool`, `ContentPart`
  - Pure structs with no external dependencies
  - Can be tested in complete isolation

- **Schema Modules**: `Schema`, `ObjectSchema`, `Core.ObjectSchema`
  - Logic depends only on NimbleOptions
  - Schema validation is deterministic

- **Utility Modules**: `Core.Utils`, `Provider.Utils`
  - Pure functions with predictable inputs/outputs
  - No external API calls or side effects

### Medium Isolation Modules (Require Mocking)
- **Core Business Logic**: `Core.Generation`, `Core.Embedding`
  - Need to mock HTTP calls via Req
  - Provider registry needs to be stubbed
  - Configuration resolution needs mocking

- **Provider Implementations**: `Provider.BuiltIns.*`
  - HTTP client needs mocking
  - Request/response transformation can be tested in isolation

### Low Isolation Modules (Integration Testing Required)
- **Provider Registry**: `Provider.Registry`
  - Depends on :persistent_term and module discovery
  - Needs full application context for proper testing

- **Configuration System**: `Core.Config`
  - Depends on Kagi, Mix.Config, and ENV vars
  - Hard to isolate from external configuration state

- **HTTP Layer**: `Core.Http.Default`
  - Tightly coupled to Req plugin system
  - Requires mock HTTP responses

### Testing Strategy Recommendations

#### Unit Testing Approach
```elixir
# Data structures - no mocks needed
test "Model.from/1 parses string format" do
  assert %Model{provider: :openai, model: "gpt-4"} = Model.from("openai:gpt-4")
end

# Core logic with HTTP mocks
test "Generation.generate_text/3 with mocked provider" do
  expect(MockProvider, :generate_text, fn _, _, _ ->
    {:ok, %Req.Response{body: "test response"}}
  end)
  
  assert {:ok, "test response"} = Generation.generate_text(model, messages)
end
```

#### Integration Testing Approach
```elixir
# Full stack with real providers (expensive tests)
@tag integration: true
test "end-to-end text generation" do
  # Requires real API keys and provider setup
  assert {:ok, response} = ReqLLM.generate_text("openai:gpt-3.5-turbo", "Hello")
  assert is_binary(response)
end
```

#### Test Doubles Needed
- **HTTP Client**: Mock Req responses for provider testing
- **Provider Registry**: Stub provider lookup for core logic testing  
- **Configuration**: Mock Kagi keyring and ENV vars
- **File System**: Mock metadata file loading in `Model.with_metadata/1`

#### Testing Isolation Strategies
1. **Provider Module Testing**: Use Bypass or Mox to mock HTTP responses
2. **Core Logic Testing**: Stub provider registry with test implementations
3. **Configuration Testing**: Use separate test configurations and ENV mocking
4. **Streaming Testing**: Mock SSE event streams with predictable data
5. **Error Path Testing**: Use Splode error injection for comprehensive coverage

### Mock Dependencies Summary
```
Testing Layer           Mocks Required
├── Data Structures     None (pure)
├── Schema Validation   None (deterministic)
├── Core Generation     HTTP client, Provider registry
├── Provider Modules    HTTP responses, Auth headers
├── Configuration       Kagi keyring, ENV vars
├── Registry System     Module loading, :persistent_term
├── Object Generation   Schema compilation, Tool responses
└── Streaming           SSE event parsing, Async streams
```

## Conclusion

ReqLLM demonstrates excellent dependency management with a clean layered architecture. The facade pattern provides API stability while the provider system enables extensibility. Testing is well-supported through clear separation of concerns, though HTTP interactions and provider registry require careful mocking strategies.

The critical paths are well-defined and testable, with most business logic isolated from external dependencies. The main testing challenges revolve around HTTP mocking and provider registry state management, both of which can be addressed through established Elixir testing patterns.
