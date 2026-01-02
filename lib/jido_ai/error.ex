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
