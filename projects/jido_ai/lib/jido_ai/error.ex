defmodule Jido.AI.Error do
  @moduledoc """
  Error handling system for Jido.AI using Splode.
  """

  use Splode,
    error_classes: [
      invalid: Jido.AI.Error.Invalid,
      api: Jido.AI.Error.API,
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

  defmodule Unknown.Unknown do
    @moduledoc "Error for unexpected or unhandled errors."
    use Splode.Error, fields: [:error], class: :unknown

    @spec message(map()) :: String.t()
    def message(%{error: error}) do
      "Unknown error: #{inspect(error)}"
    end
  end
end
