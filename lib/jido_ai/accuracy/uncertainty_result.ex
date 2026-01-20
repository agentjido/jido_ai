defmodule Jido.AI.Accuracy.UncertaintyResult do
  @moduledoc """
  Represents the result of uncertainty classification.

  An UncertaintyResult contains information about the type of uncertainty
  detected (aleatoric, epistemic, or none) along with confidence in the
  classification and recommended actions.

  ## Fields

  - `:uncertainty_type` - The type of uncertainty (:aleatoric, :epistemic, or :none)
  - `:confidence` - Confidence in the classification [0-1]
  - `:reasoning` - Human-readable explanation for the classification
  - `:suggested_action` - Recommended action based on uncertainty type
  - `:metadata` - Additional metadata

  ## Uncertainty Types

  - `:aleatoric` - Inherent uncertainty in the data (subjective, ambiguous, multiple valid answers)
  - `:epistemic` - Uncertainty due to lack of knowledge (out-of-domain, missing facts)
  - `:none` - No significant uncertainty (confident, factual)

  ## Usage

      # Create an uncertainty result
      {:ok, result} = UncertaintyResult.new(%{
        uncertainty_type: :aleatoric,
        confidence: 0.8,
        reasoning: "Query asks for subjective opinion"
      })

      # Check uncertainty type
      UncertaintyResult.aleatoric?(result)
      # => true

      UncertaintyResult.epistemic?(result)
      # => false

  """

  import Jido.AI.Accuracy.Helpers, only: [get_attr: 2, get_attr: 3]

  @type t :: %__MODULE__{
          uncertainty_type: uncertainty_type(),
          confidence: float(),
          reasoning: String.t() | nil,
          suggested_action: atom() | nil,
          metadata: map()
        }

  @type uncertainty_type :: :aleatoric | :epistemic | :none

  @uncertainty_types [:aleatoric, :epistemic, :none]

  defstruct [
    :uncertainty_type,
    :confidence,
    :reasoning,
    :suggested_action,
    metadata: %{}
  ]

  @doc """
  Creates a new UncertaintyResult from the given attributes.

  ## Parameters

  - `attrs` - Map with uncertainty result attributes:
    - `:uncertainty_type` (required) - The type of uncertainty
    - `:confidence` (optional) - Confidence in classification [0-1]
    - `:reasoning` (optional) - Explanation for classification
    - `:suggested_action` (optional) - Recommended action
    - `:metadata` (optional) - Additional metadata

  ## Returns

  `{:ok, result}` on success, `{:error, reason}` on validation failure.

  ## Examples

      iex> UncertaintyResult.new(%{uncertainty_type: :aleatoric})
      {:ok, %UncertaintyResult{uncertainty_type: :aleatoric, ...}}

      iex> UncertaintyResult.new(%{uncertainty_type: :invalid})
      {:error, :invalid_uncertainty_type}

  """
  @spec new(keyword() | map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_list(attrs) or is_map(attrs) do
    uncertainty_type = get_attr(attrs, :uncertainty_type)

    with :ok <- validate_uncertainty_type(uncertainty_type) do
      result = %__MODULE__{
        uncertainty_type: uncertainty_type,
        confidence: get_attr(attrs, :confidence),
        reasoning: get_attr(attrs, :reasoning),
        suggested_action: get_attr(attrs, :suggested_action),
        metadata: get_attr(attrs, :metadata, %{})
      }

      {:ok, result}
    end
  end

  @doc """
  Creates a new UncertaintyResult, raising on error.

  ## Examples

      iex> UncertaintyResult.new!(%{uncertainty_type: :aleatoric})
      %UncertaintyResult{uncertainty_type: :aleatoric}

  """
  @spec new!(keyword() | map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, result} -> result
      {:error, reason} -> raise ArgumentError, "Invalid UncertaintyResult: #{format_error(reason)}"
    end
  end

  @doc """
  Returns true if the uncertainty type is aleatoric.

  ## Examples

      iex> result = UncertaintyResult.new!(%{uncertainty_type: :aleatoric})
      iex> UncertaintyResult.aleatoric?(result)
      true

  """
  @spec aleatoric?(t()) :: boolean()
  def aleatoric?(%__MODULE__{uncertainty_type: :aleatoric}), do: true
  def aleatoric?(%__MODULE__{}), do: false

  @doc """
  Returns true if the uncertainty type is epistemic.

  ## Examples

      iex> result = UncertaintyResult.new!(%{uncertainty_type: :epistemic})
      iex> UncertaintyResult.epistemic?(result)
      true

  """
  @spec epistemic?(t()) :: boolean()
  def epistemic?(%__MODULE__{uncertainty_type: :epistemic}), do: true
  def epistemic?(%__MODULE__{}), do: false

  @doc """
  Returns true if there is no significant uncertainty.

  ## Examples

      iex> result = UncertaintyResult.new!(%{uncertainty_type: :none})
      iex> UncertaintyResult.certain?(result)
      true

  """
  @spec certain?(t()) :: boolean()
  def certain?(%__MODULE__{uncertainty_type: :none}), do: true
  def certain?(%__MODULE__{}), do: false

  @doc """
  Returns true if there is any uncertainty (aleatoric or epistemic).

  ## Examples

      iex> result = UncertaintyResult.new!(%{uncertainty_type: :aleatoric})
      iex> UncertaintyResult.uncertain?(result)
      true

  """
  @spec uncertain?(t()) :: boolean()
  def uncertain?(%__MODULE__{} = result), do: !certain?(result)

  @doc """
  Converts the result to a map for serialization.

  ## Examples

      iex> result = UncertaintyResult.new!(%{uncertainty_type: :aleatoric})
      iex> map = UncertaintyResult.to_map(result)
      iex> Map.has_key?(map, "uncertainty_type")
      true

  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = result) do
    result
    |> Map.from_struct()
    |> Enum.reject(fn {k, v} -> k == :__struct__ or is_nil(v) or v == %{} end)
    |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end)
  end

  @doc """
  Creates a result from a map (inverse of `to_map/1`).

  ## Examples

      iex> map = %{"uncertainty_type" => "aleatoric"}
      iex> {:ok, result} = UncertaintyResult.from_map(map)
      iex> result.uncertainty_type
      :aleatoric

  """
  @spec from_map(map()) :: {:ok, t()} | {:error, term()}
  def from_map(map) when is_map(map) do
    attrs =
      map
      |> Map.new(fn {k, v} -> {String.to_atom(k), convert_value(k, v)} end)

    new(attrs)
  end

  # Private functions

  defp validate_uncertainty_type(type) when type in @uncertainty_types, do: :ok
  defp validate_uncertainty_type(_), do: {:error, :invalid_uncertainty_type}

  # Convert values from string representation back to atoms
  # Note: When atom conversion fails (unknown atom), we keep the string value.
  # This allows partial deserialization and prevents data loss. The caller
  # should validate the result's uncertainty_type field after deserialization.
  defp convert_value("uncertainty_type", value) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> value
  end

  defp convert_value(_, value), do: value
  defp format_error(atom) when is_atom(atom), do: atom
  defp format_error(_), do: :invalid_attributes
end
