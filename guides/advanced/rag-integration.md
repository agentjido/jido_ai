# RAG Integration

Retrieval-Augmented Generation (RAG) enables AI models to generate responses enhanced with external documents, providing grounded answers with citations.

## Overview

RAG combines the power of large language models with your own documents, enabling:
- **Grounded Responses**: Answers based on your specific documents
- **Citations**: Track which documents influenced the response
- **Up-to-date Information**: Use current documents without retraining
- **Domain Expertise**: Inject specialized knowledge

## Supported Providers

| Provider | Support Type | Citations | Best For |
|----------|-------------|-----------|----------|
| **Cohere** | Native RAG | ✅ Yes | Document Q&A, knowledge bases |
| **Google** | Grounding | ✅ Yes | Search augmentation, fact-checking |
| **Anthropic** | Extended Thinking | ⚠️ Manual | Long-form analysis |

## Quick Start

```elixir
alias Jido.AI.Features.RAG

# 1. Prepare your documents
documents = [
  %{content: "Elixir is a functional programming language...", title: "Elixir Intro"},
  %{content: "OTP provides tools for building fault-tolerant systems...", title: "OTP Guide"}
]

# 2. Build RAG options for your provider
{:ok, opts} = RAG.build_rag_options(documents, %{}, :cohere)

# 3. Query with document context
{:ok, response} = Jido.AI.chat(
  "cohere:command-r-plus",
  "What is Elixir and why is it fault-tolerant?",
  opts
)

# 4. Extract citations
{:ok, citations} = RAG.extract_citations(response.raw, :cohere)
```

## Document Format

Documents must be maps with at least a `:content` field:

```elixir
%{
  content: "Document text content...",  # Required
  title: "Document Title",              # Optional but recommended
  url: "https://source.com/doc",        # Optional
  metadata: %{                          # Optional
    author: "John Doe",
    date: "2024-01-01",
    category: "technical"
  }
}
```

**Limits:**
- Maximum 100 documents per request
- Maximum 500KB per document
- Minimum 1 character content

## Provider-Specific Usage

### Cohere (Native RAG)

Cohere provides the best RAG experience with Command-R models optimized for retrieval.

```elixir
# Prepare documents
documents = [
  %{
    content: "Elixir uses lightweight processes called actors...",
    title: "Concurrency in Elixir",
    url: "https://elixir-lang.org/getting-started/processes.html"
  },
  %{
    content: "GenServers handle state management...",
    title: "GenServer Guide"
  }
]

# Build options
{:ok, opts} = RAG.build_rag_options(documents, %{temperature: 0.3}, :cohere)

# Query
{:ok, response} = Jido.AI.chat(
  "cohere:command-r-plus",
  "How does Elixir handle concurrency?",
  opts
)

# Extract citations
{:ok, citations} = RAG.extract_citations(response.raw, :cohere)

Enum.each(citations, fn citation ->
  IO.puts """
  Citation:
    Text: #{citation.text}
    Document: #{citation.document_index}
    Position: #{citation.start}-#{citation.end}
  """
end)
```

### Google (Grounding)

Google provides grounding with inline data or Google Search integration.

```elixir
# Inline document grounding
documents = [
  %{content: "Elixir documentation content...", metadata: %{source: "docs"}},
  %{content: "Blog post about Elixir patterns...", metadata: %{source: "blog"}}
]

{:ok, opts} = RAG.build_rag_options(documents, %{}, :google)

{:ok, response} = Jido.AI.chat(
  "vertex:gemini-1.5-pro",
  "Summarize best practices for Elixir",
  opts
)

# Check grounding metadata
if response.raw["grounding_metadata"] do
  {:ok, citations} = RAG.extract_citations(response.raw, :google)
  IO.inspect citations, label: "Grounding Sources"
end
```

### Anthropic (Extended Thinking)

Anthropic doesn't have native RAG, but documents can be injected into the system prompt.

```elixir
documents = [
  %{content: "Technical specification document...", title: "Spec v1.0"},
  %{content: "Implementation guide...", title: "Implementation"}
]

{:ok, opts} = RAG.build_rag_options(
  documents,
  %{system: "You are a technical analyst."},
  :anthropic
)

{:ok, response} = Jido.AI.chat(
  "anthropic:claude-3-sonnet",
  "Analyze the technical specifications and suggest improvements",
  opts
)

# Anthropic returns references in text like [1], [2]
# Manual parsing needed for citation extraction
```

## Advanced Patterns

### 1. Semantic Search with RAG

Combine embeddings for semantic search before RAG:

```elixir
defmodule MyApp.SemanticRAG do
  alias Jido.AI.Features.RAG

  def semantic_query(query, document_pool) do
    # 1. Generate query embedding
    {:ok, query_embedding} = Jido.AI.embeddings(
      "cohere:embed-english-v3.0",
      query
    )

    # 2. Generate embeddings for all documents
    doc_embeddings = Enum.map(document_pool, fn doc ->
      {:ok, embedding} = Jido.AI.embeddings(
        "cohere:embed-english-v3.0",
        doc.content
      )
      {doc, embedding}
    end)

    # 3. Calculate similarity and rank
    ranked_docs = doc_embeddings
    |> Enum.map(fn {doc, emb} ->
      similarity = cosine_similarity(query_embedding, emb)
      {doc, similarity}
    end)
    |> Enum.sort_by(fn {_doc, sim} -> sim end, :desc)
    |> Enum.take(5)  # Top 5 most relevant
    |> Enum.map(fn {doc, _sim} -> doc end)

    # 4. Use RAG with ranked documents
    {:ok, opts} = RAG.build_rag_options(ranked_docs, %{}, :cohere)

    Jido.AI.chat("cohere:command-r-plus", query, opts)
  end

  defp cosine_similarity(vec1, vec2) do
    # Implement cosine similarity calculation
    dot_product = Enum.zip(vec1, vec2)
    |> Enum.map(fn {a, b} -> a * b end)
    |> Enum.sum()

    magnitude1 = :math.sqrt(Enum.map(vec1, &(&1 * &1)) |> Enum.sum())
    magnitude2 = :math.sqrt(Enum.map(vec2, &(&1 * &1)) |> Enum.sum())

    dot_product / (magnitude1 * magnitude2)
  end
end
```

### 2. Dynamic Document Loading

Load documents based on query classification:

```elixir
defmodule MyApp.DynamicRAG do
  def query_with_context(query) do
    # Classify query to determine relevant documents
    category = classify_query(query)

    # Load relevant documents
    documents = load_documents_for_category(category)

    # Perform RAG query
    {:ok, opts} = RAG.build_rag_options(documents, %{}, :cohere)
    Jido.AI.chat("cohere:command-r-plus", query, opts)
  end

  defp classify_query(query) do
    # Use a fast model to classify the query
    {:ok, response} = Jido.AI.chat(
      "groq:llama-3.1-8b-instant",
      "Classify this query into one category (technical/business/support): #{query}",
      max_tokens: 10
    )

    String.downcase(response.content) |> String.trim()
  end

  defp load_documents_for_category(category) do
    # Load from database, file system, or API
    case category do
      "technical" -> load_technical_docs()
      "business" -> load_business_docs()
      "support" -> load_support_docs()
      _ -> load_default_docs()
    end
  end
end
```

### 3. Multi-Source RAG

Combine documents from multiple sources:

```elixir
defmodule MyApp.MultiSourceRAG do
  def query_multi_source(query, sources) do
    # Gather documents from multiple sources
    all_documents = Enum.flat_map(sources, fn source ->
      case source.type do
        :database -> fetch_from_database(source.config, query)
        :api -> fetch_from_api(source.endpoint, query)
        :file -> load_from_files(source.path, query)
        :vector_db -> search_vector_db(source.client, query)
      end
    end)

    # Deduplicate and limit
    unique_docs = Enum.uniq_by(all_documents, & &1.content)
    |> Enum.take(50)  # Stay within limits

    # Perform RAG
    {:ok, opts} = RAG.build_rag_options(unique_docs, %{}, :cohere)
    Jido.AI.chat("cohere:command-r-plus", query, opts)
  end

  defp fetch_from_database(config, _query) do
    # Query database for relevant documents
    []
  end

  defp fetch_from_api(endpoint, _query) do
    # Fetch from external API
    []
  end

  defp load_from_files(path, _query) do
    # Load and parse files
    []
  end

  defp search_vector_db(client, query) do
    # Search vector database
    []
  end
end
```

### 4. Citation Tracking

Track and present citations to users:

```elixir
defmodule MyApp.CitationTracker do
  def query_with_citations(query, documents) do
    {:ok, opts} = RAG.build_rag_options(documents, %{}, :cohere)

    case Jido.AI.chat("cohere:command-r-plus", query, opts) do
      {:ok, response} ->
        {:ok, citations} = RAG.extract_citations(response.raw, :cohere)

        # Format response with citations
        formatted = format_response_with_citations(
          response.content,
          citations,
          documents
        )

        {:ok, formatted}

      error -> error
    end
  end

  defp format_response_with_citations(content, citations, documents) do
    # Add citation numbers to content
    cited_content = add_citation_markers(content, citations)

    # Build citation list
    citation_list = Enum.map(citations, fn citation ->
      doc = Enum.at(documents, citation.document_index)
      """
      [#{citation.document_index + 1}] #{doc.title}
      #{if doc.url, do: "Source: #{doc.url}", else: ""}
      Excerpt: "#{citation.text}"
      """
    end)
    |> Enum.join("\n\n")

    %{
      content: cited_content,
      citations: citation_list,
      raw_citations: citations
    }
  end

  defp add_citation_markers(content, citations) do
    # Insert citation markers [1], [2], etc. in content
    # Implementation depends on your citation style
    content
  end
end
```

### 5. RAG with Reranking

Use Cohere's reranking for better relevance:

```elixir
defmodule MyApp.RerankedRAG do
  def query_with_reranking(query, document_pool) do
    # 1. Get all candidate documents
    candidates = document_pool
    |> Enum.map(& &1.content)

    # 2. Rerank documents by relevance
    {:ok, reranked} = Jido.AI.rerank(
      "cohere:rerank-english-v2.0",
      query,
      candidates
    )

    # 3. Take top N documents
    top_docs = reranked
    |> Enum.take(10)
    |> Enum.map(fn ranked ->
      # Get original document
      Enum.at(document_pool, ranked.index)
    end)

    # 4. Perform RAG with reranked documents
    {:ok, opts} = RAG.build_rag_options(top_docs, %{}, :cohere)
    Jido.AI.chat("cohere:command-r-plus", query, opts)
  end
end
```

## Best Practices

### 1. Document Preparation

```elixir
# ✅ Good: Clean, focused documents
documents = [
  %{
    content: "Clean, focused content about one topic",
    title: "Clear Title",
    url: "https://source.com"
  }
]

# ❌ Bad: Huge, unfocused documents
documents = [
  %{
    content: File.read!("entire_book.txt"),  # Too large
    title: "",  # No title
  }
]
```

### 2. Chunk Long Documents

```elixir
defmodule MyApp.DocumentChunker do
  @chunk_size 1000  # characters

  def chunk_documents(documents) do
    Enum.flat_map(documents, fn doc ->
      doc.content
      |> chunk_text(@chunk_size)
      |> Enum.with_index()
      |> Enum.map(fn {chunk, idx} ->
        %{
          content: chunk,
          title: "#{doc.title} (Part #{idx + 1})",
          url: doc.url,
          metadata: Map.merge(doc.metadata || %{}, %{chunk_index: idx})
        }
      end)
    end)
  end

  defp chunk_text(text, size) do
    # Simple chunking - improve with sentence boundaries
    text
    |> String.graphemes()
    |> Enum.chunk_every(size)
    |> Enum.map(&Enum.join/1)
  end
end
```

### 3. Cache Embeddings

```elixir
defmodule MyApp.EmbeddingCache do
  use GenServer

  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def get_or_compute(text, model) do
    key = cache_key(text, model)

    case GenServer.call(__MODULE__, {:get, key}) do
      {:ok, cached} ->
        {:ok, cached}
      :miss ->
        {:ok, embedding} = Jido.AI.embeddings(model, text)
        GenServer.cast(__MODULE__, {:put, key, embedding})
        {:ok, embedding}
    end
  end

  defp cache_key(text, model) do
    :crypto.hash(:sha256, "#{model}:#{text}") |> Base.encode16()
  end

  # GenServer callbacks...
  def init(_), do: {:ok, %{}}
  def handle_call({:get, key}, _from, state) do
    case Map.get(state, key) do
      nil -> {:reply, :miss, state}
      value -> {:reply, {:ok, value}, state}
    end
  end
  def handle_cast({:put, key, value}, state) do
    {:noreply, Map.put(state, key, value)}
  end
end
```

### 4. Handle Provider Fallback

```elixir
defmodule MyApp.RobustRAG do
  def query(query, documents) do
    providers = [
      {:cohere, "cohere:command-r-plus"},
      {:google, "vertex:gemini-1.5-pro"},
      {:anthropic, "anthropic:claude-3-sonnet"}
    ]

    Enum.reduce_while(providers, {:error, :all_failed}, fn {provider, model}, _acc ->
      case try_rag_query(query, documents, provider, model) do
        {:ok, response} -> {:halt, {:ok, response}}
        {:error, _} -> {:cont, {:error, :all_failed}}
      end
    end)
  end

  defp try_rag_query(query, documents, provider, model) do
    with {:ok, opts} <- RAG.build_rag_options(documents, %{}, provider),
         {:ok, response} <- Jido.AI.chat(model, query, opts) do
      {:ok, response}
    end
  end
end
```

## Troubleshooting

### Document Validation Errors

```elixir
# Error: Document missing required :content field
# Solution: Ensure all documents have :content key

# ❌ Wrong
%{"text" => "content"}

# ✅ Correct
%{content: "content"}
```

### Document Too Large

```elixir
# Error: Document content too large
# Solution: Chunk documents before sending

documents = MyApp.DocumentChunker.chunk_documents(large_documents)
```

### No Citations Returned

```elixir
# Check if provider supports citations
alias Jido.AI.Features.RAG

model = Jido.AI.Model.from("groq:llama-3.1-70b")

if RAG.supports?(model) do
  # RAG supported
else
  # Use different provider
  IO.puts "This provider doesn't support native RAG"
end
```

### Rate Limiting

```elixir
# Break large document sets into batches
defmodule MyApp.BatchedRAG do
  def query_large_dataset(query, documents) do
    documents
    |> Enum.chunk_every(50)  # Process 50 docs at a time
    |> Enum.reduce_while({:ok, []}, fn batch, {:ok, acc} ->
      case query_batch(query, batch) do
        {:ok, response} ->
          {:cont, {:ok, [response | acc]}}
        {:error, %{status: 429}} ->
          :timer.sleep(1000)  # Wait on rate limit
          {:cont, {:ok, acc}}
        error ->
          {:halt, error}
      end
    end)
  end

  defp query_batch(query, documents) do
    {:ok, opts} = RAG.build_rag_options(documents, %{}, :cohere)
    Jido.AI.chat("cohere:command-r-plus", query, opts)
  end
end
```

## Performance Tips

1. **Limit Documents**: Use top 10-20 most relevant documents
2. **Cache Embeddings**: Avoid recomputing embeddings
3. **Chunk Wisely**: Keep chunks 500-1500 characters
4. **Use Semantic Search**: Pre-filter with embeddings
5. **Batch Queries**: Group similar queries together
6. **Monitor Costs**: RAG can increase token usage

## Next Steps

- [Code Execution](code-execution.md) - Enable code interpretation
- [Plugins](plugins.md) - Integrate external tools
- [Fine-Tuning](fine-tuning.md) - Custom models
- [Provider Matrix](../providers/provider-matrix.md) - Compare providers
