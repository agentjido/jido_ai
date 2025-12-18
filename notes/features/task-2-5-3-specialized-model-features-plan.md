# Task 2.5.3: Specialized Model Features - Planning Document

**Branch:** `feature/task-2-5-3-specialized-model-features`
**Status:** Planning Complete
**Date:** 2025-10-03
**Planner:** Claude Code

## Table of Contents

1. [Problem Statement](#problem-statement)
2. [Solution Overview](#solution-overview)
3. [Research & Analysis](#research--analysis)
4. [Technical Architecture](#technical-architecture)
5. [Implementation Plan](#implementation-plan)
6. [Testing Strategy](#testing-strategy)
7. [Success Criteria](#success-criteria)
8. [Risk Mitigation](#risk-mitigation)

---

## Problem Statement

### Why Specialized Model Features Are Needed

Modern AI providers offer specialized features beyond basic chat completion that enable powerful use cases:

1. **RAG Models**: Built-in retrieval-augmented generation (Cohere's Command-R, Anthropic's citation capabilities)
2. **Code Execution**: Models with built-in interpreters (GPT-4 Code Interpreter, Claude Artifacts)
3. **Model Plugins**: Provider-specific extensions (GPT Actions, Anthropic MCP, Gemini Extensions)
4. **Fine-tuning**: Custom model training and integration (OpenAI, Google, Anthropic)

### Current State Analysis

**Existing Jido AI Capabilities:**
- Basic chat completion via ReqLLM
- Tool calling/function execution
- Embeddings support (Task 1.3.3)
- Context window management (Task 2.5.2)
- Model registry with capability detection (Task 2.2.1)

**Gaps:**
- No support for RAG-enabled models
- No code execution capabilities
- No plugin/extension system
- No fine-tuning integration
- Limited visibility into specialized model features

**ReqLLM Support Analysis:**
Based on codebase inspection, ReqLLM provides:
- Embedding API (`ReqLLM.Embedding`)
- Tool calling framework (`ReqLLM.Tool`)
- Capability detection (`ReqLLM.Capability`)
- Provider-specific options (`provider_options`)
- Response format control (`response_format`)

**Missing in ReqLLM:**
- No explicit RAG model support
- No code execution API
- No plugin system
- No fine-tuning API

### User Impact

Without specialized feature support:
- **Developers**: Cannot leverage advanced provider capabilities
- **RAG Applications**: Must build retrieval externally even when model supports it
- **Code Tasks**: Cannot use built-in code execution for data analysis
- **Customization**: Cannot integrate fine-tuned models effectively
- **Competitive Gap**: Other frameworks (LangChain, LlamaIndex) support these features

### Impact Analysis

**High Priority Features:**
1. RAG model integration (Cohere Command-R, future Anthropic citations)
2. Code execution where supported (OpenAI Code Interpreter)

**Medium Priority Features:**
3. Plugin system architecture (extensible for future providers)
4. Fine-tuning integration (OpenAI, Google fine-tuned models)

---

## Solution Overview

### High-Level Approach

Create an extensible feature system that:

1. **Feature Detection**: Identify specialized capabilities from model metadata
2. **Graceful Degradation**: Handle unsupported features without breaking
3. **Provider Abstraction**: Unified API across different provider implementations
4. **Explicit Configuration**: Clear opt-in for specialized features
5. **Future-Proof**: Designed to accommodate new provider features

### Design Principles

1. **Explicit Over Implicit**: Users must opt-in to specialized features
2. **Fail Gracefully**: Unsupported features return clear errors, don't crash
3. **Provider-Agnostic**: Abstract common patterns, support provider-specific details
4. **Non-Breaking**: Existing APIs unchanged, all features optional
5. **Documentation-First**: Clear guides for each feature type
6. **Metadata-Driven**: Use ReqLLM metadata and capability system

### Module Architecture

```
lib/jido_ai/
├── specialized_features.ex           # Main feature detection/routing
├── specialized_features/
│   ├── rag.ex                        # RAG model integration
│   ├── code_execution.ex             # Code interpreter support
│   ├── plugins.ex                    # Plugin/extension system
│   └── fine_tuning.ex                # Fine-tuned model integration
├── model/
│   └── capability_index.ex           # Enhanced with specialized features

test/jido_ai/
├── specialized_features/
│   ├── rag_test.exs
│   ├── code_execution_test.exs
│   ├── plugins_test.exs
│   └── fine_tuning_test.exs
└── integration/
    └── specialized_features_integration_test.exs
```

---

## Research & Analysis

### RAG Model Capabilities Research

**Providers with Native RAG Support:**

1. **Cohere Command-R / Command-R+**
   - Built-in document retrieval
   - Citation support in responses
   - Documents passed as context in API
   - Format: `documents` parameter with `{"data": [...], "id": "..."}` structure

2. **Anthropic (Planned)**
   - Citation support in Claude 3.5
   - Extended context for document processing
   - No native retrieval yet, but document-aware responses

3. **OpenAI (Indirect)**
   - Retrieval via Assistants API (separate from chat completions)
   - File upload and retrieval
   - Not in standard chat completion API

4. **Google Gemini**
   - Grounding with Google Search
   - Document understanding with context caching
   - Semantic retrieval capabilities

**RAG Integration Patterns:**

```elixir
# Pattern 1: Documents as context (Cohere style)
ReqLLM.Generation.generate_text(
  "cohere:command-r-plus",
  "What is the capital of France?",
  documents: [
    %{id: "doc1", data: "France information..."},
    %{id: "doc2", data: "Geography facts..."}
  ]
)

# Pattern 2: Extended context (Anthropic/Gemini style)
ReqLLM.Generation.generate_text(
  "anthropic:claude-3-5-sonnet",
  "Summarize these documents",
  provider_options: [
    documents: [...],
    enable_citations: true
  ]
)
```

### Code Execution Capabilities Research

**Providers with Code Execution:**

1. **OpenAI Code Interpreter**
   - Available in Assistants API
   - Executes Python code in sandbox
   - File upload/download support
   - Not in standard chat completion

2. **Anthropic (Artifacts/Claude)**
   - Frontend rendering only (not API feature)
   - Generates code for execution elsewhere
   - No server-side execution

3. **Local Models (Potential)**
   - Some local setups support code execution
   - Would require custom integration

**Code Execution Integration Approach:**

Since code execution is primarily in OpenAI Assistants API (not chat completions), the integration strategy is:

1. **Phase 1 (This Task)**: Detect code execution capability in metadata
2. **Phase 2 (Future)**: Assistants API integration if requested
3. **Alternative**: External execution wrapper for generated code

### Plugin and Extension Systems Research

**Provider Plugin Architectures:**

1. **OpenAI GPT Actions**
   - Custom API integrations
   - OAuth support
   - OpenAPI schema definitions
   - Configured in model, not per-request

2. **Anthropic MCP (Model Context Protocol)**
   - New protocol for extending Claude
   - Server-side integrations
   - Tool-like but more flexible
   - Still in beta

3. **Google Gemini Extensions**
   - Integration with Google services
   - Grounding with Search
   - Workspace integrations
   - API parameters for enabling

**Plugin Integration Pattern:**

```elixir
# Generic plugin configuration
%{
  plugins: [
    %{type: :search, provider: :google},
    %{type: :workspace, provider: :google, config: [...]}
  ]
}

# Provider-specific handling via provider_options
provider_options: [
  extensions: ["google_search"],
  grounding: true
]
```

### Fine-Tuning Integration Research

**Providers Supporting Fine-Tuning:**

1. **OpenAI**
   - Fine-tune GPT-4, GPT-3.5
   - Upload training data via API
   - Create fine-tuned model IDs
   - Use like standard models: `ft:gpt-4-0613:org-id:custom-model:abc123`

2. **Google Vertex AI**
   - Fine-tune PaLM, Gemini
   - Training jobs via API
   - Custom model endpoints
   - Model versioning

3. **Anthropic**
   - Fine-tuning announced but limited availability
   - Custom model access via enterprise
   - Not yet in public API

4. **Open-Source Models**
   - Fine-tune locally (LLaMA, Mistral, etc.)
   - Deploy to local/cloud endpoints
   - Use as custom providers

**Fine-Tuning Integration Approach:**

1. **Model ID Support**: Accept fine-tuned model IDs (e.g., `ft:gpt-4-...`)
2. **Metadata Enhancement**: Store fine-tuning info in model metadata
3. **Discovery**: Filter models by fine-tuned vs. base
4. **Training API** (Future): Wrapper for creating fine-tuned models

---

## Technical Architecture

### Feature Detection System

**Enhanced Capability Index:**

Extend `Jido.AI.Model.CapabilityIndex` to include specialized features:

```elixir
# New capabilities to detect:
:rag_support          # Native document retrieval
:code_execution       # Built-in code interpreter
:plugins              # Supports plugin/extension system
:fine_tuned           # Is a fine-tuned model
:citations            # Supports response citations
:grounding            # Supports external grounding (search, etc.)
```

**Metadata Structure:**

```elixir
%Jido.AI.Model{
  capabilities: %{
    # Existing capabilities
    tool_call: true,
    streaming: true,
    # New specialized capabilities
    rag_support: true,
    citations: true,
    code_execution: false,
    plugins: ["google_search"],
    fine_tuned: false
  },
  specialized_features: %{
    rag: %{
      document_format: :cohere,  # :cohere, :anthropic, :custom
      max_documents: 10,
      citation_support: true
    },
    plugins: %{
      available: ["google_search", "workspace"],
      requires_config: true
    }
  }
}
```

### RAG Module Design

**Module: `Jido.AI.SpecializedFeatures.RAG`**

```elixir
defmodule Jido.AI.SpecializedFeatures.RAG do
  @moduledoc """
  Retrieval-Augmented Generation (RAG) model integration.

  Provides support for models with native RAG capabilities, enabling
  document-aware responses with citations.
  """

  @doc """
  Checks if a model supports RAG features.
  """
  @spec supports_rag?(Model.t()) :: boolean()

  @doc """
  Prepares documents for RAG-enabled request.

  Converts documents to provider-specific format.
  """
  @spec prepare_documents([map()], Model.t()) :: {:ok, map()} | {:error, term()}

  @doc """
  Executes a RAG-enabled request with documents.
  """
  @spec generate_with_documents(Model.t(), Prompt.t(), [map()], keyword())
    :: {:ok, Response.t()} | {:error, term()}

  @doc """
  Extracts citations from RAG response.
  """
  @spec extract_citations(Response.t()) :: [map()]
end
```

**Document Format:**

```elixir
# Standard document structure
%{
  id: "doc-123",
  content: "Document text content...",
  metadata: %{
    source: "example.pdf",
    page: 5,
    timestamp: ~U[2025-01-01 00:00:00Z]
  }
}
```

### Code Execution Module Design

**Module: `Jido.AI.SpecializedFeatures.CodeExecution`**

```elixir
defmodule Jido.AI.SpecializedFeatures.CodeExecution do
  @moduledoc """
  Code execution capabilities for AI models.

  Supports models with built-in code interpreters or provides
  wrapper for external code execution.
  """

  @doc """
  Checks if a model supports code execution.
  """
  @spec supports_code_execution?(Model.t()) :: boolean()

  @doc """
  Executes code via model's built-in interpreter.

  ## Options
  - `:language` - Programming language (default: :python)
  - `:timeout` - Execution timeout in ms
  - `:files` - Files to upload for code execution
  """
  @spec execute_code(Model.t(), String.t(), keyword())
    :: {:ok, CodeResult.t()} | {:error, term()}

  @doc """
  Generates code and executes it externally.

  For models without native execution, generates code
  and optionally executes via external runner.
  """
  @spec generate_and_execute(Model.t(), Prompt.t(), keyword())
    :: {:ok, CodeResult.t()} | {:error, term()}
end

defmodule Jido.AI.SpecializedFeatures.CodeResult do
  @typedoc "Result of code execution"
  typedstruct do
    field(:code, String.t())           # Generated/executed code
    field(:output, String.t())         # Execution output
    field(:error, String.t() | nil)    # Error if execution failed
    field(:artifacts, [map()])         # Files, images, etc.
    field(:execution_time, integer())  # Execution time in ms
  end
end
```

### Plugin System Design

**Module: `Jido.AI.SpecializedFeatures.Plugins`**

```elixir
defmodule Jido.AI.SpecializedFeatures.Plugins do
  @moduledoc """
  Plugin and extension system for AI models.

  Provides abstraction over provider-specific plugin systems
  (GPT Actions, MCP, Gemini Extensions).
  """

  @doc """
  Lists available plugins for a model.
  """
  @spec list_plugins(Model.t()) :: {:ok, [Plugin.t()]} | {:error, term()}

  @doc """
  Enables plugins for a request.
  """
  @spec enable_plugins(Model.t(), [plugin_id :: String.t()], keyword())
    :: {:ok, map()} | {:error, term()}

  @doc """
  Configures a plugin with provider-specific options.
  """
  @spec configure_plugin(plugin_id :: String.t(), config :: map())
    :: {:ok, Plugin.t()} | {:error, term()}
end

defmodule Jido.AI.SpecializedFeatures.Plugin do
  @typedoc "Plugin definition"
  typedstruct do
    field(:id, String.t())
    field(:name, String.t())
    field(:provider, atom())
    field(:type, atom())  # :search, :workspace, :custom
    field(:config, map())
    field(:enabled, boolean(), default: false)
  end
end
```

### Fine-Tuning Integration Design

**Module: `Jido.AI.SpecializedFeatures.FineTuning`**

```elixir
defmodule Jido.AI.SpecializedFeatures.FineTuning do
  @moduledoc """
  Fine-tuned model integration and management.

  Supports using fine-tuned models and discovering available
  custom models from providers.
  """

  @doc """
  Checks if a model is fine-tuned.
  """
  @spec fine_tuned?(Model.t()) :: boolean()

  @doc """
  Gets base model information for a fine-tuned model.
  """
  @spec get_base_model(Model.t()) :: {:ok, Model.t()} | {:error, term()}

  @doc """
  Lists available fine-tuned models for a provider.
  """
  @spec list_fine_tuned_models(provider :: atom())
    :: {:ok, [Model.t()]} | {:error, term()}

  @doc """
  Parses fine-tuned model ID to extract metadata.

  ## Examples
      parse_model_id("ft:gpt-4-0613:org:custom:abc123")
      #=> {:ok, %{base: "gpt-4-0613", org: "org", name: "custom", id: "abc123"}}
  """
  @spec parse_model_id(String.t()) :: {:ok, map()} | {:error, term()}
end
```

### Main Feature Module

**Module: `Jido.AI.SpecializedFeatures`**

```elixir
defmodule Jido.AI.SpecializedFeatures do
  @moduledoc """
  Central hub for specialized model features.

  Provides feature detection, routing, and unified API
  for accessing specialized capabilities.
  """

  alias Jido.AI.SpecializedFeatures.{RAG, CodeExecution, Plugins, FineTuning}

  @doc """
  Detects all specialized features supported by a model.
  """
  @spec detect_features(Model.t()) :: %{
    rag: boolean(),
    code_execution: boolean(),
    plugins: [String.t()],
    fine_tuned: boolean()
  }

  @doc """
  Validates that a model supports required features.
  """
  @spec validate_features(Model.t(), required :: [atom()])
    :: :ok | {:error, term()}

  @doc """
  Gets detailed information about a feature.
  """
  @spec feature_info(Model.t(), feature :: atom())
    :: {:ok, map()} | {:error, :not_supported}
end
```

### Integration with Existing Systems

**Integration Points:**

1. **Model Registry** (`Jido.AI.Model.Registry`)
   - Add specialized feature filters
   - Example: `discover_models(features: [:rag_support])`

2. **Capability Index** (`Jido.AI.Model.CapabilityIndex`)
   - Index specialized capabilities
   - Fast lookups by feature

3. **Actions** (`Jido.AI.Actions.Instructor`)
   - Support specialized features in chat actions
   - Pass through feature options

4. **ReqLLM Bridge** (`Jido.AI.ReqLlmBridge`)
   - Convert feature options to ReqLLM format
   - Handle provider-specific transformations

---

## Implementation Plan

### Subtask 2.5.3.1: RAG Model Integration

**Goal:** Enable support for models with native retrieval-augmented generation.

#### Step 1.1: Feature Detection for RAG

**Create:** `lib/jido_ai/specialized_features/rag.ex`

**Implementation:**
```elixir
defmodule Jido.AI.SpecializedFeatures.RAG do
  @doc """
  Detects RAG support from model metadata.

  Checks for:
  - Cohere Command-R models (explicit RAG support)
  - Anthropic citation capabilities
  - Google grounding features
  """
  @spec supports_rag?(Model.t()) :: boolean()
  def supports_rag?(model) do
    # Check capabilities map
    Map.get(model.capabilities || %{}, :rag_support, false) ||
    # Check provider-specific patterns
    detect_provider_rag_support(model)
  end

  defp detect_provider_rag_support(%{provider: :cohere, model: model_name}) do
    String.contains?(model_name, "command-r")
  end

  defp detect_provider_rag_support(%{provider: :google}) do
    # Gemini supports grounding
    true
  end

  defp detect_provider_rag_support(_), do: false
end
```

**Tests:**
- Test RAG detection for Cohere Command-R
- Test RAG detection for Google Gemini
- Test negative cases (non-RAG models)

#### Step 1.2: Document Preparation

**Implementation:**
```elixir
@doc """
Prepares documents for RAG request.

Converts standard document format to provider-specific format.
"""
@spec prepare_documents([map()], Model.t()) :: {:ok, map()} | {:error, term()}
def prepare_documents(documents, model) when is_list(documents) do
  case model.provider do
    :cohere -> prepare_cohere_documents(documents)
    :google -> prepare_google_documents(documents)
    :anthropic -> prepare_anthropic_documents(documents)
    _ -> {:error, :rag_not_supported}
  end
end

defp prepare_cohere_documents(documents) do
  formatted = Enum.map(documents, fn doc ->
    %{
      "id" => doc.id || generate_doc_id(),
      "data" => doc.content,
      "metadata" => doc.metadata || %{}
    }
  end)

  {:ok, %{documents: formatted}}
end
```

**Tests:**
- Test document formatting for each provider
- Test metadata preservation
- Test empty document list
- Test invalid document structure

#### Step 1.3: RAG-Enabled Generation

**Implementation:**
```elixir
@doc """
Generates response with RAG documents.

Automatically detects provider format and includes documents.
"""
@spec generate_with_documents(Model.t(), Prompt.t(), [map()], keyword())
  :: {:ok, Response.t()} | {:error, term()}
def generate_with_documents(model, prompt, documents, opts \\ []) do
  with {:ok, true} <- validate_rag_support(model),
       {:ok, doc_params} <- prepare_documents(documents, model),
       {:ok, response} <- execute_rag_request(model, prompt, doc_params, opts) do
    {:ok, enhance_response_with_citations(response)}
  end
end
```

**Tests:**
- Integration test with Cohere Command-R (if API key available)
- Test citation extraction
- Test error handling for unsupported models
- Test document limit enforcement

#### Step 1.4: Citation Extraction

**Implementation:**
```elixir
@doc """
Extracts citations from RAG response.

Returns list of citations with document references.
"""
@spec extract_citations(Response.t()) :: [Citation.t()]
def extract_citations(response) do
  response
  |> get_citation_data()
  |> parse_citations()
end

defmodule Citation do
  @typedoc "Citation reference from RAG response"
  typedstruct do
    field(:text, String.t())        # Cited text
    field(:document_id, String.t()) # Source document ID
    field(:start, integer())        # Start position in response
    field(:end, integer())          # End position in response
  end
end
```

**Deliverables:**
- ✅ RAG module with feature detection
- ✅ Document preparation for major providers
- ✅ Citation extraction
- ✅ Comprehensive tests
- ✅ Usage documentation

---

### Subtask 2.5.3.2: Code Execution Capabilities

**Goal:** Support models with code execution and provide external execution wrapper.

#### Step 2.1: Code Execution Detection

**Create:** `lib/jido_ai/specialized_features/code_execution.ex`

**Implementation:**
```elixir
defmodule Jido.AI.SpecializedFeatures.CodeExecution do
  @doc """
  Checks if model supports code execution.

  Current support:
  - OpenAI models via Assistants API (detected but not implemented)
  - Detection for future code execution models
  """
  @spec supports_code_execution?(Model.t()) :: boolean()
  def supports_code_execution?(model) do
    Map.get(model.capabilities || %{}, :code_execution, false) ||
    detect_code_execution_support(model)
  end

  defp detect_code_execution_support(%{provider: :openai}) do
    # OpenAI supports via Assistants API
    # Note: Not in standard chat completions
    false  # Mark as false until Assistants API integrated
  end

  defp detect_code_execution_support(_), do: false
end
```

**Tests:**
- Test detection for OpenAI models
- Test negative cases

#### Step 2.2: Code Generation with Execution Intent

**Implementation:**
```elixir
@doc """
Generates code with execution metadata.

Prompts model to generate executable code and returns
structured result with code ready for external execution.
"""
@spec generate_code(Model.t(), Prompt.t(), keyword())
  :: {:ok, CodeResult.t()} | {:error, term()}
def generate_code(model, prompt, opts \\ []) do
  language = Keyword.get(opts, :language, :python)

  # Enhance prompt for code generation
  enhanced_prompt = add_code_generation_context(prompt, language)

  with {:ok, response} <- generate_with_model(model, enhanced_prompt),
       {:ok, code} <- extract_code_from_response(response, language) do
    {:ok, %CodeResult{
      code: code,
      language: language,
      model: model.id
    }}
  end
end
```

**Tests:**
- Test code extraction from markdown code blocks
- Test multiple code block handling
- Test language detection

#### Step 2.3: External Code Execution Wrapper

**Implementation:**
```elixir
@doc """
Executes generated code externally (optional).

Provides wrapper for executing code via external runner.
Not enabled by default for security.
"""
@spec execute_code_external(CodeResult.t(), keyword())
  :: {:ok, CodeResult.t()} | {:error, term()}
def execute_code_external(code_result, opts \\ []) do
  if Keyword.get(opts, :allow_execution, false) do
    # Implementation would use external runner
    # For now, return error as not implemented
    {:error, :external_execution_not_implemented}
  else
    {:error, :execution_disabled_for_security}
  end
end
```

**Tests:**
- Test execution disabled by default
- Test security guards

#### Step 2.4: Documentation and Safety

**Create documentation:**
- Security considerations for code execution
- External execution setup guide
- Code generation best practices

**Deliverables:**
- ✅ Code execution detection
- ✅ Code generation with structured output
- ✅ Security-conscious design
- ✅ Clear documentation on limitations
- ✅ Tests

---

### Subtask 2.5.3.3: Plugin and Extension Support

**Goal:** Create extensible plugin system for provider-specific features.

#### Step 3.1: Plugin Discovery

**Create:** `lib/jido_ai/specialized_features/plugins.ex`

**Implementation:**
```elixir
defmodule Jido.AI.SpecializedFeatures.Plugins do
  @doc """
  Discovers available plugins for a model.
  """
  @spec list_plugins(Model.t()) :: {:ok, [Plugin.t()]} | {:error, term()}
  def list_plugins(model) do
    plugins =
      model
      |> get_plugin_metadata()
      |> parse_available_plugins()

    {:ok, plugins}
  end

  defp get_plugin_metadata(%{capabilities: caps}) do
    Map.get(caps, :plugins, [])
  end

  defp parse_available_plugins(plugin_list) when is_list(plugin_list) do
    Enum.map(plugin_list, &create_plugin_struct/1)
  end
end
```

**Tests:**
- Test plugin discovery for Google Gemini
- Test plugin discovery for models without plugins
- Test plugin metadata parsing

#### Step 3.2: Plugin Configuration

**Implementation:**
```elixir
@doc """
Configures plugins for a request.

Builds provider-specific configuration from generic plugin specs.
"""
@spec configure_plugins([Plugin.t()], Model.t())
  :: {:ok, map()} | {:error, term()}
def configure_plugins(plugins, model) do
  case model.provider do
    :google -> configure_gemini_extensions(plugins)
    _ -> {:ok, %{}}  # No plugins for this provider
  end
end

defp configure_gemini_extensions(plugins) do
  extensions = Enum.map(plugins, fn plugin ->
    case plugin.type do
      :search -> "google_search_retrieval"
      :code -> "code_execution"
      _ -> nil
    end
  end)
  |> Enum.reject(&is_nil/1)

  {:ok, %{tools: extensions}}
end
```

**Tests:**
- Test Gemini extension configuration
- Test unsupported provider handling
- Test invalid plugin types

#### Step 3.3: Plugin-Enabled Generation

**Implementation:**
```elixir
@doc """
Generates response with plugins enabled.
"""
@spec generate_with_plugins(Model.t(), Prompt.t(), [Plugin.t()], keyword())
  :: {:ok, Response.t()} | {:error, term()}
def generate_with_plugins(model, prompt, plugins, opts \\ []) do
  with {:ok, plugin_config} <- configure_plugins(plugins, model),
       merged_opts <- merge_plugin_options(opts, plugin_config),
       {:ok, response} <- execute_with_plugins(model, prompt, merged_opts) do
    {:ok, response}
  end
end
```

**Tests:**
- Integration test with Google Gemini grounding
- Test plugin error handling
- Test plugin result parsing

**Deliverables:**
- ✅ Plugin discovery system
- ✅ Provider-specific configuration
- ✅ Plugin-enabled generation
- ✅ Extensible architecture for new plugin types
- ✅ Tests and documentation

---

### Subtask 2.5.3.4: Fine-Tuning Integration

**Goal:** Support fine-tuned models and provide discovery capabilities.

#### Step 4.1: Fine-Tuned Model Detection

**Create:** `lib/jido_ai/specialized_features/fine_tuning.ex`

**Implementation:**
```elixir
defmodule Jido.AI.SpecializedFeatures.FineTuning do
  @doc """
  Detects if a model is fine-tuned.

  Checks for fine-tuned model ID patterns:
  - OpenAI: ft:gpt-4-0613:org:name:id
  - Google: projects/PROJECT/locations/LOCATION/models/MODEL
  """
  @spec fine_tuned?(Model.t()) :: boolean()
  def fine_tuned?(model) do
    case model.provider do
      :openai -> String.starts_with?(model.model, "ft:")
      :google -> String.contains?(model.model, "projects/")
      _ -> Map.get(model.capabilities || %{}, :fine_tuned, false)
    end
  end
end
```

**Tests:**
- Test OpenAI fine-tuned model detection
- Test Google fine-tuned model detection
- Test regular model returns false

#### Step 4.2: Model ID Parsing

**Implementation:**
```elixir
@doc """
Parses fine-tuned model ID to extract metadata.

## Examples
    parse_model_id("ft:gpt-4-0613:org:custom:abc123")
    #=> {:ok, %{
      base_model: "gpt-4-0613",
      organization: "org",
      name: "custom",
      suffix: "abc123"
    }}
"""
@spec parse_model_id(String.t()) :: {:ok, map()} | {:error, term()}
def parse_model_id("ft:" <> rest) do
  case String.split(rest, ":") do
    [base, org, name, suffix] ->
      {:ok, %{
        base_model: base,
        organization: org,
        name: name,
        suffix: suffix,
        provider: :openai
      }}
    _ ->
      {:error, :invalid_model_id_format}
  end
end

def parse_model_id(model_id) do
  {:error, :not_fine_tuned_model}
end
```

**Tests:**
- Test OpenAI format parsing
- Test Google format parsing
- Test invalid formats
- Test regular model IDs

#### Step 4.3: Base Model Resolution

**Implementation:**
```elixir
@doc """
Gets base model information for a fine-tuned model.
"""
@spec get_base_model(Model.t()) :: {:ok, Model.t()} | {:error, term()}
def get_base_model(model) do
  if fine_tuned?(model) do
    case parse_model_id(model.model) do
      {:ok, %{base_model: base_id}} ->
        # Look up base model in registry
        Registry.get_model(model.provider, base_id)

      {:error, reason} ->
        {:error, reason}
    end
  else
    {:error, :not_fine_tuned}
  end
end
```

**Tests:**
- Test base model lookup
- Test error handling for missing base models
- Test regular models

#### Step 4.4: Fine-Tuned Model Discovery

**Implementation:**
```elixir
@doc """
Lists available fine-tuned models for a provider.

Filters registry for fine-tuned models.
"""
@spec list_fine_tuned_models(provider :: atom())
  :: {:ok, [Model.t()]} | {:error, term()}
def list_fine_tuned_models(provider) do
  with {:ok, models} <- Registry.discover_models(provider: provider) do
    fine_tuned = Enum.filter(models, &fine_tuned?/1)
    {:ok, fine_tuned}
  end
end
```

**Tests:**
- Test filtering fine-tuned models
- Test empty results for providers without fine-tuned models
- Test multiple fine-tuned models

**Deliverables:**
- ✅ Fine-tuned model detection
- ✅ Model ID parsing
- ✅ Base model resolution
- ✅ Discovery utilities
- ✅ Tests and documentation

---

### Integration Testing

**Create:** `test/jido_ai/integration/specialized_features_integration_test.exs`

**Test Scenarios:**

1. **RAG End-to-End** (if Cohere API key available)
   - Generate with documents
   - Extract citations
   - Verify document references

2. **Code Generation**
   - Generate Python code
   - Extract code blocks
   - Verify executable format

3. **Plugin Discovery**
   - List plugins for Gemini
   - Configure extensions
   - Generate with plugins

4. **Fine-Tuned Models**
   - Parse model IDs
   - Resolve base models
   - List fine-tuned models

**Deliverables:**
- ✅ Comprehensive integration tests
- ✅ Provider-specific test coverage
- ✅ Documentation of test requirements

---

## Testing Strategy

### Unit Testing

**Per Subtask:**

1. **RAG Tests** (`test/jido_ai/specialized_features/rag_test.exs`)
   - Feature detection
   - Document preparation
   - Citation extraction
   - Provider-specific formatting

2. **Code Execution Tests** (`test/jido_ai/specialized_features/code_execution_test.exs`)
   - Feature detection
   - Code extraction
   - Security guards
   - Result structure

3. **Plugin Tests** (`test/jido_ai/specialized_features/plugins_test.exs`)
   - Plugin discovery
   - Configuration building
   - Provider mapping
   - Error handling

4. **Fine-Tuning Tests** (`test/jido_ai/specialized_features/fine_tuning_test.exs`)
   - Model ID parsing
   - Fine-tuned detection
   - Base model resolution
   - Discovery filtering

### Integration Testing

**Test Coverage:**
- RAG with real providers (if keys available)
- Code generation end-to-end
- Plugin-enabled generation
- Fine-tuned model usage

**Mock Testing:**
- Mock provider responses for unavailable APIs
- Test error paths
- Test unsupported features

### Property-Based Testing

Use StreamData for:
- Model ID parsing (various formats)
- Document structure validation
- Plugin configuration combinations

---

## Success Criteria

### Subtask 2.5.3.1: RAG Model Integration

- [ ] RAG support detected from model metadata
- [ ] Documents prepared for Cohere format
- [ ] Documents prepared for Google format
- [ ] Citations extracted from responses
- [ ] `generate_with_documents/4` works end-to-end
- [ ] Tests cover all providers
- [ ] Documentation includes RAG usage guide
- [ ] Integration test with Cohere (if key available)

### Subtask 2.5.3.2: Code Execution

- [ ] Code execution capability detected
- [ ] Code blocks extracted from responses
- [ ] `generate_code/3` returns structured results
- [ ] Security guards prevent accidental execution
- [ ] Documentation warns about security
- [ ] External execution documented but not implemented
- [ ] Tests cover code extraction patterns

### Subtask 2.5.3.3: Plugin Support

- [ ] Plugins discovered from model metadata
- [ ] Google Gemini extensions configured
- [ ] Generic plugin interface defined
- [ ] Provider-specific mapping implemented
- [ ] `generate_with_plugins/4` works with Gemini
- [ ] Extensible for future plugin types
- [ ] Tests cover plugin configuration
- [ ] Documentation explains plugin system

### Subtask 2.5.3.4: Fine-Tuning Integration

- [ ] Fine-tuned models detected by ID pattern
- [ ] OpenAI model IDs parsed correctly
- [ ] Google model IDs parsed correctly
- [ ] Base model resolution works
- [ ] Fine-tuned models filterable in registry
- [ ] Tests cover all parsing patterns
- [ ] Documentation explains fine-tuned model usage

### Overall Success

- [ ] All subtasks completed
- [ ] Comprehensive test suite (>90% coverage)
- [ ] Integration tests pass
- [ ] Documentation complete
- [ ] No breaking changes to existing APIs
- [ ] Feature detection integrated with capability index
- [ ] Usage guides for each feature type

---

## Risk Mitigation

### Risk 1: Limited Provider Support

**Risk:** Most specialized features are provider-specific and may not be available.

**Mitigation:**
- Clear feature detection before use
- Graceful degradation with helpful errors
- Document which providers support which features
- Design for extensibility as providers add features

### Risk 2: API Changes

**Risk:** Provider APIs for specialized features may change frequently.

**Mitigation:**
- Abstract behind generic interfaces
- Version-specific handling where needed
- Monitor provider documentation
- Add deprecation warnings early

### Risk 3: Security Concerns

**Risk:** Code execution and external plugins pose security risks.

**Mitigation:**
- Code execution disabled by default
- Clear warnings in documentation
- No automatic execution of generated code
- External execution requires explicit opt-in

### Risk 4: Testing Challenges

**Risk:** Testing specialized features requires provider API keys.

**Mitigation:**
- Mock-based tests for unavailable APIs
- Integration tests run only when keys present
- Document test requirements clearly
- Use fixtures for repeatable tests

### Risk 5: Feature Complexity

**Risk:** Each feature has unique requirements and edge cases.

**Mitigation:**
- Start with simple implementations
- Iterate based on user feedback
- Clear documentation of limitations
- Explicit error messages for unsupported cases

### Risk 6: Performance Impact

**Risk:** RAG and plugin features may increase latency.

**Mitigation:**
- Document performance implications
- Lazy loading of plugin configurations
- Cache plugin metadata
- Monitor and log feature usage time

---

## Implementation Notes

### Dependencies

**No new external dependencies required.**

All features use existing dependencies:
- ReqLLM for API calls
- Existing Jido.AI modules
- Standard library for parsing

### Configuration

**Optional configuration in `config/config.exs`:**

```elixir
config :jido_ai, :specialized_features,
  # Enable/disable features
  rag_enabled: true,
  code_execution_enabled: false,  # Security: disabled by default
  plugins_enabled: true,

  # Feature-specific settings
  rag: [
    max_documents: 10,
    max_document_size: 100_000  # characters
  ],

  code_execution: [
    allow_external: false,  # Never enable in production
    timeout: 30_000
  ],

  plugins: [
    cache_ttl: 3600  # seconds
  ]
```

### Documentation Requirements

**Create usage guides:**

1. `docs/specialized-features/rag-guide.md`
   - Using RAG models
   - Document preparation
   - Citation handling
   - Provider comparison

2. `docs/specialized-features/code-execution-guide.md`
   - Code generation
   - Security considerations
   - External execution setup
   - Use cases

3. `docs/specialized-features/plugins-guide.md`
   - Plugin system overview
   - Provider-specific plugins
   - Configuration examples
   - Custom plugins (future)

4. `docs/specialized-features/fine-tuning-guide.md`
   - Using fine-tuned models
   - Model ID formats
   - Base model resolution
   - Training overview (external)

### Future Enhancements

**Phase 3 Considerations:**

1. **RAG Enhancements**
   - Vector database integration
   - Custom retrieval strategies
   - Hybrid search support

2. **Code Execution**
   - Assistants API integration for OpenAI
   - Sandboxed execution environment
   - Multi-language support

3. **Plugin Ecosystem**
   - Custom plugin registration
   - Plugin marketplace
   - Third-party integrations

4. **Fine-Tuning**
   - Training job submission
   - Model versioning
   - A/B testing support

---

## Timeline Estimate

- Subtask 2.5.3.1 (RAG): 4-5 hours
  - Feature detection: 1 hour
  - Document preparation: 1.5 hours
  - Citation extraction: 1 hour
  - Testing: 1.5 hours

- Subtask 2.5.3.2 (Code Execution): 3-4 hours
  - Detection and generation: 1.5 hours
  - Code extraction: 1 hour
  - Security and docs: 1 hour
  - Testing: 1 hour

- Subtask 2.5.3.3 (Plugins): 3-4 hours
  - Discovery: 1 hour
  - Configuration: 1 hour
  - Integration: 1 hour
  - Testing: 1 hour

- Subtask 2.5.3.4 (Fine-Tuning): 2-3 hours
  - Detection: 0.5 hours
  - Parsing: 1 hour
  - Discovery: 0.5 hours
  - Testing: 1 hour

- Integration & Documentation: 2-3 hours
  - Integration tests: 1 hour
  - Documentation: 1-2 hours

**Total: 14-19 hours**

---

## Conclusion

Task 2.5.3 adds support for specialized model features that extend beyond basic chat completion. The implementation provides:

1. **RAG Integration**: Native support for retrieval-augmented generation models
2. **Code Execution**: Detection and structured code generation
3. **Plugin System**: Extensible architecture for provider-specific features
4. **Fine-Tuning**: Support for custom fine-tuned models

The design is:
- **Non-breaking**: All features are optional additions
- **Provider-agnostic**: Generic interfaces with provider-specific implementations
- **Security-conscious**: Code execution disabled by default
- **Extensible**: Designed to accommodate new features as providers evolve

This completes Phase 2's Advanced Features section and enables users to leverage cutting-edge capabilities from modern AI providers.
