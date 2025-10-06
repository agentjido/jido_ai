# Provider Comparison Matrix

This guide provides a comprehensive comparison of all 57+ AI providers accessible through Jido AI via the unified ReqLLM integration.

## Quick Provider Selection

**Need speed?** → [High-Performance Providers](high-performance.md) (Groq, Together AI, Cerebras)
**Need specialized features?** → [Specialized Providers](specialized.md) (Cohere RAG, Perplexity Search)
**Need privacy/offline?** → [Local Providers](local-models.md) (Ollama, LMStudio)
**Enterprise deployment?** → [Enterprise Providers](enterprise.md) (Azure, Bedrock, Vertex)
**Regional compliance?** → [Regional Providers](regional.md) (Alibaba, Zhipu)

## Provider Categories

### High-Performance Providers
Optimized for speed and throughput.

| Provider | Models | Speed | Rate Limit | Key Feature |
|----------|--------|-------|------------|-------------|
| **Groq** | 8+ | ⚡ Ultra-fast (<500ms) | 30 RPM (free) | Fastest inference |
| **Together AI** | 100+ | ⚡ Very fast | 600 RPM | Model variety |
| **Cerebras** | 5+ | ⚡ Ultra-fast | Varies | Long context |
| **Fireworks** | 50+ | ⚡ Fast | 600 RPM | Custom models |

### Specialized Providers
Providers with unique capabilities.

| Provider | Models | Key Feature | Best For |
|----------|--------|-------------|----------|
| **Cohere** | 10+ | Native RAG support | Document Q&A |
| **Perplexity** | 5+ | Search integration | Research queries |
| **Replicate** | 1000+ | Model marketplace | Experimentation |
| **AI21 Labs** | 5+ | Jurassic models | Multilingual |

### Local & Self-Hosted
Run models on your own infrastructure.

| Provider | Setup | Privacy | Cost |
|----------|-------|---------|------|
| **Ollama** | Easy | 🔒 Full | Free |
| **LMStudio** | Easy | 🔒 Full | Free |
| **Llama.cpp** | Advanced | 🔒 Full | Free |
| **vLLM** | Advanced | 🔒 Full | Free |

### Enterprise Providers
Enterprise-grade features and SLAs.

| Provider | Auth | Compliance | Multi-Tenant | SLA |
|----------|------|------------|--------------|-----|
| **Azure OpenAI** | Entra ID | ✅ SOC2, HIPAA | ✅ | 99.9% |
| **Amazon Bedrock** | IAM | ✅ SOC2, HIPAA | ✅ | 99.9% |
| **Google Vertex AI** | Service Account | ✅ SOC2, HIPAA | ✅ | 99.95% |

### Regional Providers
Providers for specific geographic regions.

| Provider | Region | Compliance | Models |
|----------|--------|------------|--------|
| **Alibaba Cloud** | China | Chinese regulations | Qwen series |
| **Zhipu AI** | China | Chinese regulations | GLM models |
| **Moonshot AI** | China | Chinese regulations | Moonshot models |

## Detailed Provider Matrix

### OpenAI Family

| Provider | Models | Features | Rate Limit | Context | Cost |
|----------|--------|----------|------------|---------|------|
| **OpenAI** | 20+ | Tools, Vision, Audio | 3500 RPM | 128K | $$ |
| **Azure OpenAI** | 15+ | Enterprise features | Custom | 128K | $$$ |
| **OpenRouter** | All providers | Unified routing | Varies | Varies | $ |

### Anthropic Family

| Provider | Models | Features | Rate Limit | Context | Cost |
|----------|--------|----------|------------|---------|------|
| **Anthropic** | 5+ | Extended thinking, MCP | 4000 RPM | 200K | $$ |
| **AWS Bedrock** | Claude models | Enterprise | Custom | 200K | $$$ |

### Google Family

| Provider | Models | Features | Rate Limit | Context | Cost |
|----------|--------|----------|------------|---------|------|
| **Google AI** | 10+ | Gemini, multimodal | 60 RPM | 2M | $$ |
| **Vertex AI** | 10+ | Enterprise, grounding | Custom | 2M | $$$ |

## Feature Support Matrix

### Core Features

| Provider | Streaming | Tools | Vision | Audio | JSON Mode |
|----------|-----------|-------|--------|-------|-----------|
| OpenAI | ✅ | ✅ | ✅ | ✅ | ✅ |
| Anthropic | ✅ | ✅ | ✅ | ❌ | ✅ |
| Google | ✅ | ✅ | ✅ | ✅ | ✅ |
| Cohere | ✅ | ✅ | ❌ | ❌ | ✅ |
| Groq | ✅ | ✅ | ❌ | ❌ | ✅ |

### Advanced Features

| Provider | RAG | Code Execution | Plugins | Fine-Tuning |
|----------|-----|----------------|---------|-------------|
| OpenAI | ❌ | ✅ (Assistants) | ✅ Actions | ✅ |
| Anthropic | ✅ | ❌ | ✅ MCP | ❌ |
| Google | ✅ Grounding | ❌ | ✅ Extensions | ✅ |
| Cohere | ✅ Native | ❌ | ❌ | ✅ |

## Usage Examples

### Using Any Provider

All providers are accessible through the unified interface:

```elixir
# High-performance provider
{:ok, response} = Jido.AI.chat("groq:llama-3.1-70b", "Hello!")

# Specialized provider
{:ok, response} = Jido.AI.chat("cohere:command-r-plus", "Search query")

# Local provider
{:ok, response} = Jido.AI.chat("ollama:llama2", "Private query")

# Enterprise provider
{:ok, response} = Jido.AI.chat("azure:gpt-4", "Enterprise query")
```

### Provider-Specific Features

```elixir
# Cohere with RAG
alias Jido.AI.Features.RAG

documents = [%{content: "...", title: "Doc 1"}]
{:ok, opts} = RAG.build_rag_options(documents, %{}, :cohere)
{:ok, response} = Jido.AI.chat("cohere:command-r-plus", prompt, opts)

# OpenAI with code execution
alias Jido.AI.Features.CodeExecution

opts = CodeExecution.build_code_exec_options(%{}, :openai, enable: true)
{:ok, response} = Jido.AI.chat("openai:gpt-4", "Calculate...", opts)
```

## Provider Selection Guide

### Choose Based on Requirements

**Speed is critical:**
- Primary: Groq (fastest)
- Fallback: Together AI, Cerebras

**Cost optimization:**
- Primary: Groq (free tier)
- Fallback: OpenRouter (pay-per-use)

**Privacy/Compliance:**
- Primary: Local (Ollama)
- Fallback: Enterprise (Azure, Bedrock)

**Advanced features:**
- RAG: Cohere, Google
- Vision: OpenAI, Google, Anthropic
- Long context: Google (2M), Anthropic (200K)

**Production reliability:**
- Primary: Azure OpenAI (99.9% SLA)
- Fallback: AWS Bedrock (99.9% SLA)

### Fallback Chain Example

```elixir
# Define fallback chain
providers = [
  "groq:llama-3.1-70b",      # Try fast provider first
  "openai:gpt-4-turbo",      # Fallback to reliable
  "anthropic:claude-3-sonnet" # Final fallback
]

# Implement fallback logic
def chat_with_fallback(providers, prompt) do
  Enum.reduce_while(providers, {:error, :all_failed}, fn provider, _acc ->
    case Jido.AI.chat(provider, prompt) do
      {:ok, response} -> {:halt, {:ok, response}}
      {:error, _} -> {:cont, {:error, :all_failed}}
    end
  end)
end
```

## Authentication & Configuration

### API Key Management

All providers use the unified Keyring system:

```elixir
# Set API keys via environment
export OPENAI_API_KEY="sk-..."
export ANTHROPIC_API_KEY="sk-..."
export GROQ_API_KEY="gsk_..."

# Or via Keyring
Jido.AI.Keyring.set(:openai, "sk-...")
Jido.AI.Keyring.set(:anthropic, "sk-...")
```

### Provider-Specific Configuration

See individual provider guides for detailed setup:
- [High-Performance Providers](high-performance.md)
- [Specialized Providers](specialized.md)
- [Local Providers](local-models.md)
- [Enterprise Providers](enterprise.md)
- [Regional Providers](regional.md)

## Performance Benchmarks

### Latency Comparison (approximate)

| Provider | Cold Start | Avg Response | Streaming |
|----------|-----------|--------------|-----------|
| Groq | <100ms | 200-500ms | ⚡ Real-time |
| Together AI | <200ms | 500-1000ms | ⚡ Fast |
| OpenAI | <500ms | 1-3s | ✅ Good |
| Anthropic | <500ms | 2-4s | ✅ Good |
| Local (Ollama) | Instant | 2-10s | ⚡ Local |

### Throughput (requests per minute)

| Provider | Free Tier | Paid Tier |
|----------|-----------|-----------|
| Groq | 30 RPM | 6000 RPM |
| Together AI | 60 RPM | 3000 RPM |
| OpenAI | 3 RPM | 3500 RPM |
| Anthropic | 5 RPM | 4000 RPM |

## Cost Comparison

### Per 1M Tokens (approximate)

| Provider | Input | Output | Notes |
|----------|-------|--------|-------|
| Groq | Free (tier) | Free (tier) | Limited RPM |
| Together AI | $0.20 | $0.20 | Varies by model |
| OpenAI GPT-4 | $10 | $30 | Premium |
| OpenAI GPT-3.5 | $0.50 | $1.50 | Budget |
| Anthropic Claude | $3 | $15 | Mid-range |
| Local | $0 | $0 | Hardware cost |

## Next Steps

- [Getting Started Guide](../getting-started.md) - Set up your first provider
- [Provider Category Guides](.) - Deep-dive into specific provider types
- [Advanced Features](../features/) - Use specialized capabilities
- [Migration Guide](../migration/from-legacy-providers.md) - Upgrade from legacy code

## Troubleshooting

See the [Troubleshooting Guide](../troubleshooting.md) for common provider issues.
