# Enterprise Providers

Enterprise providers offer production-grade features including compliance certifications, SLAs, advanced security, and dedicated support for mission-critical applications.

## Supported Providers

- **Azure OpenAI** - Microsoft's enterprise AI platform
- **Amazon Bedrock** - AWS managed AI service
- **Google Vertex AI** - Google Cloud's AI platform
- **IBM watsonx.ai** - IBM's enterprise AI platform

## When to Use Enterprise Providers

**Best for:**
- Regulated industries (healthcare, finance, government)
- Compliance requirements (HIPAA, SOC2, GDPR)
- Production SLAs (99.9%+ uptime)
- Enterprise authentication (SSO, RBAC)
- Multi-tenant applications
- Audit and governance requirements

**Not ideal for:**
- Personal projects (cost overhead)
- Rapid experimentation (setup complexity)
- Maximum speed (use high-performance providers)
- Latest models (cloud providers have newer)

## Azure OpenAI

### Overview

Azure OpenAI provides OpenAI models through Microsoft's enterprise cloud platform with enhanced security and compliance.

**Key Features:**
- ✅ SOC2, HIPAA, GDPR compliant
- 🔐 Microsoft Entra ID (Azure AD) integration
- 📊 99.9% SLA
- 🌍 Regional data residency
- 🔒 Customer-managed keys
- 📈 Advanced monitoring and logging

### Setup

```bash
# Set credentials
export AZURE_OPENAI_API_KEY="..."
export AZURE_OPENAI_ENDPOINT="https://your-resource.openai.azure.com"
export AZURE_OPENAI_DEPLOYMENT="your-deployment-name"
```

```elixir
# Or via Keyring
Jido.AI.Keyring.set(:azure_openai, %{
  api_key: "...",
  endpoint: "https://your-resource.openai.azure.com",
  deployment: "gpt-4"
})
```

### Available Models

Models must be deployed through Azure Portal before use:

```elixir
# List your deployed models (requires Azure credentials)
{:ok, models} = Jido.AI.Model.Registry.discover_models(provider: :azure_openai)

# Common deployments:
# - azure:gpt-4 (GPT-4)
# - azure:gpt-4-turbo (GPT-4 Turbo)
# - azure:gpt-35-turbo (GPT-3.5 Turbo)
# - azure:text-embedding-ada-002 (Embeddings)
```

### Usage Examples

#### Basic Chat

```elixir
# Chat with Azure-deployed model
{:ok, response} = Jido.AI.chat(
  "azure:gpt-4",
  "Explain HIPAA compliance requirements",
  deployment: "my-gpt4-deployment"
)
```

#### With Entra ID Authentication

```elixir
# Use Microsoft Entra ID (Azure AD) for authentication
# Configure managed identity or service principal

{:ok, response} = Jido.AI.chat(
  "azure:gpt-4",
  prompt,
  auth_type: :entra_id,
  tenant_id: "your-tenant-id",
  client_id: "your-client-id",
  client_secret: "your-client-secret"
)
```

#### Regional Deployment

```elixir
# Use specific region for data residency
{:ok, response} = Jido.AI.chat(
  "azure:gpt-4",
  prompt,
  endpoint: "https://your-resource-eu.openai.azure.com",
  deployment: "gpt-4-eu"
)
```

#### Content Filtering

```elixir
# Azure provides built-in content filtering
{:ok, response} = Jido.AI.chat(
  "azure:gpt-4",
  prompt,
  content_filter_level: :high
)

# Check if content was filtered
if response.content_filter_results do
  IO.puts "Content filtering applied: #{inspect(response.content_filter_results)}"
end
```

### Rate Limits

| Model | TPM (Standard) | TPM (Enterprise) |
|-------|----------------|------------------|
| GPT-4 | 10K | Configurable |
| GPT-4 Turbo | 30K | Configurable |
| GPT-3.5 | 60K | Configurable |

### Pricing

Usage-based pricing (varies by region):
- GPT-4: ~$0.03-0.06 per 1K tokens (input)
- GPT-3.5: ~$0.0015-0.002 per 1K tokens (input)
- Committed use discounts available

## Amazon Bedrock

### Overview

Amazon Bedrock provides access to multiple foundation models through AWS infrastructure with enterprise-grade security.

**Key Features:**
- ✅ SOC2, HIPAA, GDPR compliant
- 🔐 AWS IAM integration
- 📊 99.9% SLA
- 🔒 VPC endpoint support
- 📈 CloudWatch integration
- 🎯 Multiple model providers (Anthropic, Meta, Cohere, etc.)

### Setup

```bash
# Set AWS credentials
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_REGION="us-east-1"
```

```elixir
# Or via Keyring
Jido.AI.Keyring.set(:bedrock, %{
  access_key_id: "...",
  secret_access_key: "...",
  region: "us-east-1"
})
```

### Available Models

```elixir
# List models available in your region
{:ok, models} = Jido.AI.Model.Registry.discover_models(provider: :bedrock)

# Popular models:
# - bedrock:anthropic.claude-3-sonnet
# - bedrock:anthropic.claude-3-haiku
# - bedrock:meta.llama3-70b-instruct
# - bedrock:cohere.command-r-plus
# - bedrock:amazon.titan-text-express
```

### Usage Examples

#### Basic Chat

```elixir
# Chat with Bedrock model
{:ok, response} = Jido.AI.chat(
  "bedrock:anthropic.claude-3-sonnet",
  "Analyze this financial document for compliance issues"
)
```

#### With IAM Role

```elixir
# Use IAM role for authentication (recommended)
{:ok, response} = Jido.AI.chat(
  "bedrock:anthropic.claude-3-sonnet",
  prompt,
  role_arn: "arn:aws:iam::123456789:role/BedrockRole"
)
```

#### VPC Endpoint

```elixir
# Use VPC endpoint for private connectivity
{:ok, response} = Jido.AI.chat(
  "bedrock:anthropic.claude-3-sonnet",
  prompt,
  endpoint_url: "https://vpce-xxx.bedrock.us-east-1.vpce.amazonaws.com"
)
```

#### Model Customization

```elixir
# Use custom fine-tuned model
{:ok, response} = Jido.AI.chat(
  "bedrock:custom-model-arn",
  prompt,
  model_arn: "arn:aws:bedrock:us-east-1:123456789:provisioned-model/xxx"
)
```

### Rate Limits

Varies by model and region:
- Claude 3 Sonnet: 10K TPM (default)
- Llama 3: 20K TPM (default)
- Request quota increases through AWS Support

### Pricing

Pay-per-use or provisioned throughput:
- On-demand: Per 1K tokens (varies by model)
- Provisioned: Hourly rate for dedicated capacity

## Google Vertex AI

### Overview

Google Vertex AI provides access to Gemini and PaLM models with enterprise features through Google Cloud Platform.

**Key Features:**
- ✅ SOC2, HIPAA, GDPR compliant
- 🔐 Google Cloud IAM integration
- 📊 99.95% SLA
- 🔍 Grounding with Google Search
- 📈 Cloud Monitoring integration
- 🎯 Custom model training and deployment

### Setup

```bash
# Set credentials
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/service-account.json"
export GOOGLE_CLOUD_PROJECT="your-project-id"
export GOOGLE_CLOUD_REGION="us-central1"
```

```elixir
# Or via Keyring
Jido.AI.Keyring.set(:vertex, %{
  project_id: "your-project-id",
  credentials: File.read!("/path/to/credentials.json") |> Jason.decode!(),
  region: "us-central1"
})
```

### Available Models

```elixir
# List available models
{:ok, models} = Jido.AI.Model.Registry.discover_models(provider: :vertex)

# Popular models:
# - vertex:gemini-1.5-pro (2M context)
# - vertex:gemini-1.5-flash (fast)
# - vertex:gemini-1.0-pro (balanced)
# - vertex:text-bison (PaLM 2)
```

### Usage Examples

#### Basic Chat

```elixir
# Chat with Vertex model
{:ok, response} = Jido.AI.chat(
  "vertex:gemini-1.5-pro",
  "Summarize this legal contract"
)
```

#### Grounding with Google Search

```elixir
# Use Google Search for grounding
{:ok, response} = Jido.AI.chat(
  "vertex:gemini-1.5-pro",
  "What are the latest regulations in fintech?",
  grounding: %{
    sources: [:google_search],
    disable_attribution: false
  }
)

# Response includes citations
if response.grounding_metadata do
  IO.inspect response.grounding_metadata.citations
end
```

#### Long Context Processing

```elixir
# Gemini 1.5 Pro supports 2M token context
{:ok, response} = Jido.AI.chat(
  "vertex:gemini-1.5-pro",
  very_long_document <> "\n\nAnalyze this document",
  max_output_tokens: 8192
)
```

#### Custom Models

```elixir
# Use custom fine-tuned model
{:ok, response} = Jido.AI.chat(
  "vertex:projects/my-project/locations/us-central1/models/my-model",
  prompt
)
```

### Rate Limits

| Model | QPM | TPM |
|-------|-----|-----|
| Gemini 1.5 Pro | 300 | 4M |
| Gemini 1.5 Flash | 2000 | 4M |
| PaLM 2 | 300 | 300K |

### Pricing

Usage-based (varies by model and region):
- Gemini 1.5 Pro: ~$0.00125 per 1K tokens (input)
- Gemini 1.5 Flash: ~$0.000125 per 1K tokens (input)
- Committed use discounts available

## IBM watsonx.ai

### Overview

IBM watsonx.ai provides enterprise AI with focus on governance, explainability, and industry-specific solutions.

**Key Features:**
- ✅ Industry compliance (financial services, healthcare)
- 🔐 IBM Cloud IAM integration
- 📊 AI governance and monitoring
- 🎯 Industry-specific models
- 📈 Model lifecycle management
- 🔍 Explainability tools

### Setup

```bash
# Set credentials
export WATSONX_API_KEY="..."
export WATSONX_PROJECT_ID="..."
export WATSONX_URL="https://us-south.ml.cloud.ibm.com"
```

### Usage Examples

```elixir
# Chat with watsonx model
{:ok, response} = Jido.AI.chat(
  "watsonx:ibm/granite-13b-chat-v2",
  "Analyze this insurance claim"
)
```

## Feature Comparison

### Compliance and Security

| Provider | HIPAA | SOC2 | GDPR | CCPA | FedRAMP |
|----------|-------|------|------|------|---------|
| Azure OpenAI | ✅ | ✅ | ✅ | ✅ | ✅ |
| Amazon Bedrock | ✅ | ✅ | ✅ | ✅ | ✅ |
| Google Vertex AI | ✅ | ✅ | ✅ | ✅ | ✅ |
| IBM watsonx.ai | ✅ | ✅ | ✅ | ✅ | In Progress |

### Authentication Methods

| Provider | API Key | SSO | IAM Roles | Managed Identity |
|----------|---------|-----|-----------|------------------|
| Azure OpenAI | ✅ | ✅ Entra ID | ✅ | ✅ |
| Amazon Bedrock | ✅ | ✅ AWS SSO | ✅ IAM | ✅ |
| Google Vertex AI | ✅ | ✅ Google | ✅ Service Accounts | ✅ |
| IBM watsonx.ai | ✅ | ✅ IBM | ✅ | ✅ |

### Enterprise Features

| Provider | SLA | VPC Support | Audit Logging | Custom Models |
|----------|-----|-------------|---------------|---------------|
| Azure OpenAI | 99.9% | ✅ | ✅ | ✅ |
| Amazon Bedrock | 99.9% | ✅ | CloudWatch | ✅ |
| Google Vertex AI | 99.95% | ✅ | Cloud Logging | ✅ |
| IBM watsonx.ai | 99.9% | ✅ | ✅ | ✅ |

## Best Practices

### 1. Authentication and Security

```elixir
# Use managed identities instead of API keys
defmodule MyApp.SecureAI do
  def chat(prompt) do
    case Application.get_env(:my_app, :cloud_provider) do
      :azure ->
        Jido.AI.chat(
          "azure:gpt-4",
          prompt,
          auth_type: :managed_identity
        )

      :aws ->
        Jido.AI.chat(
          "bedrock:anthropic.claude-3-sonnet",
          prompt,
          auth_type: :iam_role
        )

      :gcp ->
        Jido.AI.chat(
          "vertex:gemini-1.5-pro",
          prompt,
          auth_type: :service_account
        )
    end
  end
end
```

### 2. Multi-Region Deployment

```elixir
# Implement multi-region failover
defmodule MyApp.MultiRegionAI do
  @regions [
    {%{provider: "azure:gpt-4", region: "eastus"}, 1},
    {%{provider: "azure:gpt-4", region: "westus"}, 2},
    {%{provider: "bedrock:anthropic.claude-3-sonnet", region: "us-east-1"}, 3}
  ]

  def chat(prompt) do
    Enum.reduce_while(@regions, {:error, :all_failed}, fn {config, _priority}, _acc ->
      case try_region(config, prompt) do
        {:ok, response} -> {:halt, {:ok, response}}
        {:error, _} -> {:cont, {:error, :all_failed}}
      end
    end)
  end

  defp try_region(%{provider: provider, region: region}, prompt) do
    Jido.AI.chat(provider, prompt, region: region, timeout: 5_000)
  end
end
```

### 3. Compliance and Audit Logging

```elixir
# Log all AI interactions for compliance
defmodule MyApp.ComplianceLogger do
  require Logger

  def chat(user_id, prompt, opts \\ []) do
    request_id = generate_request_id()

    Logger.metadata(
      request_id: request_id,
      user_id: user_id,
      timestamp: DateTime.utc_now()
    )

    Logger.info("AI request initiated", %{
      prompt_length: String.length(prompt),
      model: Keyword.get(opts, :model, "default")
    })

    result = Jido.AI.chat(
      "azure:gpt-4",
      prompt,
      Keyword.merge(opts, request_id: request_id)
    )

    case result do
      {:ok, response} ->
        Logger.info("AI request completed", %{
          request_id: request_id,
          response_length: String.length(response.content),
          tokens_used: response.usage.total_tokens
        })

      {:error, reason} ->
        Logger.error("AI request failed", %{
          request_id: request_id,
          reason: inspect(reason)
        })
    end

    # Store in audit database
    store_audit_record(request_id, user_id, prompt, result)

    result
  end

  defp store_audit_record(request_id, user_id, prompt, result) do
    # Implementation depends on your audit system
    # Could be database, S3, dedicated audit service, etc.
  end

  defp generate_request_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16()
  end
end
```

### 4. Content Filtering

```elixir
# Implement content filtering for compliance
defmodule MyApp.ContentFilter do
  def chat(prompt, opts \\ []) do
    # Pre-filter input
    case validate_input(prompt) do
      :ok ->
        result = Jido.AI.chat("azure:gpt-4", prompt, opts)

        # Post-filter output
        case result do
          {:ok, response} -> validate_output(response)
          error -> error
        end

      {:error, reason} ->
        {:error, {:content_violation, reason}}
    end
  end

  defp validate_input(prompt) do
    # Check for prohibited content
    # This is a simplified example
    prohibited = ["confidential", "secret", "internal"]

    if Enum.any?(prohibited, &String.contains?(String.downcase(prompt), &1)) do
      {:error, :prohibited_content}
    else
      :ok
    end
  end

  defp validate_output(response) do
    # Check Azure content filter results if available
    if response.content_filter_results do
      case response.content_filter_results do
        %{severity: severity} when severity in [:high, :medium] ->
          {:error, {:filtered, severity}}
        _ ->
          {:ok, response}
      end
    else
      {:ok, response}
    end
  end
end
```

### 5. Cost Management

```elixir
# Implement cost tracking and limits
defmodule MyApp.CostControl do
  use GenServer

  @monthly_budget 10_000  # $10,000

  def start_link(_), do: GenServer.start_link(__MODULE__, %{spent: 0}, name: __MODULE__)

  def chat(prompt, opts \\ []) do
    case check_budget() do
      :ok ->
        result = Jido.AI.chat("azure:gpt-4", prompt, opts)

        case result do
          {:ok, response} ->
            track_cost(response.usage)
            {:ok, response}
          error -> error
        end

      {:error, :budget_exceeded} ->
        {:error, :budget_exceeded}
    end
  end

  defp check_budget do
    spent = GenServer.call(__MODULE__, :get_spent)
    if spent < @monthly_budget, do: :ok, else: {:error, :budget_exceeded}
  end

  defp track_cost(usage) do
    # Calculate cost based on usage
    # Azure GPT-4: ~$0.03 input, ~$0.06 output per 1K tokens
    cost = (usage.prompt_tokens * 0.03 + usage.completion_tokens * 0.06) / 1000

    GenServer.cast(__MODULE__, {:add_cost, cost})

    # Alert if approaching budget
    if GenServer.call(__MODULE__, :get_spent) > @monthly_budget * 0.9 do
      Logger.warning("AI spending at 90% of monthly budget")
    end
  end

  def handle_call(:get_spent, _from, state), do: {:reply, state.spent, state}
  def handle_cast({:add_cost, cost}, state), do: {:noreply, %{state | spent: state.spent + cost}}
end
```

## Troubleshooting

### Authentication Issues

```elixir
# Verify credentials
case Jido.AI.chat("azure:gpt-4", "test") do
  {:ok, _} ->
    IO.puts "Authentication successful"
  {:error, %{status: 401}} ->
    IO.puts "Check API key or managed identity configuration"
  {:error, %{status: 403}} ->
    IO.puts "Check IAM permissions"
  {:error, reason} ->
    IO.puts "Error: #{inspect(reason)}"
end
```

### Rate Limit Management

```elixir
# Implement exponential backoff
defmodule MyApp.RateLimitHandler do
  def chat_with_retry(model, prompt, retries \\ 3) do
    case Jido.AI.chat(model, prompt) do
      {:ok, response} ->
        {:ok, response}

      {:error, %{status: 429}} when retries > 0 ->
        backoff = :math.pow(2, 4 - retries) * 1000
        :timer.sleep(round(backoff))
        chat_with_retry(model, prompt, retries - 1)

      error -> error
    end
  end
end
```

### Regional Compliance

```elixir
# Ensure data stays in required region
defmodule MyApp.RegionalCompliance do
  @region_mapping %{
    eu: "westeurope",
    us: "eastus",
    asia: "southeastasia"
  }

  def chat(prompt, user_region) do
    region = Map.get(@region_mapping, user_region, "eastus")

    Jido.AI.chat(
      "azure:gpt-4",
      prompt,
      region: region,
      data_residency: :enforce
    )
  end
end
```

## Next Steps

- [Provider Matrix](provider-matrix.md) - Compare all providers
- [Local Providers](local-models.md) - For maximum privacy
- [Migration Guide](../migration/from-legacy-providers.md) - Upgrade existing code
- [Advanced Features](../features/) - Use enterprise capabilities
