defmodule JidoKeys.Error do
  @moduledoc """
  Error handling for JidoKeys using Splode error system.
  """

  use Splode,
    error_classes: [
      invalid: JidoKeys.Error.InvalidError,
      not_found: JidoKeys.Error.NotFoundError,
      config: JidoKeys.Error.ConfigurationError,
      server: JidoKeys.Error.ServerError
    ],
    unknown_error: JidoKeys.Error.ServerError
end

defmodule JidoKeys.Error.InvalidError do
  @moduledoc """
  Error for invalid input or parameters.
  """

  use Splode.Error,
    fields: [:field, :value],
    class: :invalid

  def message(%{field: field, value: value}) do
    "Invalid value #{inspect(value)} for field #{field}"
  end

  def message(%{field: field}) do
    "Invalid value for field #{field}"
  end

  def message(_) do
    "Invalid input"
  end
end

defmodule JidoKeys.Error.NotFoundError do
  @moduledoc """
  Error for when a configuration key is not found.
  """

  use Splode.Error,
    fields: [:key],
    class: :not_found

  def message(%{key: key}) do
    "Configuration key #{inspect(key)} not found"
  end

  def message(_) do
    "Configuration not found"
  end
end

defmodule JidoKeys.Error.ConfigurationError do
  @moduledoc """
  Error for configuration-related issues.
  """

  use Splode.Error,
    fields: [:reason],
    class: :config

  def message(%{reason: reason}) do
    "Configuration error: #{reason}"
  end

  def message(_) do
    "Configuration error"
  end
end

defmodule JidoKeys.Error.ServerError do
  @moduledoc """
  Error for GenServer-related issues.
  """

  use Splode.Error,
    fields: [:reason],
    class: :server

  def message(%{reason: reason}) do
    "Server error: #{reason}"
  end

  def message(_) do
    "Server error"
  end
end
