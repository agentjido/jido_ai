defmodule Jido.AI.Error do
  @moduledoc """
  Error handling system for Jido.AI using Splode.
  """

  use Splode,
    error_classes: [
      invalid: Jido.AI.Error.Invalid,
      api: Jido.AI.Error.API,
      validation: Jido.AI.Error.Validation,
      unknown: Jido.AI.Error.Unknown,
      object_generation: Jido.AI.Error.ObjectGeneration
    ],
    unknown_error: Jido.AI.Error.Unknown.Unknown

  defmodule Invalid do
    @moduledoc "Error class for invalid input parameters and configurations."
    use Splode.ErrorClass, class: :invalid
  end

  defmodule API do
    @moduledoc "Error class for API-related failures and HTTP errors."
    use Splode.ErrorClass, class: :api
  end

  defmodule Validation do
    @moduledoc "Error class for validation failures and parameter errors."
    use Splode.ErrorClass, class: :validation
  end

  defmodule Unknown do
    @moduledoc "Error class for unexpected or unhandled errors."
    use Splode.ErrorClass, class: :unknown
  end

  defmodule Invalid.Parameter do
    @moduledoc "Error for invalid or missing parameters."
    use Splode.Error, fields: [:parameter], class: :invalid

    @spec message(map()) :: String.t()
    def message(%{parameter: parameter}) do
      "Invalid parameter: #{parameter}"
    end
  end

  defmodule API.Request do
    @moduledoc "Error for API request failures, HTTP errors, and network issues."
    use Splode.Error,
      fields: [:reason, :status, :response_body, :request_body, :cause],
      class: :api

    @spec message(map()) :: String.t()
    def message(%{reason: reason, status: status}) when not is_nil(status) do
      "API request failed (#{status}): #{reason}"
    end

    def message(%{reason: reason}) do
      "API request failed: #{reason}"
    end
  end

  defmodule Validation.Error do
    @moduledoc "Error for parameter validation failures."
    use Splode.Error,
      fields: [:tag, :reason, :context],
      class: :validation

    @typedoc "Validation error returned by Jido.AI"
    @type t() :: %__MODULE__{
            tag: atom(),
            reason: String.t(),
            context: keyword()
          }

    @spec message(map()) :: String.t()
    def message(%{reason: reason}) do
      reason
    end
  end

  defmodule Unknown.Unknown do
    @moduledoc "Error for unexpected or unhandled errors."
    use Splode.Error, fields: [:error], class: :unknown

    @spec message(map()) :: String.t()
    def message(%{error: error}) do
      "Unknown error: #{inspect(error)}"
    end
  end

  @doc """
  Creates a validation error with the given tag, reason, and context.

  ## Examples

      iex> Jido.AI.Error.validation_error(:invalid_model_spec, "Bad model", model: "test")
      %Jido.AI.Error.Validation.Error{tag: :invalid_model_spec, reason: "Bad model", context: [model: "test"]}

  """
  @spec validation_error(atom(), String.t(), keyword()) :: Jido.AI.Error.Validation.Error.t()
  def validation_error(tag, reason, context \\ []) do
    Jido.AI.Error.Validation.Error.exception(tag: tag, reason: reason, context: context)
  end
end
