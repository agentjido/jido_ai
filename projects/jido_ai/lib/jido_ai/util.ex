defmodule Jido.AI.Util do
  @moduledoc """
  Validation utilities for Jido AI parameters.

  Provides schema-based validation with Splode error integration and reusable
  validators for common AI model parameters like temperature.

  ## Features

  - **Schema Validation**: NimbleOptions-based with automatic provider_options catch-all
  - **Custom Validators**: Pattern-matched validators for AI parameters  
  - **Splode Integration**: Consistent error handling throughout the system

  ## Example

      schema = [temperature: [type: {:custom, __MODULE__, :validate_temperature, []}]]
      case validate_schema(opts, schema) do
        {:ok, validated} -> use_validated_options(validated)
        {:error, error} -> handle_validation_error(error)
      end

  """

  alias Jido.AI.Error

  require Logger

  @doc """
  Validates options against a NimbleOptions schema with Splode error integration.

  Returns validated options on success, or a Splode validation error on failure.
  Automatically handles the catch-all pattern where unrecognized options are moved
  to the :provider_options key if it exists in the schema.

  ## Examples

      iex> schema = [temperature: [type: :float], provider_options: [type: :keyword_list, default: []]]
      iex> opts = [temperature: 0.5, top_p: 0.9]
      iex> Jido.AI.Util.validate_schema(opts, schema)
      {:ok, [temperature: 0.5, provider_options: [top_p: 0.9]]}

  """
  @spec validate_schema(Keyword.t(), Keyword.t()) :: {:ok, Keyword.t()} | {:error, Error.t()}
  def validate_schema(opts, schema) do
    schema_keys = Keyword.keys(schema)
    has_provider_options = :provider_options in schema_keys

    {recognized_opts, unrecognized_opts} =
      if has_provider_options do
        Keyword.split(opts, schema_keys -- [:provider_options])
      else
        {Keyword.take(opts, schema_keys), []}
      end

    # Merge unrecognized options into provider_options if that key exists
    final_opts =
      if has_provider_options and unrecognized_opts != [] do
        existing_provider_opts = Keyword.get(recognized_opts, :provider_options, [])
        merged_provider_opts = Keyword.merge(existing_provider_opts, unrecognized_opts)
        Keyword.put(recognized_opts, :provider_options, merged_provider_opts)
      else
        recognized_opts
      end

    case NimbleOptions.validate(final_opts, schema) do
      {:ok, validated} ->
        {:ok, validated}

      {:error, %NimbleOptions.ValidationError{} = error} ->
        {:error, Error.validation_error(:options, Exception.message(error), opts: opts)}
    end
  rescue
    e in NimbleOptions.ValidationError ->
      {:error, Error.validation_error(:options, Exception.message(e), opts: opts)}
  end

  @doc """
  Validates temperature values for AI models.

  Accepts integers or floats in the range 0-2 (OpenAI standard).
  Normalizes integers to floats for consistency.

  ## Examples

      iex> validate_temperature(0.7)
      {:ok, 0.7}

      iex> validate_temperature(1)
      {:ok, 1.0}

      iex> validate_temperature(3.0)
      {:error, "expected :temperature to be a number between 0 and 2"}

  """
  @spec validate_temperature(term()) :: {:ok, float()} | {:error, String.t()}
  def validate_temperature(value) when is_integer(value) and value >= 0 and value <= 2 do
    # normalize to float
    {:ok, value / 1}
  end

  def validate_temperature(value) when is_float(value) and value >= 0.0 and value <= 2.0 do
    {:ok, value}
  end

  def validate_temperature(_) do
    {:error, "expected :temperature to be a number between 0 and 2"}
  end

  @doc """
  Conditionally puts a key-value pair in a keyword list.

  If the value is nil, returns the original keyword list unchanged.
  Otherwise, adds the key-value pair to the keyword list.

  ## Examples

      iex> maybe_put([], :key, "value")
      [key: "value"]

      iex> maybe_put([a: 1], :key, nil)
      [a: 1]

      iex> maybe_put([a: 1], :key, "value")  
      [a: 1, key: "value"]

  """
  @spec maybe_put(keyword(), atom(), any()) :: keyword()
  def maybe_put(opts, _key, nil), do: opts
  def maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
