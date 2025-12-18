# Regional Providers

Regional providers offer AI services optimized for specific geographic regions, with local compliance, language support, and data residency requirements.

## Supported Providers

- **Alibaba Cloud** - China's leading cloud AI platform
- **Zhipu AI** - Chinese AI provider with GLM models
- **Moonshot AI** - China-based provider with long-context models
- **Mistral AI** - European AI provider (France)

## When to Use Regional Providers

**Best for:**
- Regional compliance requirements
- Local language optimization
- Data sovereignty and residency
- Lower latency in specific regions
- Cost optimization (local pricing)
- Government and regulated sectors

**Not ideal for:**
- Global applications requiring consistency
- Maximum model variety
- English-only applications
- When regional compliance isn't required

## Alibaba Cloud (China)

### Overview

Alibaba Cloud provides AI services compliant with Chinese regulations, featuring Qwen (通义千问) models.

**Key Features:**
- 🇨🇳 Chinese regulatory compliance
- 🌏 Optimized for Chinese language
- 🔐 Data stays within China
- 📊 Integration with Alibaba Cloud ecosystem
- 💼 Enterprise support

### Setup

```bash
# Set credentials
export ALIBABA_CLOUD_ACCESS_KEY_ID="..."
export ALIBABA_CLOUD_ACCESS_KEY_SECRET="..."
export ALIBABA_CLOUD_REGION="cn-beijing"
```

```elixir
# Or via Keyring
Jido.AI.Keyring.set(:alibaba, %{
  access_key_id: "...",
  access_key_secret: "...",
  region: "cn-beijing"
})
```

### Available Models

```elixir
# List available models
{:ok, models} = Jido.AI.Model.Registry.discover_models(provider: :alibaba)

# Popular models:
# - alibaba:qwen-turbo (fast, cost-effective)
# - alibaba:qwen-plus (balanced)
# - alibaba:qwen-max (highest quality)
# - alibaba:qwen-vl-plus (vision-language)
```

### Usage Examples

#### Chinese Language Chat

```elixir
# Optimized for Chinese
{:ok, response} = Jido.AI.chat(
  "alibaba:qwen-plus",
  "请解释一下机器学习的基本概念"  # "Explain basic ML concepts"
)

IO.puts response.content  # Response in Chinese
```

#### Bilingual Support

```elixir
# Works with both Chinese and English
{:ok, response} = Jido.AI.chat(
  "alibaba:qwen-turbo",
  "Translate: The weather is nice today",
  system: "You are a helpful bilingual assistant"
)
```

#### Vision-Language Models

```elixir
# Use Qwen-VL for image understanding
{:ok, response} = Jido.AI.chat(
  "alibaba:qwen-vl-plus",
  "这张图片里有什么？",  # "What's in this image?"
  images: ["/path/to/image.jpg"]
)
```

### Rate Limits

| Model | QPM | TPM | Notes |
|-------|-----|-----|-------|
| qwen-turbo | 600 | 300K | Standard tier |
| qwen-plus | 300 | 150K | Standard tier |
| qwen-max | 100 | 50K | Premium tier |

### Compliance

- ✅ Chinese Cybersecurity Law
- ✅ Personal Information Protection Law (PIPL)
- ✅ Data Security Law
- ✅ Multi-Level Protection Scheme (MLPS)

## Zhipu AI (China)

### Overview

Zhipu AI provides GLM (General Language Model) series, developed by Tsinghua University's Knowledge Engineering Group.

**Key Features:**
- 🇨🇳 Chinese regulatory compliance
- 🎓 Academic research foundation
- 🌏 Strong Chinese language capabilities
- 🔬 Latest research implementations
- 💰 Competitive pricing

### Setup

```bash
# Set API key
export ZHIPU_API_KEY="..."
```

```elixir
# Or via Keyring
Jido.AI.Keyring.set(:zhipu, "...")
```

### Available Models

```elixir
# List available models
{:ok, models} = Jido.AI.Model.Registry.discover_models(provider: :zhipu)

# Popular models:
# - zhipu:glm-4 (latest, most capable)
# - zhipu:glm-4v (vision support)
# - zhipu:glm-3-turbo (fast, economical)
```

### Usage Examples

#### Chinese Text Generation

```elixir
# Natural Chinese text generation
{:ok, response} = Jido.AI.chat(
  "zhipu:glm-4",
  "写一篇关于人工智能的文章",  # "Write an article about AI"
  max_tokens: 2000
)
```

#### Code Generation

```elixir
# Code generation in Chinese context
{:ok, response} = Jido.AI.chat(
  "zhipu:glm-4",
  "用Elixir编写一个计算斐波那契数列的函数",  # "Write Fibonacci in Elixir"
  temperature: 0.2
)
```

#### Vision Understanding

```elixir
# Image analysis with Chinese responses
{:ok, response} = Jido.AI.chat(
  "zhipu:glm-4v",
  "分析这张图片的内容",  # "Analyze this image"
  images: [image_url]
)
```

### Rate Limits

| Tier | QPM | Notes |
|------|-----|-------|
| Free | 60 | Limited features |
| Standard | 300 | Full features |
| Enterprise | Custom | Dedicated support |

## Moonshot AI (China)

### Overview

Moonshot AI specializes in long-context models with support for up to 200K tokens.

**Key Features:**
- 🇨🇳 Chinese regulatory compliance
- 📏 Ultra-long context (200K tokens)
- 🌏 Chinese and English bilingual
- 🚀 Fast inference
- 💡 Cost-effective long-context processing

### Setup

```bash
# Set API key
export MOONSHOT_API_KEY="..."
```

```elixir
# Or via Keyring
Jido.AI.Keyring.set(:moonshot, "...")
```

### Available Models

```elixir
# List available models
{:ok, models} = Jido.AI.Model.Registry.discover_models(provider: :moonshot)

# Available models:
# - moonshot:moonshot-v1-8k (8K context)
# - moonshot:moonshot-v1-32k (32K context)
# - moonshot:moonshot-v1-128k (128K context)
```

### Usage Examples

#### Long Document Processing

```elixir
# Process very long documents
long_document = File.read!("very_long_document.txt")  # 100K+ tokens

{:ok, response} = Jido.AI.chat(
  "moonshot:moonshot-v1-128k",
  long_document <> "\n\n总结这篇文档的主要内容",  # "Summarize this document"
  max_tokens: 4096
)
```

#### Multi-Document Analysis

```elixir
# Analyze multiple documents in single context
documents = [
  File.read!("doc1.txt"),
  File.read!("doc2.txt"),
  File.read!("doc3.txt")
]

context = Enum.join(documents, "\n\n---\n\n")

{:ok, response} = Jido.AI.chat(
  "moonshot:moonshot-v1-128k",
  context <> "\n\n比较这些文档的异同",  # "Compare these documents"
)
```

### Rate Limits

| Model | QPM | TPM | Context |
|-------|-----|-----|---------|
| 8K | 300 | 150K | 8K |
| 32K | 100 | 50K | 32K |
| 128K | 50 | 25K | 128K |

## Mistral AI (Europe)

### Overview

Mistral AI is a European provider offering open and commercial models with European data compliance.

**Key Features:**
- 🇪🇺 European GDPR compliance
- 🔓 Open-source models available
- 🚀 High-performance inference
- 🎯 European data residency
- 💡 Transparent AI development

### Setup

```bash
# Set API key
export MISTRAL_API_KEY="..."
```

```elixir
# Or via Keyring
Jido.AI.Keyring.set(:mistral, "...")
```

### Available Models

```elixir
# List available models
{:ok, models} = Jido.AI.Model.Registry.discover_models(provider: :mistral)

# Popular models:
# - mistral:mistral-large-latest (most capable)
# - mistral:mistral-medium-latest (balanced)
# - mistral:mistral-small-latest (fast, economical)
# - mistral:codestral-latest (code-specialized)
```

### Usage Examples

#### GDPR-Compliant Chat

```elixir
# Process data with European compliance
{:ok, response} = Jido.AI.chat(
  "mistral:mistral-large-latest",
  "Analyze this customer feedback",
  region: "eu-west-1",  # Ensure European processing
  data_processing_addendum: true
)
```

#### Code Generation

```elixir
# Use Codestral for code tasks
{:ok, response} = Jido.AI.chat(
  "mistral:codestral-latest",
  "Write a REST API client in Elixir for a user service",
  temperature: 0.2
)
```

#### Multilingual European Languages

```elixir
# Strong support for European languages
languages = ["French", "German", "Spanish", "Italian"]

Enum.each(languages, fn lang ->
  {:ok, response} = Jido.AI.chat(
    "mistral:mistral-large-latest",
    "Translate 'Hello, how are you?' to #{lang}"
  )
  IO.puts "#{lang}: #{response.content}"
end)
```

### Rate Limits

| Tier | RPM | TPM | Notes |
|------|-----|-----|-------|
| Free | 60 | 20K | Limited |
| Standard | 600 | 200K | Full access |
| Enterprise | Custom | Custom | SLA included |

### Compliance

- ✅ GDPR compliant
- ✅ European data residency
- ✅ Data Processing Agreement (DPA)
- ✅ ISO 27001 certified

## Regional Comparison

### Asia-Pacific

| Provider | Region | Primary Language | Compliance | Best For |
|----------|--------|------------------|------------|----------|
| Alibaba Cloud | China | Chinese | Chinese laws | Enterprise China |
| Zhipu AI | China | Chinese | Chinese laws | Research, Education |
| Moonshot AI | China | Chinese/English | Chinese laws | Long documents |

### Europe

| Provider | Region | Languages | Compliance | Best For |
|----------|--------|-----------|------------|----------|
| Mistral AI | France/EU | European | GDPR | European enterprises |

## Best Practices

### 1. Language Detection and Routing

```elixir
# Route to appropriate regional provider based on language
defmodule MyApp.RegionalRouter do
  def chat(prompt, opts \\ []) do
    provider = detect_provider(prompt)
    Jido.AI.chat(provider, prompt, opts)
  end

  defp detect_provider(prompt) do
    cond do
      chinese?(prompt) -> "alibaba:qwen-plus"
      european_language?(prompt) -> "mistral:mistral-large-latest"
      true -> "openai:gpt-4"  # Default fallback
    end
  end

  defp chinese?(text) do
    # Simple heuristic: check for Chinese characters
    String.match?(text, ~r/[\p{Han}]/)
  end

  defp european_language?(text) do
    # Check for European language markers
    # More sophisticated detection could use language detection library
    eu_words = ["bonjour", "hallo", "ciao", "hola"]
    Enum.any?(eu_words, &String.contains?(String.downcase(text), &1))
  end
end
```

### 2. Data Residency Compliance

```elixir
# Ensure data stays in required region
defmodule MyApp.DataResidency do
  @region_mapping %{
    china: "alibaba:qwen-plus",
    europe: "mistral:mistral-large-latest",
    us: "openai:gpt-4"
  }

  def compliant_chat(prompt, user_region, opts \\ []) do
    provider = Map.get(@region_mapping, user_region)

    unless provider do
      raise "No compliant provider for region: #{user_region}"
    end

    # Add region-specific options
    opts = Keyword.merge(opts, data_residency: user_region)

    Jido.AI.chat(provider, prompt, opts)
  end
end
```

### 3. Multilingual Applications

```elixir
# Build multilingual app with regional providers
defmodule MyApp.MultilingualChat do
  def chat(prompt, user_locale) do
    {provider, opts} = get_provider_config(user_locale)
    Jido.AI.chat(provider, prompt, opts)
  end

  defp get_provider_config(locale) do
    case locale do
      "zh-CN" ->
        {"alibaba:qwen-plus", [region: "cn-beijing"]}

      "zh-TW" ->
        {"alibaba:qwen-plus", [region: "cn-hongkong"]}

      locale when locale in ["fr-FR", "de-DE", "es-ES", "it-IT"] ->
        {"mistral:mistral-large-latest", [region: "eu-west-1"]}

      _ ->
        {"openai:gpt-4", []}
    end
  end
end
```

### 4. Cost Optimization with Regional Pricing

```elixir
# Use regional providers for cost savings
defmodule MyApp.CostOptimized do
  # Pricing per 1M tokens (approximate)
  @pricing %{
    "alibaba:qwen-turbo" => 0.50,
    "zhipu:glm-3-turbo" => 0.30,
    "openai:gpt-4" => 30.00,
    "mistral:mistral-small-latest" => 2.00
  }

  def chat_cost_effective(prompt, acceptable_providers) do
    # Sort by price
    sorted = Enum.sort_by(acceptable_providers, &Map.get(@pricing, &1, 999))

    # Try in order of cost
    Enum.reduce_while(sorted, {:error, :all_failed}, fn provider, _acc ->
      case Jido.AI.chat(provider, prompt, timeout: 5_000) do
        {:ok, response} ->
          cost = calculate_cost(provider, response.usage)
          {:halt, {:ok, response, cost}}
        {:error, _} ->
          {:cont, {:error, :all_failed}}
      end
    end)
  end

  defp calculate_cost(provider, usage) do
    price_per_1m = Map.get(@pricing, provider, 0)
    total_tokens = usage.prompt_tokens + usage.completion_tokens
    (total_tokens / 1_000_000) * price_per_1m
  end
end
```

### 5. Fallback Across Regions

```elixir
# Implement cross-regional fallback
defmodule MyApp.GlobalFallback do
  @providers [
    # Try regional first (faster, cheaper)
    {"alibaba:qwen-plus", [region: :china, language: :chinese]},
    {"mistral:mistral-large-latest", [region: :europe, language: :multilingual]},
    # Global fallback
    {"openai:gpt-4", [region: :global, language: :multilingual]}
  ]

  def chat(prompt, opts \\ []) do
    # Try providers in order
    Enum.reduce_while(@providers, {:error, :all_failed}, fn {provider, config}, _acc ->
      case try_provider(provider, prompt, opts) do
        {:ok, response} ->
          {:halt, {:ok, Map.put(response, :provider_used, provider)}}
        {:error, reason} ->
          Logger.warning("Provider #{provider} failed: #{inspect(reason)}")
          {:cont, {:error, :all_failed}}
      end
    end)
  end

  defp try_provider(provider, prompt, opts) do
    Jido.AI.chat(provider, prompt, Keyword.merge(opts, timeout: 10_000))
  end
end
```

## Troubleshooting

### Language Detection Issues

```elixir
# Use a proper language detection library
# Add to mix.exs: {:paasaa, "~> 0.6"}

defmodule MyApp.LanguageDetector do
  def detect_and_route(text) do
    case Paasaa.detect(text) do
      "zh" -> "alibaba:qwen-plus"
      "fr" -> "mistral:mistral-large-latest"
      "de" -> "mistral:mistral-large-latest"
      _ -> "openai:gpt-4"
    end
  end
end
```

### Regional Connectivity Issues

```elixir
# Handle regional network issues
defmodule MyApp.RegionalHealth do
  def health_check(provider) do
    case Jido.AI.chat(provider, "test", timeout: 3_000) do
      {:ok, _} -> {:healthy, provider}
      {:error, %{type: :timeout}} -> {:unhealthy, :timeout}
      {:error, %{type: :connection_error}} -> {:unhealthy, :connection}
      {:error, reason} -> {:unhealthy, reason}
    end
  end

  def get_healthy_provider(providers) do
    Enum.find_value(providers, fn provider ->
      case health_check(provider) do
        {:healthy, provider} -> provider
        {:unhealthy, _} -> nil
      end
    end)
  end
end
```

### Compliance Verification

```elixir
# Verify compliance requirements are met
defmodule MyApp.ComplianceCheck do
  @compliance_matrix %{
    "alibaba:qwen-plus" => [:chinese_law, :pipl, :data_security_law],
    "mistral:mistral-large-latest" => [:gdpr, :eu_data_residency],
    "openai:gpt-4" => []  # Check specific deployment
  }

  def verify_compliance(provider, required_compliance) do
    supported = Map.get(@compliance_matrix, provider, [])

    if Enum.all?(required_compliance, &(&1 in supported)) do
      :ok
    else
      missing = required_compliance -- supported
      {:error, {:missing_compliance, missing}}
    end
  end

  def chat_with_compliance(prompt, required_compliance) do
    provider = find_compliant_provider(required_compliance)

    case provider do
      nil ->
        {:error, :no_compliant_provider}
      provider ->
        Jido.AI.chat(provider, prompt)
    end
  end

  defp find_compliant_provider(required_compliance) do
    Enum.find_value(@compliance_matrix, fn {provider, supported} ->
      if Enum.all?(required_compliance, &(&1 in supported)), do: provider
    end)
  end
end
```

## Next Steps

- [Provider Matrix](provider-matrix.md) - Compare all providers
- [Enterprise Providers](enterprise.md) - For additional compliance
- [Migration Guide](../migration/from-legacy-providers.md) - Integrate regional providers
- [Advanced Features](../features/) - Use provider-specific capabilities
