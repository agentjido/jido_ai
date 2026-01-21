# Task 2.7: Documentation and Migration Guides - Planning Document

**Task**: Phase 2, Section 2.7 - Documentation and Migration Guides
**Branch**: `feature/task-2-7-documentation-migration-guides`
**Date**: 2025-10-06
**Status**: Planning

---

## 1. Problem Statement

### Why Documentation is Critical for Adoption

The ReqLLM integration has successfully provided access to 57+ AI providers and 2000+ models through a unified interface, representing a massive expansion from the original 4-provider implementation. However, this expansion creates significant challenges for adoption:

**Current Documentation Gaps**:

1. **Provider Discovery Problem**: Users don't know that 57+ providers are available or how to use them
   - Current guides only mention 4-5 providers explicitly (Anthropic, OpenAI, OpenRouter, Cloudflare, Google)
   - No comprehensive provider listing or comparison
   - Missing provider-specific configuration examples

2. **Migration Complexity**: Users have existing code using the old provider-specific implementations
   - Public API modules like `Jido.AI.Actions.OpenaiEx` remain but internals changed
   - No guide explaining what changed and why
   - Missing before/after migration examples

3. **Feature Discoverability**: Advanced capabilities are hidden
   - RAG, code execution, plugins, fine-tuning features exist but aren't documented
   - No guide on which providers support which features
   - Specialized model features lack usage examples

4. **Getting Started Friction**: New users face unclear paths
   - Multiple ways to configure providers (ReqLLM bridge vs. legacy modules)
   - API key management has multiple approaches
   - Unclear which approach to use for different scenarios

**Impact of Poor Documentation**:
- Users won't adopt the new unified system
- Support burden increases with repeated questions
- Advanced features remain unused
- Migration from legacy code stalls
- Competitive disadvantage vs. well-documented libraries

### Documentation as a Product

Good documentation is not an afterthought—it's a core product feature that:
- **Reduces friction**: Gets users productive in minutes, not hours
- **Builds trust**: Shows the library is mature and well-maintained
- **Enables self-service**: Users solve problems without asking maintainers
- **Drives adoption**: Clear examples lead to faster integration
- **Prevents errors**: Good guides prevent common mistakes

---

## 2. Solution Overview

### Documentation Strategy

Create a **comprehensive, layered documentation system** that serves users at different levels of expertise and different stages of adoption:

**Layer 1: Quick Start** (5-minute path to success)
- Single-page getting started guide
- Copy-paste examples for common providers
- Minimal configuration, maximum results

**Layer 2: Provider Coverage** (Comprehensive provider reference)
- Provider comparison matrix (all 57+ providers)
- Category-based grouping (high-performance, specialized, local, enterprise, regional)
- Provider-specific quick-start guides
- Configuration examples for each provider

**Layer 3: Migration Guides** (Smooth upgrade path)
- Migration from legacy provider-specific code
- Breaking changes documentation
- Before/after code examples
- Common migration pitfalls and solutions

**Layer 4: Advanced Features** (Power user documentation)
- RAG integration guide
- Code execution safety guide
- Plugin system documentation
- Fine-tuning integration
- Multi-modal capabilities

**Layer 5: API Reference** (Technical depth)
- ExDoc-generated API documentation
- Function-level documentation
- Type specifications
- Usage examples in doctests

### Documentation Structure

```
guides/
├── getting-started.md           # ✅ Exists, needs update
├── providers.md                 # ✅ Exists, needs major expansion
├── keyring.md                   # ✅ Exists, good state
├── prompt.md                    # ✅ Exists, good state
├── agent-skill.md               # ✅ Exists, good state
├── actions.md                   # ✅ Exists, good state
├── migration/
│   ├── from-legacy-providers.md    # ❌ NEW - Critical for adoption
│   ├── breaking-changes.md         # ❌ NEW - Version migration
│   └── reqllm-integration.md       # ❌ NEW - Deep dive
├── providers/
│   ├── provider-matrix.md          # ❌ NEW - All 57+ providers
│   ├── high-performance.md         # ❌ NEW - Groq, Together, Cerebras
│   ├── specialized.md              # ❌ NEW - Cohere, Perplexity, etc.
│   ├── local-models.md             # ❌ NEW - Ollama, LMStudio, Llama
│   ├── enterprise.md               # ❌ NEW - Azure, Bedrock, Vertex
│   └── regional.md                 # ❌ NEW - Alibaba, Zhipu, etc.
├── features/
│   ├── rag-integration.md          # ❌ NEW - RAG guide
│   ├── code-execution.md           # ❌ NEW - Safety-first guide
│   ├── plugins.md                  # ❌ NEW - Plugin systems
│   ├── fine-tuning.md              # ❌ NEW - Fine-tuned models
│   ├── context-windows.md          # ❌ NEW - Context management
│   └── advanced-parameters.md      # ❌ NEW - Generation params
└── troubleshooting.md              # ❌ NEW - Common issues
```

### Documentation Tools

**Primary Tool**: ExDoc (already configured in mix.exs)
- **Version**: 0.37-rc (latest)
- **Format**: Markdown guides + inline module documentation
- **Output**: Static HTML documentation site
- **Hosting**: HexDocs (automatic on hex.pm publish)

**Supporting Tools**:
- **Doctests**: Executable documentation examples
- **Typespecs**: Type documentation in ExDoc
- **Mermaid**: Diagrams in documentation (supported by ExDoc)
- **Markdown**: All guides in standard Markdown

### Documentation Principles

1. **Show, Don't Tell**: Every concept has a working code example
2. **Copy-Paste Ready**: Examples work without modification
3. **Progressive Disclosure**: Simple first, complexity later
4. **Error Prevention**: Common mistakes highlighted upfront
5. **Maintenance Friendly**: Single source of truth, DRY principles

---

## 3. Agent Consultations Performed

Before creating this plan, I consulted the required agents:

### Research Agent Consultation

**Question**: What are the best practices for documenting Elixir libraries with ExDoc, especially for multi-provider API libraries?

**Key Findings**:
1. **ExDoc Best Practices**:
   - Use `@moduledoc` for module-level documentation with examples
   - Use `@doc` for function documentation with typespecs
   - Include doctests for all public functions (executable examples)
   - Organize guides in guides/ directory, referenced in mix.exs
   - Use `## Examples` sections extensively

2. **Multi-Provider Documentation Patterns**:
   - **Provider Matrix**: Tabular comparison of features across providers
   - **Quick-Start Per Provider**: Copy-paste examples for each provider
   - **Unified API Documentation**: Show how single API works across all providers
   - **Migration Guides**: Before/after examples for version upgrades

3. **Elixir Library Documentation Benchmarks**:
   - **Ecto**: Excellent migration guides, clear before/after examples
   - **Phoenix**: Outstanding getting-started with progressive complexity
   - **Req**: Simple, focused documentation with extensive examples
   - **Ash Framework**: Comprehensive guides with real-world scenarios

4. **Documentation Site Structure**:
   - **Landing Page**: Quick wins in first 5 minutes
   - **Guides**: Task-based, scenario-based organization
   - **API Reference**: Auto-generated from source
   - **FAQ/Troubleshooting**: Common issues with solutions

### Elixir Expert Consultation

**Question**: How should we structure Jido AI documentation for ExDoc? What are Elixir documentation conventions we must follow?

**Key Findings**:
1. **ExDoc Configuration**:
   - Already properly configured in mix.exs with `docs/0` function
   - Guides are properly listed in `extras` section
   - Main page set to README.md (correct convention)

2. **Elixir Documentation Conventions**:
   - **Moduledoc**: Required for all public modules
   - **Typespecs**: Required for all public functions
   - **Examples**: Required in @doc for complex functions
   - **Since Annotations**: Use `@since "0.6.0"` for new features
   - **Deprecated**: Use `@deprecated` for legacy code

3. **Guide Organization**:
   - **Guides should be task-oriented**: "How to use Groq provider" not "Groq provider reference"
   - **Progressive disclosure**: Getting started → Common tasks → Advanced features
   - **Cross-linking**: Link between guides and API docs extensively
   - **Code examples first**: Show code before explaining

4. **Jido AI Specific**:
   - Current guides/ structure is good foundation
   - Need provider-specific guides (missing)
   - Need migration guides (critical gap)
   - Keep guides DRY (use includes if possible)

### Senior Engineer Review

**Question**: What's the best strategy for documenting 57+ providers without creating maintenance hell? How to structure migration docs?

**Key Recommendations**:
1. **Provider Documentation Strategy**:
   - **Don't document every provider individually**: Unsustainable
   - **Group by category**: High-performance, specialized, local, enterprise, regional
   - **Provider matrix as canonical reference**: Single table with all providers
   - **Deep-dive guides for major categories**: 5-6 category guides vs. 57 provider guides
   - **Link to ReqLLM docs for provider details**: Don't duplicate their work

2. **Migration Documentation Strategy**:
   - **Focus on breaking changes**: What users MUST change
   - **Before/after examples**: Most effective migration tool
   - **Common patterns**: Show 5-6 common migration scenarios
   - **Automated helpers**: Provide mix tasks or scripts where possible
   - **Version-based organization**: Clear "from X.X to Y.Y" structure

3. **Maintenance Considerations**:
   - **Generate provider matrix from code**: Don't maintain manually
   - **Test documentation examples**: Use doctests everywhere
   - **Single source of truth**: Link to canonical docs, don't duplicate
   - **Automate what you can**: Mix tasks for doc generation

4. **Documentation Debt Prevention**:
   - **Document as you build**: Don't defer to "documentation sprint"
   - **Documentation review in PRs**: Every feature needs docs
   - **Deprecation strategy**: Clear timeline for removing old docs
   - **Versioned documentation**: Keep old version docs available

---

## 4. Technical Details

### Documentation Location

**Primary Documentation**:
- **Location**: `/home/ducky/code/agentjido/jido_ai_integrate_req_llm/guides/`
- **Format**: Markdown (.md files)
- **Processing**: ExDoc (configured in mix.exs)
- **Output**: HTML documentation site
- **Hosting**: HexDocs (https://hexdocs.pm/jido_ai)

**Module Documentation**:
- **Location**: Inline in source files (`lib/jido_ai/**/*.ex`)
- **Format**: ExDoc annotations (@moduledoc, @doc, @typedoc)
- **Processing**: ExDoc extracts during `mix docs`

### Tools and Dependencies

**ExDoc Configuration** (from mix.exs):
```elixir
defp docs do
  [
    main: "readme",
    source_ref: "v#{@version}",
    source_url: @source_url,
    extras: [
      "README.md",
      {"guides/getting-started.md", title: "Getting Started"},
      {"guides/keyring.md", title: "Managing Keys"},
      {"guides/prompt.md", title: "Prompting"},
      {"guides/providers.md", title: "LLM Providers"},
      {"guides/agent-skill.md", title: "Agent & Skill"},
      {"guides/actions.md", title: "Actions"}
    ]
  ]
end
```

**Required Updates**:
```elixir
defp docs do
  [
    main: "readme",
    source_ref: "v#{@version}",
    source_url: @source_url,
    extras: [
      "README.md",
      # Getting Started
      {"guides/getting-started.md", title: "Getting Started"},

      # Core Concepts
      {"guides/keyring.md", title: "Managing Keys"},
      {"guides/prompt.md", title: "Prompting"},
      {"guides/agent-skill.md", title: "Agent & Skill"},
      {"guides/actions.md", title: "Actions"},

      # Providers
      {"guides/providers.md", title: "Provider Overview"},
      {"guides/providers/provider-matrix.md", title: "Provider Matrix"},
      {"guides/providers/high-performance.md", title: "High-Performance Providers"},
      {"guides/providers/specialized.md", title: "Specialized Providers"},
      {"guides/providers/local-models.md", title: "Local Models"},
      {"guides/providers/enterprise.md", title: "Enterprise Providers"},
      {"guides/providers/regional.md", title: "Regional Providers"},

      # Advanced Features
      {"guides/features/rag-integration.md", title: "RAG Integration"},
      {"guides/features/code-execution.md", title: "Code Execution"},
      {"guides/features/plugins.md", title: "Plugins"},
      {"guides/features/fine-tuning.md", title: "Fine-Tuning"},
      {"guides/features/context-windows.md", title: "Context Windows"},
      {"guides/features/advanced-parameters.md", title: "Advanced Parameters"},

      # Migration
      {"guides/migration/from-legacy-providers.md", title: "Migration Guide"},
      {"guides/migration/breaking-changes.md", title: "Breaking Changes"},
      {"guides/migration/reqllm-integration.md", title: "ReqLLM Integration Deep-Dive"},

      # Troubleshooting
      {"guides/troubleshooting.md", title: "Troubleshooting"}
    ],
    groups_for_extras: [
      "Getting Started": [
        "guides/getting-started.md"
      ],
      "Core Concepts": [
        "guides/keyring.md",
        "guides/prompt.md",
        "guides/agent-skill.md",
        "guides/actions.md"
      ],
      "Providers": ~r/guides\/providers\/.*/,
      "Advanced Features": ~r/guides\/features\/.*/,
      "Migration": ~r/guides\/migration\/.*/,
      "Troubleshooting": [
        "guides/troubleshooting.md"
      ]
    ]
  ]
end
```

### Provider Matrix Generation Strategy

**Challenge**: Manually maintaining a matrix of 57+ providers is error-prone.

**Solution**: Generate provider matrix from ReqLLM's provider registry.

**Implementation**:
```elixir
# mix task: lib/mix/tasks/jido_ai/gen_provider_docs.ex
defmodule Mix.Tasks.JidoAi.GenProviderDocs do
  use Mix.Task

  @shortdoc "Generates provider documentation from ReqLLM registry"

  def run(_args) do
    Mix.Task.run("app.start")

    providers = ReqLLM.Provider.Generated.ValidProviders.list()

    # Generate provider matrix markdown
    matrix_md = generate_provider_matrix(providers)
    File.write!("guides/providers/provider-matrix.md", matrix_md)

    # Generate category-specific guides
    generate_category_guides(providers)

    Mix.shell().info("Generated provider documentation for #{length(providers)} providers")
  end

  defp generate_provider_matrix(providers) do
    # Query ReqLLM for provider metadata
    # Generate markdown table with:
    # - Provider name
    # - Supported features (chat, embeddings, streaming)
    # - Key configuration
    # - Link to provider website
  end

  defp generate_category_guides(providers) do
    # Group providers by category
    # Generate quick-start guide for each category
  end
end
```

### Documentation Testing Strategy

**Doctests**: Every code example in documentation must be executable
```elixir
defmodule Jido.AI.Provider do
  @moduledoc """
  Unified provider interface for all LLM providers.

  ## Examples

      iex> {:ok, model} = Jido.AI.Model.from({:anthropic, [model: "claude-3-5-haiku"]})
      iex> is_struct(model, Jido.AI.Model)
      true

      iex> {:ok, model} = Jido.AI.Model.from({:groq, [model: "llama-3.1-70b-versatile"]})
      iex> model.provider
      :groq
  """
end
```

**Documentation Validation Mix Task**:
```elixir
# mix task to validate all documentation examples
mix test --only doctest
```

### ExDoc Features to Leverage

1. **Grouping**: Group modules by functionality
2. **Annotations**: `@since`, `@deprecated`, `@doc false`
3. **Type Documentation**: Automatic type reference generation
4. **Search**: Built-in search across all docs
5. **Diagrams**: Mermaid diagram support
6. **Cross-linking**: Auto-linking to modules and functions

---

## 5. Success Criteria

### Quantitative Metrics

1. **Coverage Completeness**:
   - ✅ All 57+ providers documented in provider matrix
   - ✅ All 6 provider categories have dedicated guides
   - ✅ All 6 advanced features have dedicated guides
   - ✅ Migration guide covers all breaking changes
   - ✅ At least 5 migration code examples (before/after)

2. **Code Example Coverage**:
   - ✅ Every guide has at least 3 working code examples
   - ✅ All examples pass doctests
   - ✅ Provider matrix has configuration example for each category
   - ✅ Migration guide has complete before/after examples

3. **Module Documentation Coverage**:
   - ✅ 100% of public modules have @moduledoc
   - ✅ 100% of public functions have @doc
   - ✅ 100% of public functions have @spec (typespecs)
   - ✅ All modules have at least 1 usage example

4. **Documentation Structure**:
   - ✅ All guides appear in ExDoc navigation
   - ✅ Guides grouped by category in navigation
   - ✅ Cross-links work between guides and API docs
   - ✅ `mix docs` builds without warnings

### Qualitative Metrics

1. **User Experience**:
   - ✅ New user can complete first API call in 5 minutes
   - ✅ Provider discovery is obvious (matrix on main providers page)
   - ✅ Migration path is clear and step-by-step
   - ✅ Advanced features are discoverable

2. **Maintenance Quality**:
   - ✅ Provider matrix generated from code (not manual)
   - ✅ No duplication between guides (DRY)
   - ✅ Links to ReqLLM docs rather than duplicating
   - ✅ Documentation testing in CI

3. **Completeness**:
   - ✅ All Phase 2 features documented
   - ✅ Breaking changes clearly called out
   - ✅ Security considerations documented (especially code execution)
   - ✅ Troubleshooting guide covers common issues

### Validation Tests

**Documentation Build Test**:
```bash
mix docs  # Must complete without warnings
```

**Doctest Coverage**:
```bash
mix test --only doctest  # All doctests must pass
```

**Link Validation**:
```bash
# Check for broken links in documentation
mix docs.check_links
```

**Example Validation**:
```bash
# Run all examples from guides as integration tests
mix test.docs.examples
```

---

## 6. Implementation Plan

### Phase 1: Foundation and Infrastructure (Days 1-2)

**Objective**: Set up documentation infrastructure and update existing guides

#### Task 1.1: Update ExDoc Configuration
- **File**: `mix.exs`
- **Changes**:
  - Add all new guides to `extras` list
  - Configure `groups_for_extras` for navigation
  - Add `groups_for_modules` for API organization
- **Validation**: `mix docs` builds successfully

#### Task 1.2: Create Documentation Generation Mix Task
- **File**: `lib/mix/tasks/jido_ai/gen_provider_docs.ex`
- **Purpose**: Generate provider matrix from ReqLLM registry
- **Features**:
  - Query ReqLLM for all providers
  - Generate markdown table with provider info
  - Group providers by category
  - Generate category-specific quick-starts
- **Validation**: `mix jido_ai.gen_provider_docs` creates valid markdown

#### Task 1.3: Set Up Documentation Testing
- **Create**: `test/docs/` directory
- **Add**: Doctest helpers
- **Configure**: Documentation example validation
- **Validation**: `mix test.docs` runs successfully

#### Task 1.4: Update README.md
- **Changes**:
  - Update provider count (57+ providers)
  - Add links to new documentation
  - Update quick-start example
  - Add migration notice for existing users
- **Validation**: README renders correctly on GitHub

### Phase 2: Provider Documentation (Days 3-5)

**Objective**: Create comprehensive provider documentation

#### Task 2.1: Generate and Refine Provider Matrix
- **File**: `guides/providers/provider-matrix.md`
- **Content**:
  - Auto-generated table of all 57+ providers
  - Columns: Provider, Category, Features, Setup, Links
  - Grouped by category for easy scanning
  - Configuration examples for each category
- **Method**: Run `mix jido_ai.gen_provider_docs`, then manual refinement
- **Validation**: Matrix is accurate, links work

#### Task 2.2: Update Provider Overview Guide
- **File**: `guides/providers.md` (existing, major update)
- **Content**:
  - Overview of unified provider system
  - Link to provider matrix
  - Provider categories explanation
  - ReqLLM integration benefits
  - How to choose a provider
- **Examples**:
  - Using any provider through unified interface
  - Switching between providers
  - Provider fallback patterns
- **Validation**: Examples run in doctests

#### Task 2.3: High-Performance Providers Guide
- **File**: `guides/providers/high-performance.md` (new)
- **Providers**: Groq, Together AI, Cerebras, Fireworks
- **Content**:
  - Performance characteristics
  - Best use cases
  - Configuration examples
  - Benchmarking guidance
  - Cost comparison
- **Examples**: Each provider with chat completion
- **Validation**: Examples tested with provider APIs

#### Task 2.4: Specialized Providers Guide
- **File**: `guides/providers/specialized.md` (new)
- **Providers**: Cohere, Perplexity, Replicate, Hugging Face
- **Content**:
  - Unique capabilities of each provider
  - When to use specialized providers
  - Integration examples
  - RAG-optimized providers (Cohere)
  - Search-enhanced models (Perplexity)
- **Examples**: Provider-specific features
- **Validation**: Feature examples verified

#### Task 2.5: Local Models Guide
- **File**: `guides/providers/local-models.md` (new)
- **Providers**: Ollama, LMStudio, Llama.cpp
- **Content**:
  - Local model benefits (privacy, cost, offline)
  - Setup and installation
  - Model download and management
  - Performance considerations
  - Network configuration
- **Examples**:
  - Ollama setup and usage
  - LMStudio integration
  - Local model discovery
- **Validation**: Examples tested with local providers

#### Task 2.6: Enterprise Providers Guide
- **File**: `guides/providers/enterprise.md` (new)
- **Providers**: Azure OpenAI, Amazon Bedrock, Google Vertex AI
- **Content**:
  - Enterprise features (SLAs, compliance, security)
  - Authentication and authorization
  - VPC/VPN configuration
  - Multi-tenant setup
  - Cost management
- **Examples**:
  - Azure OpenAI with tenant config
  - AWS Bedrock with IAM roles
  - Vertex AI with service accounts
- **Validation**: Configuration examples verified

#### Task 2.7: Regional Providers Guide
- **File**: `guides/providers/regional.md` (new)
- **Providers**: Alibaba Cloud, Zhipu AI, Moonshot AI
- **Content**:
  - Regional provider benefits
  - Compliance and data residency
  - Language-specific models
  - Configuration for Chinese providers
- **Examples**: Regional provider setup
- **Validation**: Configuration validated

### Phase 3: Migration Documentation (Days 6-7)

**Objective**: Create clear migration path from legacy code

#### Task 3.1: Migration Guide from Legacy Providers
- **File**: `guides/migration/from-legacy-providers.md` (new)
- **Content**:
  - Why migrate to unified system
  - What's different in new system
  - Step-by-step migration process
  - 10+ before/after code examples:
    - OpenAI chat completion (old vs. new)
    - Anthropic with Instructor (old vs. new)
    - Multi-provider setup (old vs. new)
    - API key management (old vs. new)
    - Error handling (old vs. new)
    - Streaming responses (old vs. new)
    - Tool/function calling (old vs. new)
    - Embeddings generation (old vs. new)
    - Provider switching (old vs. new)
    - Configuration management (old vs. new)
  - Common migration pitfalls
  - Testing migration
- **Examples**: All before/after pairs tested
- **Validation**: Migration path verified with real code

#### Task 3.2: Breaking Changes Documentation
- **File**: `guides/migration/breaking-changes.md` (new)
- **Content**:
  - Version-by-version breaking changes
  - 0.5.x → 0.6.x changes (ReqLLM integration)
  - What requires code changes
  - What's backward compatible
  - Deprecation timeline
  - Workarounds for breaking changes
- **Format**: Organized by version, severity tagged
- **Validation**: All breaking changes documented

#### Task 3.3: ReqLLM Integration Deep-Dive
- **File**: `guides/migration/reqllm-integration.md` (new)
- **Content**:
  - Why ReqLLM was chosen
  - Architecture before and after
  - How unified bridge works
  - Provider mapping details
  - Performance implications
  - Troubleshooting integration issues
- **Audience**: Advanced users wanting deep understanding
- **Diagrams**: Architecture diagrams with Mermaid
- **Validation**: Technical accuracy reviewed

### Phase 4: Advanced Features Documentation (Days 8-10)

**Objective**: Document specialized model features from Task 2.5.3

#### Task 4.1: RAG Integration Guide
- **File**: `guides/features/rag-integration.md` (new)
- **Content**:
  - What is RAG and when to use it
  - Supported providers (Cohere, Google, Anthropic)
  - Document preparation for each provider
  - Citation extraction
  - RAG options configuration
  - Best practices
- **Examples**:
  - Cohere RAG with documents
  - Google Gemini RAG
  - Anthropic RAG
  - Citation parsing
- **Source**: `lib/jido_ai/features/rag.ex`
- **Validation**: Examples from test suite

#### Task 4.2: Code Execution Safety Guide
- **File**: `guides/features/code-execution.md` (new)
- **Content**:
  - Code execution capabilities overview
  - **Security warnings** (prominently displayed)
  - Supported providers (OpenAI)
  - Safety checks and environment validation
  - Opt-in configuration
  - Result extraction
  - Use cases and limitations
- **Examples**:
  - Enabling code execution (with warnings)
  - Safety check validation
  - Result parsing
- **Source**: `lib/jido_ai/features/code_execution.ex`
- **Validation**: Security warnings clear

#### Task 4.3: Plugins Guide
- **File**: `guides/features/plugins.md` (new)
- **Content**:
  - Plugin systems overview (OpenAI Actions, Anthropic MCP, Google Extensions)
  - Supported providers
  - Plugin configuration
  - Built-in plugin discovery
  - Custom plugin creation
  - Result extraction
- **Examples**:
  - OpenAI GPT Actions
  - Anthropic MCP server
  - Google Extensions
- **Source**: `lib/jido_ai/features/plugins.ex`
- **Validation**: Plugin examples tested

#### Task 4.4: Fine-Tuning Integration Guide
- **File**: `guides/features/fine-tuning.md` (new)
- **Content**:
  - Fine-tuned model detection
  - Supported providers (OpenAI, Google, Cohere, Together)
  - Model ID parsing
  - Base model resolution
  - Using fine-tuned models
- **Examples**:
  - OpenAI fine-tuned model usage
  - Google fine-tuned model
  - Fine-tune ID parsing
- **Source**: `lib/jido_ai/features/fine_tuning.ex`
- **Validation**: Model ID parsing examples

#### Task 4.5: Context Window Management Guide
- **File**: `guides/features/context-windows.md` (new)
- **Content**:
  - Context window overview
  - Automatic detection
  - Truncation strategies
  - Extended context models (100K+ tokens)
  - Token counting
  - Optimization utilities
- **Examples**:
  - Context window detection
  - Truncation strategies
  - Large context models
- **Source**: `lib/jido_ai/context_window.ex`
- **Validation**: Examples tested

#### Task 4.6: Advanced Generation Parameters Guide
- **File**: `guides/features/advanced-parameters.md` (new)
- **Content**:
  - JSON mode and structured output
  - Grammar-constrained generation
  - Logit bias
  - Token probability access
  - Provider-specific parameters
- **Examples**:
  - JSON mode usage
  - Structured output
  - Logit bias configuration
- **Validation**: Parameter examples tested

### Phase 5: Module Documentation Enhancement (Days 11-12)

**Objective**: Ensure all modules have complete inline documentation

#### Task 5.1: Audit Module Documentation Coverage
- **Tool**: Custom mix task to check coverage
- **Check**:
  - All public modules have @moduledoc
  - All public functions have @doc
  - All public functions have @spec
  - All modules have usage examples
- **Output**: Coverage report

#### Task 5.2: Add Missing Module Documentation
- **Modules to document**:
  - All `Jido.AI.Features.*` modules
  - All `Jido.AI.ReqLLMBridge.*` modules
  - Provider adapter modules
  - Model registry modules
- **Content for each**:
  - Clear module description
  - Usage examples
  - See also links
  - Since annotations

#### Task 5.3: Add Function Documentation
- **Focus**: Public functions without @doc
- **Content**:
  - Function purpose
  - Parameter descriptions
  - Return value description
  - Examples
  - Edge cases

#### Task 5.4: Add Typespecs
- **Focus**: Functions without @spec
- **Quality**: Use strict types, not any()
- **Validation**: Dialyzer passes

### Phase 6: Troubleshooting and Refinement (Days 13-14)

**Objective**: Create troubleshooting guide and polish all documentation

#### Task 6.1: Create Troubleshooting Guide
- **File**: `guides/troubleshooting.md` (new)
- **Sections**:
  - **Installation Issues**
    - Dependency conflicts
    - Version mismatches
  - **Authentication Errors**
    - API key not found
    - Invalid API key format
    - Rate limiting
  - **Provider-Specific Issues**
    - Provider unavailable
    - Model not found
    - Feature not supported
  - **Request Failures**
    - Timeout errors
    - Network issues
    - Invalid parameters
  - **Response Parsing**
    - Unexpected response format
    - Missing fields
  - **Migration Issues**
    - Breaking changes
    - Deprecated functions
- **Format**: Problem → Solution → Example
- **Validation**: Solutions tested

#### Task 6.2: Update Getting Started Guide
- **File**: `guides/getting-started.md` (existing, update)
- **Changes**:
  - Update to show ReqLLM providers
  - Add provider choice guidance
  - Update examples to new API
  - Add "What's Next" section linking to other guides
- **Validation**: Examples tested

#### Task 6.3: Cross-Link All Documentation
- **Task**: Add cross-links between all guides
- **Links**:
  - Getting started → Provider guides
  - Provider guides → Feature guides
  - Feature guides → API reference
  - Migration guide → Troubleshooting
  - All guides → Provider matrix
- **Validation**: No broken links

#### Task 6.4: Add Diagrams
- **Tool**: Mermaid diagrams in markdown
- **Diagrams to create**:
  - Architecture: Old vs. New (migration guide)
  - Provider flow: Request → ReqLLM → Provider (provider guide)
  - Feature detection: Model → Features (features guide)
  - Authentication: Keyring hierarchy (keyring guide)
- **Validation**: Diagrams render in ExDoc

#### Task 6.5: Documentation Review and Polish
- **Review checklist**:
  - ✅ All code examples tested
  - ✅ No typos or grammar issues
  - ✅ Consistent terminology
  - ✅ Consistent formatting
  - ✅ All links work
  - ✅ Navigation is logical
- **Tools**: Spell checker, link checker
- **Validation**: `mix docs` builds cleanly

### Phase 7: Testing and Validation (Day 15)

**Objective**: Comprehensive validation of all documentation

#### Task 7.1: Doctest Validation
```bash
mix test --only doctest
```
- All doctests pass
- Examples in guides execute correctly

#### Task 7.2: Documentation Build Validation
```bash
mix docs
```
- No warnings
- All guides appear in navigation
- All links work
- Search works

#### Task 7.3: Link Validation
```bash
mix docs.check_links
```
- No broken internal links
- No broken external links
- All cross-references valid

#### Task 7.4: Example Validation
- Manual validation of all provider examples
- Test with real API keys (where safe)
- Verify migration examples work

#### Task 7.5: User Testing
- Have fresh user follow getting started
- Time to first successful API call
- Identify friction points
- Collect feedback

---

## 7. Notes and Considerations

### Edge Cases and Challenges

#### Challenge 1: Provider Documentation Maintenance
**Problem**: 57+ providers will change over time (features added, deprecated, etc.)

**Solutions**:
1. **Generate from code**: Use mix task to auto-generate provider matrix from ReqLLM
2. **Link to ReqLLM docs**: For provider-specific details, link to authoritative source
3. **Versioned documentation**: Keep old version docs available on HexDocs
4. **Deprecation warnings**: Use `@deprecated` annotations for outdated features

#### Challenge 2: Example Code Maintenance
**Problem**: Code examples can break as API evolves

**Solutions**:
1. **Doctests everywhere**: All examples are tested
2. **CI testing**: Documentation tests run on every PR
3. **Version pinning**: Examples specify which version they're for
4. **Automated updates**: Mix task to update examples across docs

#### Challenge 3: Migration Path Complexity
**Problem**: Multiple migration paths (different starting points)

**Solutions**:
1. **Decision tree**: Help users identify their migration path
2. **Common scenarios**: Cover 80% of use cases with specific examples
3. **Migration checklist**: Step-by-step validation
4. **Automated migration helpers**: Mix tasks to help migration

#### Challenge 4: Documentation Versioning
**Problem**: Users on different versions need different docs

**Solutions**:
1. **HexDocs versioning**: Automatic version separation on hexdocs.pm
2. **Version badges**: Clear indication of what version docs apply to
3. **Changelog integration**: Link breaking changes to migration guide
4. **Search by version**: HexDocs provides this automatically

### Security Considerations

#### Code Execution Documentation
- **Warnings must be prominent**: Red warning boxes in docs
- **Opt-in emphasized**: Make it clear this is disabled by default
- **Security checklist**: Provide security review checklist
- **Production warnings**: Document why this is dangerous in production

#### API Key Documentation
- **Never show real keys**: All examples use placeholders
- **Security best practices**: Link to security guide
- **Keyring security**: Document security model clearly
- **Environment variables**: Recommend secure approaches

### Maintenance Strategy

#### Documentation Ownership
- **Primary maintainer**: Assigned documentation owner
- **Review process**: All PRs require documentation review
- **Update cadence**: Review docs quarterly for accuracy
- **Community contributions**: Guide for external doc contributions

#### Automated Maintenance
- **Provider matrix generation**: Automated from ReqLLM
- **Link checking**: CI job to check for broken links
- **Example testing**: All examples in CI
- **Version updates**: Automated version bumping in examples

#### Documentation Metrics
- **Track**: HexDocs page views (available from hex.pm)
- **Monitor**: GitHub issues tagged "documentation"
- **Survey**: Annual user survey on documentation quality
- **Analytics**: Which guides are most/least used

### Future Enhancements

#### Phase 3 Documentation Needs
When Phase 3 (multi-modal, advanced streaming) is implemented:
- Update provider matrix with multi-modal capabilities
- Add multi-modal guide (images, audio, video)
- Add advanced streaming guide
- Update feature detection documentation

#### Interactive Documentation
Future possibilities:
- **Interactive examples**: Live code editor in docs
- **Provider playground**: Test providers without setup
- **Migration tool**: Web-based migration helper
- **Video tutorials**: Screen recordings for complex features

#### Internationalization
Future expansion:
- **Chinese documentation**: For regional providers
- **Translation strategy**: Community-driven translations
- **Language-specific examples**: Localized examples

---

## 8. Dependencies and Prerequisites

### Required Before Starting

1. **Phase 2 Section 2.5 Complete**: ✅ (Specialized features implemented)
2. **ReqLLM Integration Stable**: ✅ (Phase 1 complete)
3. **Provider Registry Working**: ✅ (Model registry implemented)
4. **Features Module Complete**: ✅ (RAG, code execution, plugins, fine-tuning)

### Required During Implementation

1. **Access to Provider APIs**: For testing examples
2. **ReqLLM Documentation**: Reference for provider details
3. **ExDoc Latest Version**: 0.37-rc already installed
4. **Mix Tasks**: Provider docs generation task

### Deliverables

1. **Updated mix.exs**: ExDoc configuration with all guides
2. **16 new markdown guides**: In guides/ directory
3. **Updated existing guides**: 4 guides refreshed
4. **Mix task**: Provider docs generation
5. **Documentation tests**: Doctest coverage for all examples
6. **Module documentation**: 100% coverage of public modules
7. **Troubleshooting guide**: Common issues and solutions

---

## 9. Timeline

**Total Estimated Time**: 15 working days (3 weeks)

- **Phase 1 (Infrastructure)**: 2 days
- **Phase 2 (Provider Docs)**: 3 days
- **Phase 3 (Migration Docs)**: 2 days
- **Phase 4 (Feature Docs)**: 3 days
- **Phase 5 (Module Docs)**: 2 days
- **Phase 6 (Polish)**: 2 days
- **Phase 7 (Validation)**: 1 day

**Buffer**: Additional 2-3 days for unforeseen issues

---

## 10. Success Validation

### Documentation Completeness Checklist

- [ ] All 57+ providers in provider matrix
- [ ] 6 provider category guides complete
- [ ] Migration guide with 10+ examples
- [ ] Breaking changes documented
- [ ] 6 advanced feature guides complete
- [ ] Troubleshooting guide complete
- [ ] README updated
- [ ] All existing guides updated

### Technical Quality Checklist

- [ ] `mix docs` builds without warnings
- [ ] All doctests pass
- [ ] All links validated
- [ ] No broken cross-references
- [ ] Navigation is logical
- [ ] Search works correctly

### User Experience Checklist

- [ ] New user can complete first API call in 5 minutes
- [ ] Provider discovery is obvious
- [ ] Migration path is clear
- [ ] Advanced features are discoverable
- [ ] Error messages link to troubleshooting

### Maintenance Quality Checklist

- [ ] Provider matrix generated from code
- [ ] No documentation duplication
- [ ] Links to canonical sources
- [ ] Documentation tests in CI
- [ ] Version annotations present

---

## Conclusion

This comprehensive documentation plan will transform Jido AI from a library with 4 documented providers to a well-documented library showcasing 57+ providers with clear migration paths and extensive feature documentation. The documentation will serve as a key differentiator and adoption driver, making the ReqLLM integration accessible and valuable to all users.

The plan balances completeness with maintainability by:
- Generating provider matrix from code
- Linking to authoritative sources
- Testing all examples
- Automating what can be automated
- Focusing on user tasks over API reference

Success will be measured not just by documentation volume, but by user experience: time-to-first-success, discoverability, and clarity of migration path.
