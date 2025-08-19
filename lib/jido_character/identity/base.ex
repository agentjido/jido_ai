defmodule Jido.Character.Identity.Base do
  @moduledoc """
  Core, unchanging identity attributes that form the foundation of a character's identity.
  """
  use TypedEctoSchema
  import Ecto.Changeset

  @derive Inspect
  @derive Jason.Encoder
  @primary_key false
  typed_embedded_schema do
    field(:unique_id, :string)
    field(:creation_timestamp, :utc_datetime_usec)
    field(:character_type, :string)
    field(:version, :integer)
    field(:namespace, :string)
    field(:tags, {:array, :string})
  end

  def changeset(base \\ %__MODULE__{}, attrs) do
    base
    |> cast(attrs, [:unique_id, :creation_timestamp, :character_type, :version, :namespace, :tags])
    |> validate_required([:unique_id, :creation_timestamp, :version])
    |> validate_inclusion(:character_type, ["npc", "player", "system"])
    |> validate_number(:version, greater_than: 0)
    |> validate_length(:tags, max: 20)
  end

  @spec template(map()) :: %__MODULE__{}
  def template(attrs \\ %{}) do
    %__MODULE__{
      unique_id: UUID.uuid4(),
      creation_timestamp: DateTime.utc_now(),
      character_type: "npc",
      version: 1,
      namespace: "default",
      tags: []
    }
    |> Map.merge(attrs)
  end

  @doc """
  Updates the character type if it's valid.
  Returns {:ok, updated_base} or {:error, changeset}
  """
  @spec update_character_type(t(), String.t()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def update_character_type(base, new_type) do
    base
    |> changeset(%{character_type: new_type})
    |> apply_action(:update)
  end

  @doc """
  Adds a tag to the character's tags list if not already present
  and if it wouldn't exceed the maximum number of tags.
  """
  @spec add_tag(t(), String.t()) :: {:ok, t()} | {:error, Ecto.Changeset.t() | :tag_exists}
  def add_tag(base, tag) do
    if tag in base.tags do
      {:error, :tag_exists}
    else
      base
      |> changeset(%{tags: [tag | base.tags]})
      |> apply_action(:update)
    end
  end

  @doc """
  Removes a tag from the character's tags list.
  """
  @spec remove_tag(t(), String.t()) :: {:ok, t()}
  def remove_tag(base, tag) do
    {:ok, %{base | tags: Enum.reject(base.tags, &(&1 == tag))}}
  end

  @doc """
  Updates the namespace of the character.
  """
  @spec update_namespace(t(), String.t()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def update_namespace(base, new_namespace) do
    base
    |> changeset(%{namespace: new_namespace})
    |> apply_action(:update)
  end

  @doc """
  Increments the version number by 1.
  """
  @spec increment_version(t()) :: {:ok, t()}
  def increment_version(base) do
    {:ok, %{base | version: base.version + 1}}
  end

  @doc """
  Returns true if the base identity matches all the given tags.
  """
  @spec matches_tags?(t(), list(String.t())) :: boolean()
  def matches_tags?(base, tags) do
    Enum.all?(tags, &(&1 in base.tags))
  end
end
