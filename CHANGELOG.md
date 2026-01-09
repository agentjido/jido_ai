# Changelog

All notable changes to Jido AI will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - Unreleased (ReqLLM Integration)

### Major Changes

This is a major version release featuring a complete architectural shift from provider-specific implementations to a unified ReqLLM-based system. While the public API remains largely unchanged, the internal implementation has been completely rewritten to support 57+ AI providers through a single unified interface.

### Added - Core Infrastructure

#### ReqLLM Integration (Phase 1)
- **Unified Provider Access**: Access to 57+ AI providers (OpenAI, Anthropic, Google, Groq, Together AI, Cohere, Perplexity, and 50+ more) through a single unified API
- **ReqLLM Bridge Layer**: Translation layer between Jido AI's existing interfaces and ReqLLM's unified API
- **Model Registry**: Dynamic model discovery and capability detection across all providers
- **Provider Adapters**: Optimized adapters for each provider family (OpenAI-compatible, Anthropic, Google, etc.)

#### Enhanced Authentication
- **Hybrid Keyring System**: Integration of both Jido.AI.Keyring and JidoKeys for credential management
- **Environment Variable Support**: Automatic API key detection from environment variables
- **Session Authentication**: Support for enterprise authentication (Azure Entra ID, AWS IAM, Google Service Accounts)
- **Multi-Provider Key Management**: Unified credential storage for all 57+ providers

#### Streaming Architecture
- **Unified Streaming**: Consistent streaming API across all providers
- **Server-Sent Events (SSE)**: Native SSE support with automatic reconnection
- **Stream Aggregation**: Intelligent stream chunking and aggregation
- **Error Recovery**: Automatic retry and error handling in streams

#### Tool Integration
- **Universal Tool Calling**: Function/tool calling support across compatible providers
- **Tool Descriptor Translation**: Automatic conversion between provider-specific tool formats
- **Tool Execution Pipeline**: Standardized tool execution with response handling
- **Schema Validation**: JSON schema validation for tool parameters

### Added - Advanced Features (Phase 2)

#### Advanced Generation Parameters
- **Temperature Control**: Fine-grained control over randomness (0.0-2.0)
- **Top-P/Top-K Sampling**: Nucleus and top-k sampling strategies
- **Repetition Penalties**: Frequency and presence penalties to reduce repetition
- **Logit Bias**: Token-level probability adjustments (OpenAI/compatible providers)
- **JSON Mode**: Guaranteed JSON output (OpenAI, Groq, Together AI)
- **Provider-Specific Options**: Support for provider-specific parameters (reasoning_effort, top_logprobs, etc.)

#### Context Window Management
- **Automatic Detection**: Context limits automatically extracted from model metadata (4K-2M tokens)
- **Validation**: Pre-flight checks to ensure prompts fit within context windows
- **Intelligent Truncation**: Multiple strategies (keep_recent, keep_bookends, sliding_window, smart_truncate)
- **Token Counting**: Accurate provider-specific token estimation
- **Completion Reservation**: Automatic space reservation for model responses

#### Specialized Model Features
- **RAG Integration**: Native Retrieval-Augmented Generation support (Cohere, Google, Anthropic)
  - Document formatting and citation extraction
  - Multi-document context management
  - Semantic search integration
- **Code Execution**: Secure code interpretation (OpenAI GPT-4/3.5)
  - Sandboxed Python execution
  - Security controls and explicit opt-in
  - Result extraction and file handling
- **Plugins/Extensions**:
  - OpenAI GPT Actions (custom API integrations)
  - Anthropic MCP (Model Context Protocol) with security validation
  - Google Gemini Extensions (built-in tools)
- **Fine-Tuning Detection**: Automatic detection and management of fine-tuned models
  - Model ID parsing (OpenAI, Google, Cohere, Together formats)
  - Base model resolution
  - Capability inheritance checking

### Added - Documentation (Phase 2)

#### Comprehensive Guides (16 total)
- **Provider Documentation** (6 guides):
  - Provider comparison matrix for all 57+ providers
  - High-performance providers (Groq, Together AI, Cerebras, Fireworks)
  - Specialized providers (Cohere, Perplexity, Replicate, AI21 Labs)
  - Local/self-hosted providers (Ollama, LMStudio, Llama.cpp, vLLM)
  - Enterprise providers (Azure OpenAI, AWS Bedrock, Google Vertex AI, IBM watsonx)
  - Regional providers (Alibaba, Zhipu, Moonshot, Mistral)

- **Migration Guides** (3 guides):
  - Complete migration guide with 10 before/after scenarios
  - Breaking changes documentation
  - ReqLLM architecture deep-dive

- **Feature Guides** (6 guides):
  - RAG integration with semantic search patterns
  - Code execution with security-first approach
  - Plugins with validation and security controls
  - Fine-tuning model management
  - Context window management (4K-2M tokens)
  - Advanced generation parameters

- **Troubleshooting Guide**: Comprehensive guide with common issues and solutions

### Fixed
- **Image Support**: Fixed and enhanced support for Base64 data URLs and remote image URLs in `ReqLLM` chat completion action.

### Changed

#### Provider System
- **Internal Implementation**: All provider-specific code now routes through ReqLLM
- **Model Format**: Support for unified `provider:model` format (e.g., `"openai:gpt-4"`)
- **Response Normalization**: Consistent response format across all providers
- **Error Handling**: Unified error types and messages

#### API Keys
- **Keyring System**: Enhanced to support 57+ providers
- **Environment Variables**: Standardized environment variable naming (e.g., `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`)
- **Automatic Discovery**: Keys automatically discovered from environment when not explicitly set

#### Streaming
- **Unified Format**: Consistent streaming chunk format across all providers
- **Better Error Handling**: Improved error recovery in streaming scenarios
- **Server-Sent Events**: Native SSE support replacing custom implementations

### Deprecated

#### Module Usage (Soft Deprecation)
- Direct usage of provider-specific action modules (OpenaiEx, etc.) is discouraged but still functional
- Users should migrate to the unified `Jido.AI.chat/3` API
- Timeline:
  - v2.0.0: Soft deprecation (warnings in logs)
  - v2.1.0: Documentation removal
  - v3.0.0: Hard deprecation (compile warnings)
  - v4.0.0: Removal

#### Configuration
- Manual HTTP client configuration is deprecated in favor of ReqLLM's optimized defaults
- Per-request options should be used instead of global HTTP configuration

### Breaking Changes

#### Response Format
- Response structure normalized across all providers
- New fields: `provider`, `model`, `finish_reason`, `raw` (contains original response)
- Access pattern changes:
  - Old: `get_in(response, ["choices", 0, "message", "content"])`
  - New: `response.content`

#### Error Format
- Errors now return structured `%Jido.AI.Error{}` with normalized fields
- Consistent error types: `:authentication_error`, `:rate_limit`, `:timeout`, `:api_error`, etc.
- Status codes preserved in `:status` field

#### Model Specification
- Unified API requires `provider:model` format: `"openai:gpt-4"` instead of just `"gpt-4"`
- Legacy action modules still accept old format for backward compatibility

#### Streaming Chunks
- Stream chunks now return `%Jido.AI.StreamChunk{}` structs
- Consistent `.content` field across all providers
- Old provider-specific chunk parsing no longer needed

### Migration Guide

See `guides/migration/from-legacy-providers.md` for detailed migration instructions including:
- 10 before/after code scenarios
- Common pitfalls and solutions
- Testing strategies
- Step-by-step migration checklist

### Security

#### Enhanced Security Features
- **Plugin Security**: Command whitelist for MCP servers (only npx, node, python3, python allowed)
- **Environment Filtering**: Blocks environment variables with secret patterns (KEY, SECRET, TOKEN, PASSWORD)
- **Name Validation**: Plugin names must be alphanumeric with hyphens/underscores only
- **Code Execution**: Disabled by default, requires explicit opt-in with safety checks
- **Audit Logging**: Security violations logged for monitoring

#### Credential Management
- Secure keyring-based credential storage
- Support for managed identities and service accounts
- No credentials in code or version control

### Performance

#### Optimizations
- **Connection Pooling**: Automatic connection reuse across requests
- **Provider Selection**: Ability to use faster providers (Groq: <500ms, Together: <1s)
- **Streaming**: Reduced latency with immediate token streaming
- **Caching**: Support for response caching patterns
- **Batch Processing**: Concurrent request handling with Task.async_stream

### Compatibility

#### Backward Compatibility
- ✅ Existing action modules (OpenaiEx, Instructor, Langchain) continue to work
- ✅ Public API names unchanged (Jido.AI.Actions.*)
- ✅ Existing error handling patterns preserved
- ✅ Configuration structure maintained

#### Requirements
- Elixir ~> 1.17
- Erlang/OTP 26+
- ReqLLM ~> 0.1

### Known Issues
- Phase 2 advanced features require ReqLLM 0.1+ (not yet released)
- Some provider-specific features may have limited support in initial release
- Documentation for inline module `@moduledoc` pending (Phase 5)

### Contributors
Special thanks to all contributors who helped with the ReqLLM integration.

---

## [1.0.0] and Earlier

For changes prior to the ReqLLM integration, see the project's commit history.

### Notable Pre-2.0 Features
- Initial Jido AI framework
- OpenaiEx integration
- Instructor integration for structured outputs
- LangChain integration
- Basic keyring system
- Agent and Skill abstractions
- Prompt management
- Google Gemini support

---

## Migration Resources

- **Migration Guide**: `guides/migration/from-legacy-providers.md`
- **Breaking Changes**: `guides/migration/breaking-changes.md`
- **Architecture**: `guides/migration/reqllm-integration.md`
- **Troubleshooting**: `guides/troubleshooting.md`
- **Provider Matrix**: `guides/providers/provider-matrix.md`

## Documentation

Complete documentation available in the `guides/` directory:
- Provider guides (6 guides covering 57+ providers)
- Migration guides (3 guides)
- Feature guides (6 guides)
- Troubleshooting guide

Generate HTML documentation with:
```bash
mix docs
```

---

[2.0.0]: https://github.com/agentjido/jido_ai/compare/v1.0.0...v2.0.0
[1.0.0]: https://github.com/agentjido/jido_ai/releases/tag/v1.0.0
