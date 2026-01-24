defmodule Jido.AI.GEPA.PromptVariant do
  @moduledoc """
  Represents a prompt variant in the GEPA optimization process.

  A PromptVariant holds a prompt template along with its evaluation metrics
  and lineage information for tracking evolution across generations.

  ## Fields

  - `id` - Unique identifier for this variant
  - `template` - The prompt template (string or structured map)
  - `generation` - Which generation this variant belongs to (0 = seed)
  - `parents` - List of parent variant IDs for lineage tracking
  - `accuracy` - Evaluation accuracy score (0.0-1.0), nil if not evaluated
  - `token_cost` - Total tokens used during evaluation, nil if not evaluated
  - `latency_ms` - Average latency per task in milliseconds (optional)
  - `metadata` - Additional notes, tags, or custom data

  ## Usage

      # Create a new seed variant
      variant = PromptVariant.new!(%{
        template: "You are a helpful assistant...",
        generation: 0
      })

      # Update after evaluation
      variant = PromptVariant.update_metrics(variant, %{
        accuracy: 0.85,
        token_cost: 1500,
        latency_ms: 250
      })

      # Check if evaluated
      PromptVariant.evaluated?(variant)
      #=> true
  """

  @type t :: %__MODULE__{
          id: String.t(),
          template: String.t() | map(),
          generation: non_neg_integer(),
          parents: [String.t()],
          accuracy: float() | nil,
          token_cost: non_neg_integer() | nil,
          latency_ms: non_neg_integer() | nil,
          metadata: map()
        }

  @enforce_keys [:id, :template]
  defstruct [
    :id,
    :template,
    generation: 0,
    parents: [],
    accuracy: nil,
    token_cost: nil,
    latency_ms: nil,
    metadata: %{}
  ]

  @doc """
  Creates a new PromptVariant from the given attributes.

  ## Parameters

  - `attrs` - Map with variant attributes:
    - `:template` (required) - The prompt template
    - `:id` (optional) - Unique ID, auto-generated if not provided
    - `:generation` (optional) - Generation number, defaults to 0
    - `:parents` (optional) - List of parent IDs, defaults to []
    - `:metadata` (optional) - Additional data, defaults to %{}

  ## Returns

  `{:ok, variant}` on success, `{:error, reason}` on failure.

  ## Examples

      iex> PromptVariant.new(%{template: "Be helpful"})
      {:ok, %PromptVariant{template: "Be helpful", generation: 0, ...}}

      iex> PromptVariant.new(%{})
      {:error, :template_required}
  """
  @spec new(map()) :: {:ok, t()} | {:error, atom()}
  def new(attrs) when is_map(attrs) do
    case validate_attrs(attrs) do
      :ok ->
        variant = build_variant(attrs)
        {:ok, variant}

      {:error, _} = error ->
        error
    end
  end

  def new(_), do: {:error, :invalid_attrs}

  @doc """
  Creates a new PromptVariant, raising on error.

  Same as `new/1` but raises `ArgumentError` on invalid input.

  ## Examples

      iex> PromptVariant.new!(%{template: "Be helpful"})
      %PromptVariant{template: "Be helpful", ...}

      iex> PromptVariant.new!(%{})
      ** (ArgumentError) template is required
  """
  @spec new!(map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, variant} -> variant
      {:error, reason} -> raise ArgumentError, error_message(reason)
    end
  end

  @doc """
  Updates the metrics of a variant after evaluation.

  ## Parameters

  - `variant` - The variant to update
  - `metrics` - Map with metric values:
    - `:accuracy` - Accuracy score (0.0-1.0)
    - `:token_cost` - Total tokens used
    - `:latency_ms` - Average latency in ms (optional)

  ## Returns

  Updated variant struct.

  ## Examples

      iex> variant = PromptVariant.new!(%{template: "test"})
      iex> PromptVariant.update_metrics(variant, %{accuracy: 0.9, token_cost: 1000})
      %PromptVariant{accuracy: 0.9, token_cost: 1000, ...}
  """
  @spec update_metrics(t(), map()) :: t()
  def update_metrics(%__MODULE__{} = variant, metrics) when is_map(metrics) do
    accuracy = Map.get(metrics, :accuracy)
    token_cost = Map.get(metrics, :token_cost)
    latency_ms = Map.get(metrics, :latency_ms)

    %{
      variant
      | accuracy: validate_accuracy(accuracy),
        token_cost: validate_token_cost(token_cost),
        latency_ms: validate_latency(latency_ms)
    }
  end

  @doc """
  Checks if a variant has been evaluated.

  A variant is considered evaluated if it has both accuracy and token_cost set.

  ## Examples

      iex> variant = PromptVariant.new!(%{template: "test"})
      iex> PromptVariant.evaluated?(variant)
      false

      iex> variant = PromptVariant.update_metrics(variant, %{accuracy: 0.9, token_cost: 100})
      iex> PromptVariant.evaluated?(variant)
      true
  """
  @spec evaluated?(t()) :: boolean()
  def evaluated?(%__MODULE__{accuracy: acc, token_cost: cost}) do
    not is_nil(acc) and not is_nil(cost)
  end

  @doc """
  Creates a child variant from this variant with a new template.

  The child inherits the parent's ID in its parents list and
  increments the generation number.

  ## Parameters

  - `parent` - The parent variant
  - `new_template` - The mutated template for the child

  ## Returns

  A new variant struct with lineage information.

  ## Examples

      iex> parent = PromptVariant.new!(%{template: "v1", generation: 0})
      iex> child = PromptVariant.create_child(parent, "v2 improved")
      iex> child.generation
      1
      iex> child.parents
      [parent.id]
  """
  @spec create_child(t(), String.t() | map()) :: t()
  def create_child(%__MODULE__{} = parent, new_template) do
    new!(%{
      template: new_template,
      generation: parent.generation + 1,
      parents: [parent.id],
      metadata: Map.get(parent.metadata, :inherited, %{})
    })
  end

  @doc """
  Compares two variants by a specific metric.

  Returns `:gt`, `:lt`, or `:eq` based on the comparison.
  For accuracy, higher is better. For token_cost and latency_ms, lower is better.

  ## Parameters

  - `v1` - First variant
  - `v2` - Second variant
  - `metric` - The metric to compare (`:accuracy`, `:token_cost`, `:latency_ms`)

  ## Examples

      iex> v1 = %PromptVariant{accuracy: 0.9, token_cost: 100}
      iex> v2 = %PromptVariant{accuracy: 0.8, token_cost: 100}
      iex> PromptVariant.compare(v1, v2, :accuracy)
      :gt
  """
  @spec compare(t(), t(), atom()) :: :gt | :lt | :eq
  def compare(%__MODULE__{} = v1, %__MODULE__{} = v2, metric) do
    val1 = Map.get(v1, metric)
    val2 = Map.get(v2, metric)

    cond do
      is_nil(val1) or is_nil(val2) -> :eq
      val1 == val2 -> :eq
      metric == :accuracy -> if val1 > val2, do: :gt, else: :lt
      # For cost/latency, lower is better
      true -> if val1 < val2, do: :gt, else: :lt
    end
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp validate_attrs(attrs) do
    cond do
      not Map.has_key?(attrs, :template) -> {:error, :template_required}
      not valid_template?(attrs.template) -> {:error, :invalid_template}
      true -> :ok
    end
  end

  defp valid_template?(template) when is_binary(template), do: String.length(template) > 0
  defp valid_template?(template) when is_map(template), do: map_size(template) > 0
  defp valid_template?(_), do: false

  defp build_variant(attrs) do
    %__MODULE__{
      id: Map.get(attrs, :id, generate_id()),
      template: attrs.template,
      generation: Map.get(attrs, :generation, 0),
      parents: Map.get(attrs, :parents, []),
      accuracy: nil,
      token_cost: nil,
      latency_ms: nil,
      metadata: Map.get(attrs, :metadata, %{})
    }
  end

  defp generate_id do
    "pv_#{Jido.Util.generate_id()}"
  end

  defp validate_accuracy(nil), do: nil
  defp validate_accuracy(acc) when is_number(acc), do: max(0.0, min(1.0, acc / 1))
  defp validate_accuracy(_), do: nil

  defp validate_token_cost(nil), do: nil
  defp validate_token_cost(cost) when is_integer(cost) and cost >= 0, do: cost
  defp validate_token_cost(cost) when is_number(cost), do: round(max(0, cost))
  defp validate_token_cost(_), do: nil

  defp validate_latency(nil), do: nil
  defp validate_latency(lat) when is_integer(lat) and lat >= 0, do: lat
  defp validate_latency(lat) when is_number(lat), do: round(max(0, lat))
  defp validate_latency(_), do: nil

  defp error_message(:template_required), do: "template is required"
  defp error_message(:invalid_template), do: "template must be a non-empty string or map"
  defp error_message(:invalid_attrs), do: "attrs must be a map"
end
