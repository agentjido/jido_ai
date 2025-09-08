# ReqLLM Module Relationships

This diagram shows the architectural relationships between modules in the ReqLLM package based on the oracle analysis.

```mermaid
graph TB
    %% Main Facade
    ReqLLM[ReqLLM<br/>Main API Facade] --> Generation[Core.Generation]
    ReqLLM --> ObjectGeneration[ObjectGeneration]
    ReqLLM --> Embedding[Core.Embedding]
    ReqLLM --> Config[Core.Config]
    ReqLLM --> Utils[Core.Utils]
    ReqLLM --> Messages[Core.Messages]
    ReqLLM --> ProviderRegistry[Provider.Registry]

    %% Core Data Structures
    subgraph DataStructures[Core Data Structures]
        Model[Model]
        Message[Message]
        Tool[Tool]
        ContentPart[ContentPart]
        Schema[Schema]
        ObjectSchema[ObjectSchema]
    end

    %% Provider System
    subgraph ProviderSystem[Provider System]
        ProviderBehaviour[Provider.Adapter<br/>@behaviour]
        ProviderDSL[Provider.DSL<br/>Generates Implementations]
        ProviderSpec[Provider.Spec]
        ProviderUtils[Provider.Utils]
        ProviderRegistry[Provider.Registry]
        
        subgraph BuiltInProviders[Built-in Providers]
            OpenAI[Provider.BuiltIns.OpenAI]
            Anthropic[Provider.BuiltIns.Anthropic]
        end
    end

    %% Plugin System
    subgraph PluginSystem[Plugin System]
        Kagi[Plugins.Kagi<br/>Auto Auth Injection]
        TokenUsage[Plugins.TokenUsage<br/>Usage Tracking]
        StreamPlugin[Plugins.Stream<br/>SSE Handling]
        Splode[Plugins.Splode<br/>Error Handling]
    end

    %% Capability System
    subgraph CapabilitySystem[Capability System]
        CapabilityBehaviour[Core.Capability<br/>@behaviour]
        CapabilityVerifier[Core.CapabilityVerifier]
        
        subgraph BuiltInCapabilities[Built-in Capabilities]
            GenerateTextCap[Capabilities.GenerateText]
            StreamTextCap[Capabilities.StreamText]
            ToolCallingCap[Capabilities.ToolCalling]
            ReasoningCap[Capabilities.Reasoning]
        end
    end

    %% Mix Tasks
    subgraph MixTasks[Mix Tasks]
        VerifyTask[mix req_llm.verify<br/>Capability Testing]
        ModelSyncTask[mix req_llm.model_sync<br/>Models.dev Sync]
        StreamTextTask[mix stream_text<br/>Testing Utility]
    end

    %% HTTP Core
    subgraph HTTPCore[HTTP Core]
        HTTP[Core.HTTP]
        HTTPDefault[Core.HTTP.Default]
        ResponseParser[Core.Response.Parser]
        ResponseStream[Core.Response.Stream]
    end

    %% Error System
    subgraph ErrorSystem[Error System]
        Error[Error]
        SchemaValidation[Error.SchemaValidation]
        ObjectGenerationError[Error.ObjectGeneration]
    end

    %% Metadata System
    subgraph MetadataSystem[External Data]
        ModelsDevJSON[priv/models_dev/*.json<br/>44+ Provider Metadata]
    end

    %% Key Relationships
    ProviderDSL --> ProviderBehaviour
    ProviderDSL -.->|generates| OpenAI
    ProviderDSL -.->|generates| Anthropic
    ProviderDSL -->|auto-registers| ProviderRegistry
    ProviderDSL -->|reads metadata| ModelsDevJSON
    
    Generation --> HTTP
    ObjectGeneration --> HTTP
    Embedding --> HTTP
    
    HTTP --> Kagi
    HTTP --> TokenUsage
    HTTP --> StreamPlugin
    HTTP --> Splode
    
    VerifyTask --> CapabilityVerifier
    CapabilityVerifier --> CapabilityBehaviour
    CapabilityVerifier --> GenerateTextCap
    CapabilityVerifier --> StreamTextCap
    CapabilityVerifier --> ToolCallingCap
    CapabilityVerifier --> ReasoningCap
    
    ModelSyncTask -.->|updates| ModelsDevJSON
    
    %% Data structure relationships
    Generation --> Model
    Generation --> Message
    Generation --> Tool
    ObjectGeneration --> Schema
    ObjectGeneration --> ObjectSchema
    Message --> ContentPart
    
    Model -->|enhanced with| ModelsDevJSON
    
    %% Error handling
    HTTP --> Error
    ObjectGeneration --> ObjectGenerationError
    Schema --> SchemaValidation

    %% Styling
    classDef facade fill:#e1f5fe,stroke:#0277bd,stroke-width:3px
    classDef core fill:#f3e5f5,stroke:#7b1fa2,stroke-width:2px
    classDef provider fill:#e8f5e8,stroke:#388e3c,stroke-width:2px
    classDef plugin fill:#fff3e0,stroke:#f57c00,stroke-width:2px
    classDef capability fill:#fce4ec,stroke:#c2185b,stroke-width:2px
    classDef task fill:#f1f8e9,stroke:#689f38,stroke-width:2px
    classDef data fill:#e0f2f1,stroke:#00695c,stroke-width:2px
    classDef error fill:#ffebee,stroke:#d32f2f,stroke-width:2px
    classDef external fill:#fafafa,stroke:#616161,stroke-width:2px

    class ReqLLM facade
    class Generation,ObjectGeneration,Embedding,Config,Utils,Messages,HTTP,HTTPDefault,ResponseParser,ResponseStream core
    class ProviderBehaviour,ProviderDSL,ProviderSpec,ProviderUtils,ProviderRegistry,OpenAI,Anthropic provider
    class Kagi,TokenUsage,StreamPlugin,Splode plugin
    class CapabilityBehaviour,CapabilityVerifier,GenerateTextCap,StreamTextCap,ToolCallingCap,ReasoningCap capability
    class VerifyTask,ModelSyncTask,StreamTextTask task
    class Model,Message,Tool,ContentPart,Schema,ObjectSchema data
    class Error,SchemaValidation,ObjectGenerationError error
    class ModelsDevJSON external
```

## Key Architectural Patterns

### 1. Facade Pattern
- **ReqLLM** serves as the main API facade, delegating to specialized subsystems
- Provides Vercel AI SDK-compatible interface (`generate_text`, `stream_text`, `generate_object`, `embed`)

### 2. Provider DSL Code Generation
- **Provider.DSL** generates boilerplate implementations and auto-registers providers
- Providers only implement unique `build_request/3` and `parse_response/3` logic
- Metadata loaded from `priv/models_dev/*.json` files (44+ providers)

### 3. Plugin-based Middleware Stack
- **HTTP** layer uses composable Req plugins for cross-cutting concerns:
  - **Kagi**: Auto auth injection
  - **TokenUsage**: Usage/cost tracking
  - **Stream**: SSE handling  
  - **Splode**: Error standardization

### 4. Capability-based Testing
- **CapabilityVerifier** validates advertised model features
- **mix req_llm.verify** provides automated testing framework
- Built-in capabilities: text generation, streaming, tool calling, reasoning

### 5. Metadata-driven Model Enhancement
- **Model** structs enhanced with rich metadata from models.dev
- **mix req_llm.model_sync** keeps provider data current
- Supports cost calculation, capability detection, and limits
