defmodule Jido.AI.Error do
  @moduledoc """
  Splode-based error handling for Jido.AI.

  Provides structured error types for AI operations including:
  - API errors (rate limits, authentication, etc.)
  - Validation errors
  - Execution errors
  """

  use Splode,
    error_classes: [
      api: Jido.AI.Error.API,
      validation: Jido.AI.Error.Validation,
      execution: Jido.AI.Error.Execution
    ],
    unknown_error: Jido.AI.Error.Unknown
end

defmodule Jido.AI.Error.API do
  @moduledoc "API-level errors from LLM providers"

  use Splode.ErrorClass,
    class: :api
end

defmodule Jido.AI.Error.Validation do
  @moduledoc "Input/output validation errors"

  use Splode.ErrorClass,
    class: :validation
end

defmodule Jido.AI.Error.Execution do
  @moduledoc "Execution and runtime errors"

  use Splode.ErrorClass,
    class: :execution
end

defmodule Jido.AI.Error.Unknown do
  @moduledoc "Fallback error for unknown error types"

  use Splode.Error,
    fields: [:error],
    class: :unknown

  @impl true
  def message(%{error: error}) do
    "Unknown error: #{inspect(error)}"
  end
end

# ============================================================================
# API Error Types
# ============================================================================

defmodule Jido.AI.Error.API.RateLimit do
  @moduledoc "Rate limit exceeded error"

  use Splode.Error,
    fields: [:message, :retry_after],
    class: :api

  @impl true
  def message(%{message: message}) when is_binary(message), do: message
  def message(%{retry_after: seconds}) when is_integer(seconds), do: "Rate limit exceeded, retry after #{seconds} seconds"
  def message(_), do: "Rate limit exceeded"
end

defmodule Jido.AI.Error.API.Auth do
  @moduledoc "Authentication/authorization error"

  use Splode.Error,
    fields: [:message],
    class: :api

  @impl true
  def message(%{message: message}) when is_binary(message), do: message
  def message(_), do: "Authentication failed"
end

defmodule Jido.AI.Error.API.Timeout do
  @moduledoc "Request timeout error"

  use Splode.Error,
    fields: [:message],
    class: :api

  @impl true
  def message(%{message: message}) when is_binary(message), do: message
  def message(_), do: "Request timed out"
end

defmodule Jido.AI.Error.API.Provider do
  @moduledoc "Provider-side error (5xx)"

  use Splode.Error,
    fields: [:message, :status],
    class: :api

  @impl true
  def message(%{message: message}) when is_binary(message), do: message
  def message(%{status: status}) when is_integer(status), do: "Provider error (#{status})"
  def message(_), do: "Provider error"
end

defmodule Jido.AI.Error.API.Network do
  @moduledoc "Network connectivity error"

  use Splode.Error,
    fields: [:message],
    class: :api

  @impl true
  def message(%{message: message}) when is_binary(message), do: message
  def message(_), do: "Network error"
end

# ============================================================================
# Validation Error Types
# ============================================================================

defmodule Jido.AI.Error.Validation.Invalid do
  @moduledoc "Input validation error"

  use Splode.Error,
    fields: [:message, :field],
    class: :validation

  @impl true
  def message(%{message: message}) when is_binary(message), do: message
  def message(%{field: field}) when is_binary(field), do: "Invalid field: #{field}"
  def message(_), do: "Validation error"
end
