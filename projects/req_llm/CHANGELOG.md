# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0-rc.1] - 2025-01-13

### Added
- First public release candidate
- Composable plugin architecture built on Req
- Support for 45+ providers and 665+ models via models.dev sync
- Typed data structures for all API interactions
- Dual API layers: low-level Req plugin and high-level helpers
- Built-in streaming support with typed StreamChunk responses
- Automatic usage and cost tracking
- Anthropic and OpenAI provider implementations
- Context Codec protocol for provider wire format conversion
- JidoKeys integration for secure API key management
- Comprehensive test matrix with fixture and live testing support
- Tool calling capabilities
- Embeddings generation support (OpenAI)
- Structured data generation with schema validation
- Extensive documentation and guides

### Features
- `ReqLLM.generate_text/3` and `generate_text!/3` for text generation
- `ReqLLM.stream_text/3` and `stream_text!/3` for streaming responses  
- `ReqLLM.generate_object/4` and `generate_object!/4` for structured output
- `ReqLLM.generate_embeddings/3` for vector embeddings
- `ReqLLM.run/3` for low-level Req plugin integration
- Provider-agnostic model specification with "provider:model" syntax
- Automatic model metadata loading and cost calculation
- Tool definition and execution framework
- Message and content part builders
- Usage statistics and cost tracking on all responses

### Technical
- Elixir ~> 1.15 compatibility
- OTP 24+ support  
- Apache-2.0 license
- Comprehensive documentation with HexDocs
- Quality tooling with Dialyzer, Credo, and formatter
- LiveFixture testing framework for API mocking

[1.0.0-rc.1]: https://github.com/agentjido/req_llm/releases/tag/v1.0.0-rc.1
