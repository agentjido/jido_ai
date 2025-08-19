defmodule Jido.Character.Personality.Behavior do
  @moduledoc """
  General patterns and response frameworks that adapt based on traits,
  current context, and emotional state.
  """
  use TypedEctoSchema
  import Ecto.Changeset

  @derive Inspect
  @derive Jason.Encoder
  @primary_key false
  typed_embedded_schema do
    field(:patterns, {:array, :map}, default: [])
    field(:response_frameworks, {:array, :map}, default: [])
    field(:current_context, :map)
    field(:emotional_state, :map)
  end

  def changeset(behavior \\ %__MODULE__{}, attrs) do
    behavior
    |> cast(attrs, [:patterns, :response_frameworks, :current_context, :emotional_state])
    |> validate_required([:patterns, :response_frameworks])
  end

  @spec template(map()) :: %__MODULE__{}
  def template(attrs \\ %{}) do
    %__MODULE__{
      patterns: [],
      response_frameworks: [],
      current_context: %{},
      emotional_state: %{}
    }
    |> Map.merge(attrs)
  end

  @doc """
  Updates the current context and emotional state
  Returns {:ok, updated_behavior} or {:error, changeset}
  """
  @spec update_state(t(), map(), map()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def update_state(behavior, context, emotional_state) do
    behavior
    |> changeset(%{current_context: context, emotional_state: emotional_state})
    |> apply_action(:update)
  end

  @doc """
  Adds a new pattern to the behavior's patterns list.
  """
  @spec add_pattern(t(), map()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def add_pattern(behavior, pattern) do
    updated_patterns = [pattern | behavior.patterns]

    behavior
    |> changeset(%{patterns: updated_patterns})
    |> apply_action(:update)
  end

  @doc """
  Adds a new response framework to the behavior's response_frameworks list.
  """
  @spec add_response_framework(t(), map()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def add_response_framework(behavior, framework) do
    updated_frameworks = [framework | behavior.response_frameworks]

    behavior
    |> changeset(%{response_frameworks: updated_frameworks})
    |> apply_action(:update)
  end
end
