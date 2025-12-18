# Enterprise Provider Validation

This document describes the enterprise provider validation features implemented in Task 2.1.4 of Phase 2. These features extend the Jido AI ReqLLM bridge to support enterprise-grade authentication and validation for Azure OpenAI, Amazon Bedrock, and regional providers like Alibaba Cloud.

## Overview

The enterprise provider validation system provides:

- **Enterprise Authentication**: Secure authentication patterns for Azure OpenAI (API key, Microsoft Entra ID), Amazon Bedrock (IAM roles, direct credentials), and Alibaba Cloud (API key, workspace isolation)
- **Multi-Tenant Support**: Tenant isolation and enterprise security compliance
- **Regional Compliance**: Data residency, cross-border transfer restrictions, and privacy framework compliance
- **Performance Monitoring**: Authentication overhead measurement and optimization
- **Comprehensive Testing**: Functional validation tests for each enterprise provider

## Enterprise Providers

### Azure OpenAI

Supports Microsoft's enterprise OpenAI service with tenant-specific configurations.

#### Authentication Methods

1. **API Key Authentication**
   ```elixir
   config = %{
     api_key: "your-azure-api-key",
     endpoint: "https://your-resource.openai.azure.com/",
     auth_method: :api_key,
     resource_name: "your-resource"
   }
   ```

2. **Microsoft Entra ID**
   ```elixir
   config = %{
     tenant_id: "your-tenant-id",
     client_id: "your-client-id",
     client_secret: "your-client-secret",
     endpoint: "https://your-resource.openai.azure.com/",
     auth_method: :entra_id
   }
   ```

3. **Managed Identity** (Future)
   ```elixir
   config = %{
     managed_identity_id: "your-identity-id",
     endpoint: "https://your-resource.openai.azure.com/",
     auth_method: :managed_identity
   }
   ```

#### Key Features

- **2025 API Compatibility**: Updated to support latest Azure OpenAI API versions
- **RBAC Integration**: Role-based access control for enterprise environments
- **Private Endpoints**: Support for Azure private endpoint configurations
- **Tenant Isolation**: Multi-tenant workspace management

### Amazon Bedrock

Supports AWS's foundation model service with enterprise security patterns.

#### Authentication Methods

1. **IAM Role Authentication**
   ```elixir
   config = %{
     role_arn: "arn:aws:iam::123456789012:role/BedrockRole",
     region: "us-east-1",
     auth_method: :iam_role
   }
   ```

2. **Direct Credentials**
   ```elixir
   config = %{
     access_key_id: "your-access-key",
     secret_access_key: "your-secret-key",
     session_token: "your-session-token", # optional
     region: "us-east-1",
     auth_method: :direct_credentials
   }
   ```

3. **Cross-Account Access** (Future)
   ```elixir
   config = %{
     cross_account_role: "arn:aws:iam::987654321098:role/CrossAccountRole",
     external_id: "your-external-id",
     region: "us-east-1",
     auth_method: :cross_account
   }
   ```

#### Key Features

- **Multi-Region Deployment**: Support for all AWS Bedrock regions
- **Foundation Model Access**: Claude, Titan, Jurassic, and other models
- **VPC Endpoints**: Private network access through AWS VPC
- **Compliance**: HIPAA, SOC, and other enterprise compliance frameworks

### Alibaba Cloud (Regional Provider)

Supports Alibaba Cloud's DashScope service for APAC region deployments.

#### Authentication Methods

1. **API Key Authentication**
   ```elixir
   config = %{
     api_key: "your-dashscope-api-key",
     region: "ap-southeast-1",
     endpoint: "https://dashscope.aliyuncs.com",
     workspace: "default"
   }
   ```

2. **Workspace Isolation**
   ```elixir
   config = %{
     api_key: "your-dashscope-api-key",
     region: "ap-southeast-1",
     endpoint: "https://dashscope.aliyuncs.com",
     workspace: "enterprise-tenant-001",
     compliance_level: "enterprise"
   }
   ```

#### Key Features

- **Cultural Adaptation**: Multi-language support with Chinese language specialization
- **Regional Compliance**: GDPR, PDPA, PIPL compliance frameworks
- **Data Residency**: Enforced data residency for APAC regions
- **Cross-Border Controls**: Configurable cross-border data transfer restrictions

## Usage Examples

### Basic Provider Validation

```elixir
# Test Azure OpenAI provider
{:ok, response} = Jido.AI.ReqLLMBridge.chat_completion(
  :azure_openai,
  %{
    model: "gpt-4",
    messages: [%{role: "user", content: "Hello Azure OpenAI"}],
    max_tokens: 100
  },
  azure_config
)

# Test Amazon Bedrock
{:ok, response} = Jido.AI.ReqLLMBridge.chat_completion(
  :amazon_bedrock,
  %{
    model: "anthropic.claude-3-sonnet-20240229-v1:0",
    messages: [%{role: "user", content: "Hello Bedrock"}],
    max_tokens: 100
  },
  bedrock_config
)

# Test Alibaba Cloud with Chinese
{:ok, response} = Jido.AI.ReqLLMBridge.chat_completion(
  :alibaba_cloud,
  %{
    model: "qwen2.5-72b-instruct",
    messages: [%{role: "user", content: "你好，阿里云"}],
    max_tokens: 100,
    language: "zh-CN"
  },
  alibaba_config
)
```

### Enterprise Authentication

```elixir
# Authenticate with enterprise provider
{:ok, headers} = Jido.AI.ReqLLMBridge.EnterpriseAuthentication.authenticate_azure_openai(
  azure_config,
  []
)

# Validate enterprise security compliance
Jido.AI.Test.EnterpriseHelpers.assert_enterprise_security_compliance(
  {:ok, headers},
  :enterprise
)

# Measure authentication overhead
{auth_result, overhead_ms} = Jido.AI.Test.EnterpriseHelpers.measure_auth_overhead(fn ->
  Jido.AI.ReqLLMBridge.EnterpriseAuthentication.authenticate_bedrock(
    bedrock_config,
    []
  )
end)
```

## Testing

### Running Enterprise Provider Tests

The enterprise provider validation includes comprehensive test suites:

```bash
# Run all enterprise provider validation tests
mix test --only provider_validation

# Run specific provider tests
mix test --only azure_openai
mix test --only amazon_bedrock
mix test --only alibaba_cloud

# Run enterprise authentication tests
mix test --only enterprise_authentication

# Run integration tests
mix test --only authentication_flows
```

### Test Tags

The test suites use the following tags for organization:

- `@moduletag :provider_validation` - All provider validation tests
- `@moduletag :functional_validation` - Functional test suites
- `@moduletag :integration_testing` - Integration test suites
- `@moduletag :enterprise_providers` - Enterprise provider tests
- `@moduletag :azure_openai` - Azure OpenAI specific tests
- `@moduletag :amazon_bedrock` - Amazon Bedrock specific tests
- `@moduletag :alibaba_cloud` - Alibaba Cloud specific tests
- `@moduletag :enterprise_authentication` - Authentication flow tests

### Credential Requirements

Tests automatically skip when credentials are not available:

```bash
# Set Azure OpenAI credentials
export AZURE_OPENAI_API_KEY="your-api-key"
export AZURE_OPENAI_ENDPOINT="https://your-resource.openai.azure.com/"

# Set AWS credentials
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_REGION="us-east-1"

# Set Alibaba Cloud credentials
export ALIBABA_CLOUD_API_KEY="your-api-key"
export ALIBABA_CLOUD_REGION="ap-southeast-1"
```

## Configuration Examples

### Production Azure OpenAI Configuration

```elixir
config :jido_ai, :azure_openai,
  auth_method: :entra_id,
  tenant_id: {:system, "AZURE_TENANT_ID"},
  client_id: {:system, "AZURE_CLIENT_ID"},
  client_secret: {:system, "AZURE_CLIENT_SECRET"},
  endpoint: {:system, "AZURE_OPENAI_ENDPOINT"},
  resource_name: {:system, "AZURE_RESOURCE_NAME"},
  api_version: "2024-10-01-preview",
  rbac_enabled: true,
  private_endpoint: true
```

### Production Amazon Bedrock Configuration

```elixir
config :jido_ai, :amazon_bedrock,
  auth_method: :iam_role,
  role_arn: {:system, "AWS_BEDROCK_ROLE_ARN"},
  region: {:system, "AWS_REGION"},
  vpc_endpoint: {:system, "AWS_VPC_ENDPOINT"},
  compliance_frameworks: ["HIPAA", "SOC2"],
  cross_region_replication: true,
  disaster_recovery_region: "us-west-2"
```

### Production Alibaba Cloud Configuration

```elixir
config :jido_ai, :alibaba_cloud,
  api_key: {:system, "ALIBABA_CLOUD_API_KEY"},
  region: {:system, "ALIBABA_CLOUD_REGION"},
  endpoint: {:system, "ALIBABA_CLOUD_ENDPOINT"},
  workspace: {:system, "ALIBABA_CLOUD_WORKSPACE"},
  compliance_level: "enterprise",
  data_residency_required: true,
  cross_border_transfer: false,
  privacy_framework: "PIPL"
```

## Security Considerations

### Authentication Security

- **Token Management**: All authentication tokens are handled securely and never logged
- **Session Isolation**: Multi-tenant configurations ensure proper session isolation
- **Credential Rotation**: Support for credential rotation and refresh patterns
- **Audit Logging**: Enterprise authentication events are logged for compliance

### Network Security

- **Private Endpoints**: Support for private network access where available
- **TLS Encryption**: All communications use TLS 1.2 or higher
- **Certificate Validation**: Strict certificate validation for all connections
- **IP Restrictions**: Support for IP allowlist configurations

### Compliance Features

- **Data Residency**: Configurable data residency requirements
- **Cross-Border Controls**: Granular control over cross-border data transfers
- **Privacy Frameworks**: Support for GDPR, PIPL, PDPA compliance
- **Audit Trails**: Comprehensive audit logging for enterprise environments

## Troubleshooting

### Common Issues

1. **Authentication Failures**
   ```
   Error: Azure OpenAI credentials not available
   Solution: Verify AZURE_OPENAI_API_KEY and AZURE_OPENAI_ENDPOINT are set
   ```

2. **Regional Access Issues**
   ```
   Error: Region not supported for Alibaba Cloud
   Solution: Verify region is in supported list: ap-southeast-1, ap-northeast-1, etc.
   ```

3. **Cross-Border Restrictions**
   ```
   Error: Cross-border transfer restricted
   Solution: Check data residency configuration and compliance settings
   ```

### Debug Mode

Enable debug mode for detailed authentication flows:

```elixir
config :jido_ai, :req_llm_bridge,
  debug_authentication: true,
  log_level: :debug
```

## Migration Guide

### From Basic to Enterprise Providers

1. **Update Configuration**: Add enterprise authentication methods
2. **Add Credentials**: Configure enterprise credentials in environment
3. **Update Tests**: Use enterprise test helpers for validation
4. **Enable Compliance**: Configure regional and compliance settings

### Credential Migration

```elixir
# Before (basic OpenAI)
config = %{api_key: "sk-..."}

# After (enterprise Azure OpenAI)
config = %{
  api_key: "your-azure-key",
  endpoint: "https://your-resource.openai.azure.com/",
  auth_method: :api_key,
  resource_name: "your-resource"
}
```

## Support

For enterprise provider validation support:

1. Check the test suites for usage examples
2. Review the enterprise authentication bridge implementation
3. Consult the planning document for detailed specifications
4. Use the enterprise test helpers for validation patterns

## Related Documentation

- [Phase 2 Implementation Plan](../notes/features/phase-2-1-4-enterprise-provider-validation-plan.md)
- [ReqLLM Bridge Documentation](../lib/jido_ai/req_llm_bridge/)
- [Enterprise Authentication Bridge](../lib/jido_ai/req_llm_bridge/enterprise_authentication.ex)
- [Enterprise Test Helpers](../test/support/enterprise_test_helpers.ex)