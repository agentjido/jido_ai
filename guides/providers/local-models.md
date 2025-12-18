# Local and Self-Hosted Providers

Local providers enable running AI models on your own infrastructure, providing complete privacy, offline capability, and zero API costs.

## Supported Providers

- **Ollama** - Easy local model management
- **LMStudio** - User-friendly desktop application
- **Llama.cpp** - High-performance inference engine
- **vLLM** - Production-grade serving with GPU optimization

## When to Use Local Providers

**Best for:**
- Privacy-sensitive applications (healthcare, legal, finance)
- Offline/air-gapped environments
- Development and testing without API costs
- Complete data control and sovereignty
- Reducing latency with local inference

**Not ideal for:**
- Maximum model quality (cloud models are larger)
- Zero infrastructure management
- Instant scalability
- Accessing latest models immediately

## Ollama

### Overview

Ollama provides the easiest way to run local LLMs, with automatic model management and GPU acceleration.

**Key Features:**
- 🎯 Simplest setup (one command install)
- 📦 100+ pre-built models
- 🚀 Automatic GPU acceleration
- 🔒 Complete privacy (no data leaves machine)
- 💰 Free and open source

### Setup

```bash
# Install Ollama
curl -fsSL https://ollama.com/install.sh | sh

# Or on macOS
brew install ollama

# Start Ollama service
ollama serve
```

```elixir
# No API key needed for local Ollama
# Just ensure service is running on localhost:11434
```

### Available Models

```bash
# List available models to download
ollama list

# Popular models:
# - llama3.2:latest (Meta's latest)
# - llama3.1:70b (larger, more capable)
# - mistral:latest (fast and capable)
# - codellama:latest (code-optimized)
# - phi3:latest (small, efficient)
```

### Model Management

```bash
# Pull a model
ollama pull llama3.2

# Pull specific size
ollama pull llama3.1:70b

# Remove a model
ollama rm llama3.2

# Show model info
ollama show llama3.2
```

### Usage Examples

#### Basic Chat

```elixir
# Chat with local model
{:ok, response} = Jido.AI.chat(
  "ollama:llama3.2",
  "Explain Elixir pattern matching"
)

# Model runs entirely on your machine
IO.puts response.content
```

#### Streaming for Real-Time Responses

```elixir
# Stream responses for better UX
{:ok, stream} = Jido.AI.chat(
  "ollama:llama3.2",
  "Write a story about space exploration",
  stream: true
)

stream
|> Stream.each(fn chunk ->
  IO.write(chunk.content)
end)
|> Stream.run()
```

#### Code Generation

```elixir
# Use code-specialized models
{:ok, response} = Jido.AI.chat(
  "ollama:codellama",
  "Write a GenServer that manages a counter",
  temperature: 0.2  # Lower temperature for code
)
```

#### Custom Prompts

```elixir
# Multi-turn conversation
messages = [
  %{role: "system", content: "You are an Elixir expert"},
  %{role: "user", content: "What is a GenServer?"},
  %{role: "assistant", content: "A GenServer is..."},
  %{role: "user", content: "Show me an example"}
]

{:ok, response} = Jido.AI.chat(
  "ollama:llama3.2",
  messages
)
```

#### Embeddings Generation

```elixir
# Generate embeddings locally
{:ok, embeddings} = Jido.AI.embeddings(
  "ollama:nomic-embed-text",
  "Text to embed"
)

# No API costs, full privacy
```

### Performance Optimization

```bash
# Use quantized models for faster inference
ollama pull llama3.2:7b-q4_0  # 4-bit quantization

# GPU acceleration (automatic if available)
# Check GPU usage
nvidia-smi  # NVIDIA GPUs
rocm-smi   # AMD GPUs
```

```elixir
# Adjust generation parameters for speed
{:ok, response} = Jido.AI.chat(
  "ollama:llama3.2",
  prompt,
  max_tokens: 256,      # Shorter responses
  temperature: 0.7,     # Standard creativity
  num_predict: 256      # Ollama-specific limit
)
```

### Resource Requirements

| Model | Size | RAM Required | GPU VRAM | Speed |
|-------|------|--------------|----------|-------|
| phi3:latest | 2GB | 4GB | Optional | ⚡⚡⚡⚡ |
| llama3.2:latest | 4GB | 8GB | 4GB+ | ⚡⚡⚡ |
| llama3.1:70b | 40GB | 64GB | 40GB+ | ⚡⚡ |
| codellama:latest | 4GB | 8GB | 4GB+ | ⚡⚡⚡ |

## LMStudio

### Overview

LMStudio provides a user-friendly desktop interface for running local LLMs with a built-in chat UI.

**Key Features:**
- 🖥️ Beautiful desktop UI
- 📦 One-click model downloads
- 🔄 Model comparison tools
- 🚀 GPU acceleration
- 🔌 OpenAI-compatible API

### Setup

```bash
# Download from lmstudio.ai
# Install and launch application

# Enable local server in LMStudio:
# Settings → Server → Start Server (default port: 1234)
```

```elixir
# Configure endpoint (LMStudio uses OpenAI-compatible API)
# No API key needed for local instance
```

### Usage Examples

```elixir
# Chat with model loaded in LMStudio
{:ok, response} = Jido.AI.chat(
  "lmstudio:local-model",
  "What is functional programming?",
  base_url: "http://localhost:1234/v1"
)
```

### Best Practices

- Load models through LMStudio UI first
- Use GPU acceleration when available
- Monitor resource usage in LMStudio dashboard
- Save conversation history in LMStudio for debugging

## Llama.cpp

### Overview

Llama.cpp is a high-performance C++ inference engine with extensive platform support.

**Key Features:**
- ⚡ Fastest CPU inference
- 🎯 Highly optimized
- 📱 Runs on mobile devices
- 🔧 Advanced configuration options

### Setup

```bash
# Build from source
git clone https://github.com/ggerganov/llama.cpp
cd llama.cpp
make

# Or use pre-built server
./server -m models/llama-2-7b.Q4_0.gguf -c 2048
```

### Usage Examples

```elixir
# Connect to llama.cpp server
{:ok, response} = Jido.AI.chat(
  "llamacpp:model",
  "Explain concurrency",
  base_url: "http://localhost:8080"
)
```

### Performance Tuning

```bash
# CPU optimization
./server -m model.gguf -t 8 -c 2048  # 8 threads, 2048 context

# GPU acceleration (CUDA)
make LLAMA_CUBLAS=1
./server -m model.gguf -ngl 35  # Offload 35 layers to GPU

# Metal (macOS)
make LLAMA_METAL=1
./server -m model.gguf -ngl 1
```

## vLLM

### Overview

vLLM is a production-grade serving system optimized for high-throughput GPU inference.

**Key Features:**
- 🚀 Highest throughput (PagedAttention)
- 🎯 Production-ready
- 📊 Batch processing support
- 🔧 Extensive model support

### Setup

```bash
# Install vLLM
pip install vllm

# Start server
python -m vllm.entrypoints.openai.api_server \
  --model meta-llama/Llama-2-7b-chat-hf \
  --port 8000
```

### Usage Examples

```elixir
# High-throughput inference
{:ok, response} = Jido.AI.chat(
  "vllm:llama-2-7b",
  "Explain the Actor model",
  base_url: "http://localhost:8000/v1"
)

# Batch processing
prompts = ["prompt 1", "prompt 2", "prompt 3"]

tasks = Enum.map(prompts, fn prompt ->
  Task.async(fn ->
    Jido.AI.chat("vllm:llama-2-7b", prompt)
  end)
end)

results = Task.await_many(tasks)
```

### Production Configuration

```bash
# Production server with optimizations
python -m vllm.entrypoints.openai.api_server \
  --model meta-llama/Llama-2-70b-chat-hf \
  --tensor-parallel-size 4 \    # Multi-GPU
  --max-num-seqs 256 \           # Batch size
  --max-model-len 4096           # Context length
```

## Feature Comparison

| Provider | Ease of Use | Performance | GPU Required | Model Selection |
|----------|------------|-------------|--------------|-----------------|
| Ollama | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | No | 100+ models |
| LMStudio | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | No | UI-based |
| Llama.cpp | ⭐⭐ | ⭐⭐⭐⭐⭐ | No | Manual setup |
| vLLM | ⭐⭐ | ⭐⭐⭐⭐⭐ | Yes | HuggingFace |

## Use Case Matrix

| Use Case | Recommended Provider | Why |
|----------|---------------------|-----|
| Getting started | Ollama | Easiest setup |
| Desktop experimentation | LMStudio | Best UI |
| Production deployment | vLLM | Highest throughput |
| CPU-only inference | Llama.cpp | Best CPU performance |
| Mobile/edge devices | Llama.cpp | Smallest footprint |
| Privacy-critical | Any local | No data leaves machine |

## Best Practices

### 1. Model Selection

```elixir
# Choose model based on task complexity
defmodule MyApp.LocalAI do
  @simple_model "ollama:phi3"       # Fast, good for simple tasks
  @standard_model "ollama:llama3.2" # Balanced
  @complex_model "ollama:llama3.1:70b" # Best quality

  def chat(prompt, complexity: :simple) do
    Jido.AI.chat(@simple_model, prompt)
  end

  def chat(prompt, complexity: :standard) do
    Jido.AI.chat(@standard_model, prompt)
  end

  def chat(prompt, complexity: :complex) do
    Jido.AI.chat(@complex_model, prompt)
  end
end
```

### 2. Resource Management

```elixir
# Monitor and manage resources
defmodule MyApp.ResourceMonitor do
  def chat_with_monitoring(model, prompt) do
    start_time = System.monotonic_time(:millisecond)
    start_memory = :erlang.memory(:total)

    result = Jido.AI.chat(model, prompt)

    end_time = System.monotonic_time(:millisecond)
    end_memory = :erlang.memory(:total)

    metrics = %{
      latency: end_time - start_time,
      memory_used: end_memory - start_memory,
      model: model
    }

    Logger.info("Local inference metrics: #{inspect(metrics)}")

    result
  end
end
```

### 3. Caching and Optimization

```elixir
# Cache model responses for repeated queries
defmodule MyApp.LocalCache do
  use GenServer

  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def init(_), do: {:ok, %{}}

  def chat(model, prompt) do
    cache_key = :crypto.hash(:sha256, "#{model}:#{prompt}") |> Base.encode16()

    case GenServer.call(__MODULE__, {:get, cache_key}) do
      {:ok, cached} ->
        {:ok, cached}
      :miss ->
        {:ok, response} = Jido.AI.chat(model, prompt)
        GenServer.cast(__MODULE__, {:put, cache_key, response})
        {:ok, response}
    end
  end

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

### 4. Fallback to Cloud

```elixir
# Fallback to cloud when local unavailable
defmodule MyApp.HybridAI do
  @local_model "ollama:llama3.2"
  @cloud_model "openai:gpt-4"

  def chat(prompt) do
    case Jido.AI.chat(@local_model, prompt, timeout: 5_000) do
      {:ok, response} ->
        {:ok, %{response | source: :local}}
      {:error, _} ->
        # Local failed, use cloud
        case Jido.AI.chat(@cloud_model, prompt) do
          {:ok, response} -> {:ok, %{response | source: :cloud}}
          error -> error
        end
    end
  end
end
```

### 5. Development vs Production

```elixir
# Different providers for dev/prod
defmodule MyApp.Config do
  def ai_provider do
    case Application.get_env(:my_app, :env) do
      :dev -> "ollama:llama3.2"      # Free local dev
      :test -> "ollama:phi3"         # Fast for tests
      :prod -> "openai:gpt-4"        # Reliable production
    end
  end
end

# Use in application
{:ok, response} = Jido.AI.chat(
  MyApp.Config.ai_provider(),
  prompt
)
```

## Troubleshooting

### Ollama Connection Issues

```elixir
# Check if Ollama is running
case Jido.AI.chat("ollama:llama3.2", "test") do
  {:ok, _} ->
    IO.puts "Ollama is running"
  {:error, %{type: :connection_error}} ->
    IO.puts "Start Ollama: ollama serve"
  {:error, reason} ->
    IO.puts "Error: #{inspect(reason)}"
end
```

### Model Not Found

```bash
# Ensure model is pulled
ollama pull llama3.2

# List available models
ollama list
```

### Out of Memory

```elixir
# Use smaller model or quantized version
# Instead of: "ollama:llama3.1:70b"
# Use: "ollama:llama3.2"  # Smaller model
# Or: "ollama:llama3.1:70b-q4_0"  # Quantized
```

### Slow Inference

```bash
# Enable GPU acceleration for Ollama
# NVIDIA: Install CUDA toolkit
# AMD: Install ROCm
# Apple: Metal is automatic

# Verify GPU usage
nvidia-smi  # Should show ollama process

# Use smaller context window
```

```elixir
{:ok, response} = Jido.AI.chat(
  "ollama:llama3.2",
  prompt,
  max_tokens: 256,  # Shorter responses = faster
  num_ctx: 2048     # Smaller context window
)
```

## Security Considerations

### Data Privacy

```elixir
# Ensure sensitive data never leaves machine
defmodule MyApp.SecureAI do
  @local_model "ollama:llama3.2"

  def process_sensitive(data) do
    # Force local processing
    case Jido.AI.chat(@local_model, data) do
      {:ok, response} ->
        # Verify model is local
        if String.starts_with?(@local_model, "ollama:") do
          {:ok, response}
        else
          {:error, :security_violation}
        end
      error -> error
    end
  end
end
```

### Air-Gapped Environments

```bash
# Download models on internet-connected machine
ollama pull llama3.2

# Export model
ollama show llama3.2 --modelfile > llama3.2.modelfile

# Transfer to air-gapped machine and import
ollama create llama3.2 -f llama3.2.modelfile
```

## Cost Comparison

| Provider | Setup Cost | Running Cost | Scalability Cost |
|----------|-----------|--------------|------------------|
| Local (Ollama) | Hardware | Electricity | More hardware |
| Cloud (OpenAI) | $0 | Per token | Automatic |
| Hybrid | Hardware | Mixed | Flexible |

**Break-even analysis:**
- High volume (>1M tokens/day): Local is cheaper
- Low volume (<100K tokens/day): Cloud is cheaper
- Privacy requirements: Local regardless of cost

## Next Steps

- [High-Performance Providers](high-performance.md) - When you need cloud speed
- [Enterprise Providers](enterprise.md) - For compliance requirements
- [Provider Matrix](provider-matrix.md) - Compare all options
- [Migration Guide](../migration/from-legacy-providers.md) - Integrate local models
