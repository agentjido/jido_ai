# Specialized Providers

Specialized providers offer unique capabilities beyond standard chat completion, such as native RAG support, search integration, or custom model deployment.

## Supported Providers

- **Cohere** - Native RAG and retrieval-augmented generation
- **Perplexity** - Search-augmented responses with citations
- **Replicate** - 1000+ community models marketplace
- **AI21 Labs** - Jurassic models with multilingual support

## When to Use Specialized Providers

**Best for:**
- RAG applications (document Q&A, knowledge bases)
- Search-augmented queries (research, fact-checking)
- Experimentation with cutting-edge models
- Multilingual content generation

**Not ideal for:**
- Basic chat completion (use standard providers)
- Maximum speed (use high-performance providers)
- Offline/private deployments (use local providers)

## Cohere

### Overview

Cohere provides enterprise-grade language models with native RAG support, making it ideal for document-based applications.

**Key Features:**
- 🔍 Native RAG and retrieval support
- 🌍 Strong multilingual capabilities (100+ languages)
- 📊 Built-in reranking for search results
- 💼 Enterprise-focused with SOC2 compliance

### Setup

```elixir
# Set API key
export COHERE_API_KEY="..."

# Or via Keyring
Jido.AI.Keyring.set(:cohere, "...")
```

### Available Models

```elixir
# List Cohere models
{:ok, models} = Jido.AI.Model.Registry.discover_models(provider: :cohere)

# Popular models:
# - cohere:command-r-plus (best quality, RAG-optimized)
# - cohere:command-r (balanced)
# - cohere:command (fast)
# - cohere:command-light (fastest)
```

### Usage Examples

#### Basic Chat

```elixir
# Standard chat completion
{:ok, response} = Jido.AI.chat(
  "cohere:command-r-plus",
  "Explain quantum computing"
)

# With streaming
{:ok, stream} = Jido.AI.chat(
  "cohere:command-r",
  "Tell me about machine learning",
  stream: true
)
```

#### RAG Integration

```elixir
# Use Cohere's native RAG support
alias Jido.AI.Features.RAG

# Prepare documents
documents = [
  %{content: "Paris is the capital of France...", title: "Geography"},
  %{content: "The Eiffel Tower was built in 1889...", title: "History"},
  %{content: "French cuisine is renowned worldwide...", title: "Culture"}
]

# Build RAG options for Cohere
{:ok, opts} = RAG.build_rag_options(documents, %{}, :cohere)

# Query with document context
{:ok, response} = Jido.AI.chat(
  "cohere:command-r-plus",
  "What is Paris known for?",
  opts
)

# Response includes citations to source documents
IO.puts response.content
```

#### Embeddings

```elixir
# Generate embeddings for semantic search
{:ok, embeddings} = Jido.AI.embeddings(
  "cohere:embed-english-v3.0",
  "Text to embed"
)

# Batch embeddings
texts = ["text 1", "text 2", "text 3"]
{:ok, batch_embeddings} = Jido.AI.embeddings(
  "cohere:embed-english-v3.0",
  texts
)
```

#### Reranking

```elixir
# Rerank search results for better relevance
query = "best practices for Elixir"
documents = [
  "Elixir pattern matching is powerful...",
  "GenServers handle state management...",
  "Python is a popular language..."
]

{:ok, reranked} = Jido.AI.rerank(
  "cohere:rerank-english-v2.0",
  query,
  documents
)

# Results sorted by relevance
Enum.each(reranked, fn doc ->
  IO.puts "Score: #{doc.relevance_score} - #{doc.text}"
end)
```

### Rate Limits

| Tier | RPM | TPM | Notes |
|------|-----|-----|-------|
| Trial | 100 | 100,000 | Limited features |
| Production | 10,000 | 10,000,000 | Full features |

## Perplexity

### Overview

Perplexity combines LLMs with real-time web search, providing up-to-date information with citations.

**Key Features:**
- 🔍 Real-time web search integration
- 📚 Automatic citation generation
- 🎯 Research-optimized models
- ⚡ Fast inference

### Setup

```elixir
# Set API key
export PERPLEXITY_API_KEY="pplx-..."

# Or via Keyring
Jido.AI.Keyring.set(:perplexity, "pplx-...")
```

### Available Models

```elixir
# List Perplexity models
{:ok, models} = Jido.AI.Model.Registry.discover_models(provider: :perplexity)

# Available models:
# - perplexity:llama-3.1-sonar-large-128k-online (search-enabled)
# - perplexity:llama-3.1-sonar-small-128k-online (faster)
# - perplexity:llama-3.1-sonar-large-128k-chat (offline)
```

### Usage Examples

#### Search-Augmented Queries

```elixir
# Query with real-time search
{:ok, response} = Jido.AI.chat(
  "perplexity:llama-3.1-sonar-large-128k-online",
  "What are the latest developments in Elixir 1.18?"
)

# Response includes current information with citations
IO.puts response.content
# May include citations: [1], [2], etc.
```

#### Research Queries

```elixir
# Complex research query
{:ok, response} = Jido.AI.chat(
  "perplexity:llama-3.1-sonar-large-128k-online",
  "Compare the performance characteristics of different BEAM languages",
  max_tokens: 1000
)
```

#### Offline Mode (No Search)

```elixir
# Use chat models without search for standard queries
{:ok, response} = Jido.AI.chat(
  "perplexity:llama-3.1-sonar-large-128k-chat",
  "Explain functional programming concepts"
)
```

### Rate Limits

| Tier | RPM | Notes |
|------|-----|-------|
| Free | 20 | Search-enabled |
| Standard | 5,000 | All features |

## Replicate

### Overview

Replicate provides access to 1000+ community-deployed models, from stable diffusion to specialized LLMs.

**Key Features:**
- 🎨 Huge model variety (1000+ models)
- 🚀 Easy custom model deployment
- 💰 Pay-per-inference pricing
- 🔬 Latest research models

### Setup

```elixir
# Set API key
export REPLICATE_API_KEY="r8_..."

# Or via Keyring
Jido.AI.Keyring.set(:replicate, "r8_...")
```

### Available Models

```elixir
# List popular Replicate models
{:ok, models} = Jido.AI.Model.Registry.discover_models(provider: :replicate)

# Popular models:
# - replicate:meta/llama-2-70b-chat
# - replicate:mistralai/mixtral-8x7b-instruct-v0.1
# - replicate:stability-ai/stable-diffusion (image generation)
```

### Usage Examples

#### Chat with Community Models

```elixir
# Use any community model
{:ok, response} = Jido.AI.chat(
  "replicate:meta/llama-2-70b-chat",
  "Hello, how are you?"
)

# Try experimental models
{:ok, response} = Jido.AI.chat(
  "replicate:username/custom-model",
  "Custom task"
)
```

#### Image Generation

```elixir
# Generate images with Stable Diffusion
{:ok, result} = Jido.AI.generate_image(
  "replicate:stability-ai/stable-diffusion",
  "A serene mountain landscape at sunset",
  width: 1024,
  height: 768
)

# Result contains image URL
IO.puts "Generated: #{result.image_url}"
```

#### Custom Model Deployment

```elixir
# Deploy your own model
# 1. Push model to Replicate via CLI or API
# 2. Use it immediately

{:ok, response} = Jido.AI.chat(
  "replicate:my-username/my-fine-tuned-model",
  "Task specific to my domain"
)
```

### Rate Limits

Pay-per-inference pricing - no rate limits, but costs scale with usage.

## AI21 Labs

### Overview

AI21 Labs develops Jurassic models with strong multilingual capabilities and enterprise features.

**Key Features:**
- 🌍 Strong multilingual support
- 📝 Long-form content generation
- 🎯 Task-specific APIs (summarization, paraphrasing)
- 💼 Enterprise-grade

### Setup

```elixir
# Set API key
export AI21_API_KEY="..."

# Or via Keyring
Jido.AI.Keyring.set(:ai21, "...")
```

### Available Models

```elixir
# List AI21 models
{:ok, models} = Jido.AI.Model.Registry.discover_models(provider: :ai21)

# Available models:
# - ai21:jamba-1.5-large
# - ai21:jamba-1.5-mini
# - ai21:j2-ultra (legacy)
```

### Usage Examples

#### Basic Chat

```elixir
# Standard completion
{:ok, response} = Jido.AI.chat(
  "ai21:jamba-1.5-large",
  "Write a product description for a new smartphone"
)
```

#### Multilingual Content

```elixir
# Generate content in different languages
{:ok, response} = Jido.AI.chat(
  "ai21:jamba-1.5-large",
  "Écrivez une description de produit pour un nouveau smartphone",
  temperature: 0.7
)
```

#### Long-Form Generation

```elixir
# Generate longer content
{:ok, response} = Jido.AI.chat(
  "ai21:jamba-1.5-large",
  "Write a comprehensive guide to getting started with Elixir",
  max_tokens: 2000
)
```

### Rate Limits

| Tier | RPM | Notes |
|------|-----|-------|
| Free | 300 | Trial credits |
| Pro | Custom | Contact sales |

## Feature Comparison

### RAG Support

| Provider | Native RAG | Document Handling | Citations | Reranking |
|----------|-----------|-------------------|-----------|-----------|
| Cohere | ✅ Native | ✅ Excellent | ✅ Yes | ✅ Yes |
| Perplexity | ✅ Search | 🔍 Web search | ✅ Yes | ❌ No |
| Replicate | ❌ No | Varies | ❌ No | ❌ No |
| AI21 Labs | ❌ No | ⚠️ Basic | ❌ No | ❌ No |

### Use Case Matrix

| Provider | Best For | Avoid For |
|----------|----------|-----------|
| Cohere | Enterprise RAG, document Q&A | Image generation, voice |
| Perplexity | Research, fact-checking | Private/offline use |
| Replicate | Experimentation, custom models | Production reliability |
| AI21 Labs | Multilingual content | Maximum speed |

## Best Practices

### 1. Choose the Right Provider

```elixir
# For RAG applications
defmodule MyApp.DocumentQA do
  @provider "cohere:command-r-plus"

  def ask(question, documents) do
    alias Jido.AI.Features.RAG
    {:ok, opts} = RAG.build_rag_options(documents, %{}, :cohere)
    Jido.AI.chat(@provider, question, opts)
  end
end

# For research queries
defmodule MyApp.Research do
  @provider "perplexity:llama-3.1-sonar-large-128k-online"

  def research(query) do
    Jido.AI.chat(@provider, query, max_tokens: 1000)
  end
end
```

### 2. Implement RAG Properly

```elixir
# Efficient RAG implementation with Cohere
defmodule MyApp.KnowledgeBase do
  alias Jido.AI.Features.RAG

  def query(question, documents) do
    # 1. Generate embeddings for documents (one-time)
    embedded_docs = Enum.map(documents, fn doc ->
      {:ok, embedding} = Jido.AI.embeddings(
        "cohere:embed-english-v3.0",
        doc.content
      )
      Map.put(doc, :embedding, embedding)
    end)

    # 2. Build RAG context
    {:ok, opts} = RAG.build_rag_options(embedded_docs, %{}, :cohere)

    # 3. Query with context
    Jido.AI.chat("cohere:command-r-plus", question, opts)
  end
end
```

### 3. Handle Citations

```elixir
# Parse citations from Perplexity/Cohere responses
defmodule MyApp.Citations do
  def extract_citations(response) do
    # Response may include citation markers [1], [2], etc.
    regex = ~r/\[(\d+)\]/

    citations = Regex.scan(regex, response.content)
    |> Enum.map(fn [_, num] -> String.to_integer(num) end)
    |> Enum.uniq()

    {response.content, citations}
  end

  def format_with_sources(content, citations, sources) do
    """
    #{content}

    Sources:
    #{Enum.map(citations, fn idx -> "#{idx}. #{Enum.at(sources, idx - 1)}" end) |> Enum.join("\n")}
    """
  end
end
```

### 4. Cost Optimization

```elixir
# Use appropriate model size for task
defmodule MyApp.CostOptimized do
  def chat(prompt, complexity: :simple) do
    # Use smaller model for simple tasks
    Jido.AI.chat("cohere:command-light", prompt)
  end

  def chat(prompt, complexity: :complex) do
    # Use larger model for complex tasks
    Jido.AI.chat("cohere:command-r-plus", prompt)
  end

  def chat(prompt, complexity: :rag) do
    # Use RAG-optimized model
    Jido.AI.chat("cohere:command-r-plus", prompt)
  end
end
```

### 5. Fallback Strategies

```elixir
# Implement fallback for specialized features
defmodule MyApp.SmartFallback do
  def rag_query(question, documents) do
    case try_cohere_rag(question, documents) do
      {:ok, response} -> {:ok, response}
      {:error, _} -> fallback_to_standard(question, documents)
    end
  end

  defp try_cohere_rag(question, documents) do
    alias Jido.AI.Features.RAG
    {:ok, opts} = RAG.build_rag_options(documents, %{}, :cohere)
    Jido.AI.chat("cohere:command-r-plus", question, opts)
  end

  defp fallback_to_standard(question, documents) do
    # Build context manually
    context = Enum.map_join(documents, "\n\n", & &1.content)
    prompt = "Context: #{context}\n\nQuestion: #{question}"
    Jido.AI.chat("openai:gpt-4", prompt)
  end
end
```

## Troubleshooting

### RAG Not Working

```elixir
# Verify feature support
alias Jido.AI.Features

model = Jido.AI.Model.from("cohere:command-r-plus")
if Features.supports?(model, :rag) do
  # RAG supported
else
  # Use alternative approach
end
```

### Citation Parsing Issues

```elixir
# Robust citation extraction
defmodule MyApp.CitationParser do
  def parse(response) do
    case extract_citations(response.content) do
      {:ok, citations} -> citations
      {:error, _} -> []  # Graceful degradation
    end
  end

  defp extract_citations(content) do
    # Handle different citation formats
    patterns = [
      ~r/\[(\d+)\]/,      # [1]
      ~r/\((\d+)\)/,      # (1)
      ~r/\^(\d+)/         # ^1
    ]

    citations = Enum.flat_map(patterns, fn pattern ->
      Regex.scan(pattern, content)
      |> Enum.map(fn [_, num] -> String.to_integer(num) end)
    end)
    |> Enum.uniq()
    |> Enum.sort()

    {:ok, citations}
  end
end
```

### Rate Limit Management

```elixir
# Implement intelligent rate limiting
defmodule MyApp.RateLimiter do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def call_with_limit(provider, prompt) do
    GenServer.call(__MODULE__, {:check_limit, provider})

    case Jido.AI.chat(provider, prompt) do
      {:ok, response} -> {:ok, response}
      {:error, %{status: 429}} ->
        # Rate limited - wait and retry
        :timer.sleep(1000)
        call_with_limit(provider, prompt)
      error -> error
    end
  end
end
```

## Next Steps

- [Provider Matrix](provider-matrix.md) - Compare all providers
- [High-Performance Providers](high-performance.md) - Speed optimization
- [Feature Guides](../features/) - Deep-dive into RAG, code execution, etc.
- [Migration Guide](../migration/from-legacy-providers.md) - Upgrade existing code
