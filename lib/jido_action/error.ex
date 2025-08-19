defmodule Jido.Action.Error do
  @moduledoc """
  Centralized error handling for Jido Actions using Splode.

  This module provides a consistent way to create, aggregate, and handle errors
  within the Jido Action system. It uses the Splode library to enable error
  composition and classification.

  ## Error Classes

  Errors are organized into the following classes, in order of precedence:

  - `:invalid` - Input validation, bad requests, and invalid configurations
  - `:execution` - Runtime execution errors and action failures
  - `:config` - System configuration and setup errors
  - `:internal` - Unexpected internal errors and system failures

  When multiple errors are aggregated, the class of the highest precedence error
  determines the overall error class.

  ## Usage

  Use this module to create and handle errors consistently:

      # Create a specific error
      {:error, error} = Jido.Action.Error.validation_error("must be a positive integer", field: :user_id)

      # Create timeout error
      {:error, timeout} = Jido.Action.Error.timeout_error("Action timed out after 30s", timeout: 30000)

      # Convert any value to a proper error
      {:error, normalized} = Jido.Action.Error.to_error("Something went wrong")
  """
  use Splode,
    # Error class modules for Splode
    error_classes: [
      invalid: Invalid,
      execution: Execution,
      config: Config,
      internal: Internal
    ],
    unknown_error: __MODULE__.Internal.UnknownError

  defmodule Invalid do
    @moduledoc "Invalid input error class"
    use Splode.ErrorClass, class: :invalid
  end

  defmodule Execution do
    @moduledoc "Execution error class"
    use Splode.ErrorClass, class: :execution
  end

  defmodule Config do
    @moduledoc "Configuration error class"
    use Splode.ErrorClass, class: :config
  end

  defmodule Internal do
    @moduledoc "Internal error class"
    use Splode.ErrorClass, class: :internal

    defmodule UnknownError do
      @moduledoc "Unknown internal error"
      defexception [:message, :details]

      @type t :: %__MODULE__{
              message: String.t(),
              details: map()
            }

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

    @type t :: %__MODULE__{
            message: String.t(),
            field: atom() | nil,
            value: any() | nil,
            details: map()
          }

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
    @moduledoc "Error for runtime execution failures"
    defexception [:message, :details]

    @type t :: %__MODULE__{
            message: String.t(),
            details: map()
          }

    @impl true
    def exception(opts) do
      %__MODULE__{
        message: Keyword.get(opts, :message, "Execution failed"),
        details: Keyword.get(opts, :details, %{})
      }
    end
  end

  defmodule TimeoutError do
    @moduledoc "Error for action timeouts"
    defexception [:message, :timeout, :details]

    @type t :: %__MODULE__{
            message: String.t(),
            timeout: non_neg_integer() | nil,
            details: map()
          }

    @impl true
    def exception(opts) do
      %__MODULE__{
        message: Keyword.get(opts, :message, "Action timed out"),
        timeout: Keyword.get(opts, :timeout),
        details: Keyword.get(opts, :details, %{})
      }
    end
  end

  defmodule ConfigurationError do
    @moduledoc "Error for configuration issues"
    defexception [:message, :details]

    @type t :: %__MODULE__{
            message: String.t(),
            details: map()
          }

    @impl true
    def exception(opts) do
      %__MODULE__{
        message: Keyword.get(opts, :message, "Configuration error"),
        details: Keyword.get(opts, :details, %{})
      }
    end
  end

  defmodule InternalError do
    @moduledoc "Error for unexpected internal failures"
    defexception [:message, :details]

    @type t :: %__MODULE__{
            message: String.t(),
            details: map()
          }

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
  @spec validation_error(String.t(), map()) :: InvalidInputError.t()
  def validation_error(message, details \\ %{}) do
    InvalidInputError.exception(
      message: message,
      field: details[:field],
      value: details[:value],
      details: details
    )
  end

  @doc """
  Creates an execution error for runtime failures.
  """
  @spec execution_error(String.t(), map()) :: ExecutionFailureError.t()
  def execution_error(message, details \\ %{}) do
    ExecutionFailureError.exception(
      message: message,
      details: details
    )
  end

  @doc """
  Creates a configuration error.
  """
  @spec config_error(String.t(), map()) :: ConfigurationError.t()
  def config_error(message, details \\ %{}) do
    ConfigurationError.exception(
      message: message,
      details: details
    )
  end

  @doc """
  Creates a timeout error.
  """
  @spec timeout_error(String.t(), map()) :: TimeoutError.t()
  def timeout_error(message, details \\ %{}) do
    TimeoutError.exception(
      message: message,
      timeout: details[:timeout],
      details: details
    )
  end

  @doc """
  Creates an internal server error.
  """
  @spec internal_error(String.t(), map()) :: InternalError.t()
  def internal_error(message, details \\ %{}) do
    InternalError.exception(
      message: message,
      details: details
    )
  end

  @doc """
  Formats a NimbleOptions configuration error for display.
  Used when configuration validation fails during compilation.
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
