defmodule Jido.Character.Identity do
  @moduledoc """
  Identity schema defining core identity attributes and validation rules.
  """
  use TypedEctoSchema
  use Ecto.Schema
  import Ecto.Changeset

  alias Jido.Character.Identity.{Base, Style, Profile}

  @type character :: Jido.Character.t()
  @type error :: Jido.Character.error()

  @derive Inspect
  @derive Jason.Encoder
  @primary_key false
  typed_embedded_schema do
    # Core identity fields from current implementation
    field(:username, :string, default: "")
    field(:display_name, :string, default: "")
    field(:avatar_url, :string, default: "")
    field(:interests, {:array, :string}, default: [])

    # New embedded schemas
    embeds_one(:base, Base, on_replace: :update)
    embeds_one(:style, Style, on_replace: :update)
    embeds_one(:profile, Profile, on_replace: :update)
  end

  def changeset(identity \\ %__MODULE__{}, attrs) do
    identity
    |> cast(attrs, [:username, :display_name, :avatar_url, :interests])
    |> cast_embed(:base)
    |> cast_embed(:style)
    |> cast_embed(:profile)
    |> validate_required([:username, :base])
    |> validate_length(:username, min: 3, max: 30)
    |> validate_format(:username, ~r/^[a-zA-Z0-9_]+$/)
    |> validate_length(:display_name, max: 255)
    |> validate_length(:interests, max: 10)
  end

  def template(attrs \\ %{}) do
    %__MODULE__{
      username: nil,
      display_name: nil,
      avatar_url: nil,
      interests: [],
      base: Base.template(),
      style: Style.template(),
      profile: Profile.template()
    }
    |> Map.merge(attrs)
  end

  @doc "Updates multiple identity fields at once"
  @spec update_identity(character() | {:ok, character()}, map()) :: {:ok, character()} | error()
  def update_identity({:ok, character}, attrs), do: update_identity(character, attrs)

  def update_identity(%Jido.Character{} = character, attrs) when is_map(attrs) do
    Jido.Character.update(character, %{identity: attrs})
  end

  @doc "Updates the username"
  @spec set_username(character(), String.t()) :: {:ok, character()} | error()
  def set_username(%Jido.Character{} = character, username) do
    update_identity(character, %{username: username})
  end

  @doc "Updates display name"
  @spec set_display_name(character(), String.t()) :: {:ok, character()} | error()
  def set_display_name(%Jido.Character{} = character, display_name) do
    update_identity(character, %{display_name: display_name})
  end

  @doc "Updates avatar URL"
  @spec set_avatar_url(character(), String.t()) :: {:ok, character()} | error()
  def set_avatar_url(%Jido.Character{} = character, avatar_url) do
    update_identity(character, %{avatar_url: avatar_url})
  end

  @doc "Updates interests list"
  @spec set_interests(character(), list(String.t())) :: {:ok, character()} | error()
  def set_interests(%Jido.Character{} = character, interests) when is_list(interests) do
    update_identity(character, %{interests: interests})
  end

  @doc """
  Adds an interest to the list.
  Returns error if adding would exceed the 10-item limit.
  """
  @spec add_interest(character(), String.t()) :: {:ok, character()} | error()
  def add_interest(%Jido.Character{} = character, interest) do
    current_interests = get_interests(character)

    # Don't add if it would exceed 10 items
    if length(current_interests) >= 10 do
      # Create a changeset with nested error structure
      {:error,
       Jido.Character.changeset(character, %{
         identity: %{interests: List.duplicate("interest", 11)}
       })}
    else
      # Only add if not already present
      case interest in current_interests do
        true -> {:ok, character}
        false -> set_interests(character, [interest | current_interests])
      end
    end
  end

  @doc "Removes an interest from the list"
  @spec remove_interest(character(), String.t()) :: {:ok, character()} | error()
  def remove_interest(%Jido.Character{} = character, interest) do
    current_interests = get_interests(character)
    updated_interests = Enum.reject(current_interests, &(&1 == interest))
    set_interests(character, updated_interests)
  end

  @doc "Gets the username"
  @spec get_username(character()) :: String.t() | nil
  def get_username(%Jido.Character{identity: %{username: username}}), do: username

  @doc "Gets the display name"
  @spec get_display_name(character()) :: String.t() | nil
  def get_display_name(%Jido.Character{identity: %{display_name: display_name}}), do: display_name

  @doc "Gets the avatar URL"
  @spec get_avatar_url(character()) :: String.t() | nil
  def get_avatar_url(%Jido.Character{identity: %{avatar_url: avatar_url}}), do: avatar_url

  @doc "Gets the interests list"
  @spec get_interests(character()) :: list(String.t())
  def get_interests(%Jido.Character{identity: %{interests: interests}}) when is_list(interests),
    do: interests

  def get_interests(_), do: []
end

defimpl Jido.Character.Composer, for: Jido.Character.Identity do
  import Jido.Character.Helpers
  alias Jido.Character.Identity

  def compose(%Identity{base: base, style: style, profile: profile}, _opts) do
    profile_text = profile_to_text(profile)
    style_text = style_to_text(style)

    composed = """
    #{add_section_header("Identity", base_to_text(base))}
    #{if style_text != "", do: add_section_header("Style", style_text)}
    #{if profile_text != "", do: add_section_header("Profile", profile_text)}
    """

    {:ok, String.trim(composed)}
  end

  defp base_to_text(%{name: name} = base) when not is_nil(name) do
    "#{name} is #{base.description}"
  end

  defp style_to_text(%{expressions: expressions}) when length(expressions) > 0 do
    expressions
    |> random_sample(3)
    |> Enum.join("\n")
  end

  defp style_to_text(_), do: ""

  defp profile_to_text(%{status: status}) when not is_nil(status), do: status
  defp profile_to_text(_), do: ""
end
