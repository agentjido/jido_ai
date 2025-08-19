defmodule Jido.Character.Personality.Expression do
  @moduledoc """
  Immediate outward manifestation of personality, influenced by style,
  context, and emotional state.
  """
  use TypedEctoSchema
  import Ecto.Changeset

  @valid_tones [:formal, :casual, :friendly, :professional, :playful]

  @derive {Jason.Encoder, except: []}
  @primary_key false
  typed_embedded_schema do
    field(:current_tone, Ecto.Enum, values: @valid_tones, default: :casual)
    field(:style_overrides, :map, default: %{})
    field(:active_filters, {:array, :string}, default: [])
  end

  @spec template(map()) :: %__MODULE__{}
  def template(attrs \\ %{}) do
    %__MODULE__{
      current_tone: :casual,
      style_overrides: %{},
      active_filters: []
    }
    |> Map.merge(attrs)
  end

  def changeset(expression \\ %__MODULE__{}, attrs) do
    attrs = if Keyword.keyword?(attrs), do: Map.new(attrs), else: attrs

    expression
    |> cast(attrs, [:current_tone, :style_overrides, :active_filters])
    |> validate_inclusion(:current_tone, @valid_tones)
    |> validate_cast_active_filters()
  end

  def new(opts \\ []) do
    attrs =
      opts
      |> Enum.into(%{})
      |> maybe_convert_filters()

    %__MODULE__{}
    |> changeset(attrs)
    |> apply_changes()
  end

  @doc """
  Updates the current tone of expression
  """
  def set_tone(%__MODULE__{} = expression, tone) when tone in @valid_tones do
    changeset(expression, %{current_tone: tone})
    |> apply_changes()
  end

  @doc """
  Adds a filter to the active filters list
  """
  def add_filter(%__MODULE__{} = expression, filter) when is_atom(filter) do
    new_filters = [to_string(filter) | expression.active_filters]

    changeset(expression, %{active_filters: new_filters})
    |> apply_changes()
  end

  @doc """
  Gets the active filters as atoms
  """
  def get_filters(%__MODULE__{active_filters: filters}) do
    Enum.map(filters, &String.to_existing_atom/1)
  end

  # Private Functions

  defp maybe_convert_filters(%{active_filters: filters} = attrs) when is_list(filters) do
    %{attrs | active_filters: Enum.map(filters, &to_string/1)}
  end

  defp maybe_convert_filters(attrs), do: attrs

  defp validate_cast_active_filters(changeset) do
    case get_change(changeset, :active_filters) do
      nil ->
        changeset

      filters ->
        if Enum.all?(filters, &is_binary/1) do
          changeset
        else
          add_error(changeset, :active_filters, "must be a list of strings")
        end
    end
  end
end
