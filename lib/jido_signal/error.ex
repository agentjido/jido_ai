defmodule Jido.Signal.Error do
  @moduledoc """
  Centralized error handling for Jido Signal using Splode.

  This module provides a consistent way to create, aggregate, and handle errors
  within the Jido Signal system. It uses the Splode library to enable error
  composition and classification.

  ## Error Classes

  Errors are organized into the following classes, in order of precedence:

  - `:invalid` - Input validation, bad requests, and invalid configurations
  - `:execution` - Runtime execution errors and signal processing failures
  - `:routing` - Signal routing and dispatch errors
  - `:timeout` - Signal processing and delivery timeouts
  - `:internal` - Unexpected internal errors and system failures

  When multiple errors are aggregated, the class of the highest precedence error
  determines the overall error class.

  ## Usage

  Use this module to create and handle errors consistently:

      # Create a specific error
      {:error, error} = Jido.Signal.Error.validation_error("Invalid signal format", field: :signal_type)

      # Create routing error
      {:error, routing} = Jido.Signal.Error.routing_error("No route found for signal", target: "unknown")

      # Convert any value to a proper error
      {:error, normalized} = Jido.Signal.Error.to_error("Signal processing failed")
  """
  use Splode,
    # Error class modules for Splode
    error_classes: [
      invalid: Invalid,
      execution: Execution,
      routing: Routing,
      timeout: Timeout,
      internal: Internal
    ],
    unknown_error: Jido.Signal.Error.Internal.UnknownError

  defmodule Invalid do
    @moduledoc "Invalid input error class"
    use Splode.ErrorClass, class: :invalid
  end

  defmodule Execution do
    @moduledoc "Execution error class"
    use Splode.ErrorClass, class: :execution
  end

  defmodule Routing do
    @moduledoc "Routing error class"
    use Splode.ErrorClass, class: :routing
  end

  defmodule Timeout do
    @moduledoc "Timeout error class"
    use Splode.ErrorClass, class: :timeout
  end

  defmodule Internal do
    @moduledoc "Internal error class"
    use Splode.ErrorClass, class: :internal

    defmodule UnknownError do
      @moduledoc "Unknown internal error"
      defexception [:message, :details]

      @impl true
      def exception(opts) do
        %__MODULE__{
          message: Keyword.get(opts, :message, "Unknown error"),
          details: Keyword.get(opts, :details, %{})
        }
      end
    end
  end

  # Define specific error structs inline
  defmodule InvalidInputError do
    @moduledoc "Error for invalid input parameters"
    defexception [:message, :field, :value, :details]

    @impl true
    def exception(opts) do
      message = Keyword.get(opts, :message, "Invalid input")

      %__MODULE__{
        message: message,
        field: Keyword.get(opts, :field),
        value: Keyword.get(opts, :value),
        details: Keyword.get(opts, :details, %{})
      }
    end
  end

  defmodule ExecutionFailureError do
    @moduledoc "Error for signal processing failures"
    defexception [:message, :details]

    @impl true
    def exception(opts) do
      %__MODULE__{
        message: Keyword.get(opts, :message, "Signal processing failed"),
        details: Keyword.get(opts, :details, %{})
      }
    end
  end

  defmodule RoutingError do
    @moduledoc "Error for signal routing failures"
    defexception [:message, :target, :details]

    @impl true
    def exception(opts) do
      %__MODULE__{
        message: Keyword.get(opts, :message, "Signal routing failed"),
        target: Keyword.get(opts, :target),
        details: Keyword.get(opts, :details, %{})
      }
    end
  end

  defmodule TimeoutError do
    @moduledoc "Error for signal processing timeouts"
    defexception [:message, :timeout, :details]

    @impl true
    def exception(opts) do
      %__MODULE__{
        message: Keyword.get(opts, :message, "Signal processing timed out"),
        timeout: Keyword.get(opts, :timeout),
        details: Keyword.get(opts, :details, %{})
      }
    end
  end

  defmodule DispatchError do
    @moduledoc "Error for signal dispatch failures"
    defexception [:message, :details]

    @impl true
    def exception(opts) do
      %__MODULE__{
        message: Keyword.get(opts, :message, "Signal dispatch failed"),
        details: Keyword.get(opts, :details, %{})
      }
    end
  end

  defmodule InternalError do
    @moduledoc "Error for unexpected internal failures"
    defexception [:message, :details]

    @impl true
    def exception(opts) do
      %__MODULE__{
        message: Keyword.get(opts, :message, "Internal error"),
        details: Keyword.get(opts, :details, %{})
      }
    end
  end

  @doc """
  Creates a validation error for invalid input parameters.
  """
  def validation_error(message, details \\ %{}) do
    InvalidInputError.exception(
      message: message,
      field: details[:field],
      value: details[:value],
      details: details
    )
  end

  @doc """
  Creates an execution error for signal processing failures.
  """
  def execution_error(message, details \\ %{}) do
    ExecutionFailureError.exception(
      message: message,
      details: details
    )
  end

  @doc """
  Creates a routing error for signal routing failures.
  """
  def routing_error(message, details \\ %{}) do
    RoutingError.exception(
      message: message,
      target: details[:target],
      details: details
    )
  end

  @doc """
  Creates a timeout error for signal processing timeouts.
  """
  def timeout_error(message, details \\ %{}) do
    TimeoutError.exception(
      message: message,
      timeout: details[:timeout],
      details: details
    )
  end

  @doc """
  Creates a dispatch error for signal dispatch failures.
  """
  def dispatch_error(message, details \\ %{}) do
    DispatchError.exception(
      message: message,
      details: details
    )
  end

  @doc """
  Creates an internal server error.
  """
  def internal_error(message, details \\ %{}) do
    InternalError.exception(
      message: message,
      details: details
    )
  end

  @doc """
  Formats a NimbleOptions validation error for configuration validation.
  Used when validating configuration options at compile or runtime.

  ## Parameters
  - `error`: The NimbleOptions.ValidationError to format
  - `module_type`: String indicating the module type (e.g. "Action", "Agent", "Sensor")

  ## Examples

      iex> error = %NimbleOptions.ValidationError{keys_path: [:name], message: "is required"}
      iex> Jido.Signal.Error.format_nimble_config_error(error, "Action")
      "Invalid configuration given to use Jido.Action for key [:name]: is required"
  """
  @spec format_nimble_config_error(
          NimbleOptions.ValidationError.t() | any(),
          String.t(),
          module()
        ) ::
          String.t()
  def format_nimble_config_error(
        %NimbleOptions.ValidationError{keys_path: [], message: message},
        module_type,
        module
      ) do
    "Invalid configuration given to use Jido.#{module_type} (#{module}): #{message}"
  end

  def format_nimble_config_error(
        %NimbleOptions.ValidationError{keys_path: keys_path, message: message},
        module_type,
        module
      ) do
    "Invalid configuration given to use Jido.#{module_type} (#{module}) for key #{inspect(keys_path)}: #{message}"
  end

  def format_nimble_config_error(error, _module_type, _module) when is_binary(error), do: error
  def format_nimble_config_error(error, _module_type, _module), do: inspect(error)

  @doc """
  Formats a NimbleOptions validation error for parameter validation.
  Used when validating runtime parameters.

  ## Parameters
  - `error`: The NimbleOptions.ValidationError to format
  - `module_type`: String indicating the module type (e.g. "Action", "Agent", "Sensor")

  ## Examples

      iex> error = %NimbleOptions.ValidationError{keys_path: [:input], message: "is required"}
      iex> Jido.Signal.Error.format_nimble_validation_error(error, "Action")
      "Invalid parameters for Action at [:input]: is required"
  """
  @spec format_nimble_validation_error(
          NimbleOptions.ValidationError.t() | any(),
          String.t(),
          module()
        ) ::
          String.t()
  def format_nimble_validation_error(
        %NimbleOptions.ValidationError{keys_path: [], message: message},
        module_type,
        module
      ) do
    "Invalid parameters for #{module_type} (#{module}): #{message}"
  end

  def format_nimble_validation_error(
        %NimbleOptions.ValidationError{keys_path: keys_path, message: message},
        module_type,
        module
      ) do
    "Invalid parameters for #{module_type} (#{module}) at #{inspect(keys_path)}: #{message}"
  end

  def format_nimble_validation_error(error, _module_type, _module) when is_binary(error),
    do: error

  def format_nimble_validation_error(error, _module_type, _module), do: inspect(error)
end
