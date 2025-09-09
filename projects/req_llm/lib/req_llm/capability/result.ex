defmodule ReqLLM.Capability.Result do
  @moduledoc """
  Represents a capability verification result.

  This struct provides a simple format for capability test results,
  replacing ExUnit test results with a focused structure for model
  capability verification outcomes.

  ## Fields

  - `:model` - The model identifier string (e.g., "openai:gpt-4")
  - `:capability` - The capability identifier (atom or string)
  - `:status` - Verification status (`:passed` or `:failed`)
  - `:latency_ms` - Request latency in milliseconds
  - `:details` - Optional raw verification result (any term)

  ## Usage Examples

      # Successful verification
      result = %ReqLLM.Capability.Result{
        model: "openai:gpt-4",
        capability: :generate_text,
        status: :passed,
        latency_ms: 1250,
        details: %{response: "Hello world", tokens: 2}
      }

      # Failed verification  
      result = %ReqLLM.Capability.Result{
        model: "anthropic:claude-3-sonnet",
        capability: "tool_calling",
        status: :failed,
        latency_ms: 2300,
        details: {:error, "Tool schema validation failed"}
      }

  """

  use TypedStruct

  @derive Jason.Encoder
  typedstruct enforce: true do
    @typedoc "A capability verification result"

    field(:model, String.t())
    field(:capability, atom() | String.t())
    field(:status, :passed | :failed)
    field(:latency_ms, non_neg_integer())
    field(:details, any(), default: nil, enforce: false)
  end

  @doc """
  Creates a passed result.

  ## Parameters

    * `model` - The model identifier string
    * `capability` - The capability identifier  
    * `latency_ms` - Request latency in milliseconds
    * `details` - Optional verification details

  ## Examples

      ReqLLM.Capability.Result.passed("openai:gpt-4", :generate_text, 1200)
      #=> %ReqLLM.Capability.Result{model: "openai:gpt-4", capability: :generate_text, status: :passed, latency_ms: 1200}

  """
  @spec passed(String.t(), atom() | String.t(), non_neg_integer(), any()) :: t()
  def passed(model, capability, latency_ms, details \\ nil) do
    %__MODULE__{
      model: model,
      capability: capability,
      status: :passed,
      latency_ms: latency_ms,
      details: details
    }
  end

  @doc """
  Creates a failed result.

  ## Parameters

    * `model` - The model identifier string
    * `capability` - The capability identifier
    * `latency_ms` - Request latency in milliseconds  
    * `details` - Optional failure details

  ## Examples

      ReqLLM.Capability.Result.failed("anthropic:claude-3-sonnet", :tool_calling, 2100, {:error, "Invalid schema"})
      #=> %ReqLLM.Capability.Result{model: "anthropic:claude-3-sonnet", capability: :tool_calling, status: :failed, latency_ms: 2100, details: {:error, "Invalid schema"}}

  """
  @spec failed(String.t(), atom() | String.t(), non_neg_integer(), any()) :: t()
  def failed(model, capability, latency_ms, details \\ nil) do
    %__MODULE__{
      model: model,
      capability: capability,
      status: :failed,
      latency_ms: latency_ms,
      details: details
    }
  end
end
