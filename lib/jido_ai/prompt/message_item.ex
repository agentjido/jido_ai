defmodule Jido.AI.Prompt.MessageItem do
  @moduledoc """
  Represents a single message item within a prompt.

  Each message has a role (system, user, assistant, function) and content.
  The content can be either a raw string, an EEx template to be rendered,
  or a list of content parts for rich media support.
  """

  use TypedStruct

  typedstruct do
    @typedoc "A message item within a prompt"

    # role can be :system, :assistant, :user, :function, etc.
    field :role, atom(), default: :user

    # Either a raw string, an EEx template, or a list of content parts
    field :content, String.t() | list(), default: ""

    # Indicates whether the content is a template or plain text
    field :engine, :eex | :none, default: :none

    # Optional name field for function calling or other uses
    field :name, String.t(), default: nil
  end

  @doc """
  Creates a new MessageItem struct.

  ## Examples

      iex> Jido.AI.Prompt.MessageItem.new(%{role: :user, content: "Hello"})
      %Jido.AI.Prompt.MessageItem{role: :user, content: "Hello", engine: :none}

      iex> Jido.AI.Prompt.MessageItem.new(%{role: :system, content: "You are <%= @assistant_type %>", engine: :eex})
      %Jido.AI.Prompt.MessageItem{role: :system, content: "You are <%= @assistant_type %>", engine: :eex}
  """
  def new(attrs) when is_map(attrs) do
    struct(__MODULE__, attrs)
  end

  @doc """
  Creates a new MessageItem struct from a map with string keys.

  This is useful when creating message items from JSON or other external sources.

  ## Examples

      iex> Jido.AI.Prompt.MessageItem.from_map(%{"role" => "user", "content" => "Hello"})
      %Jido.AI.Prompt.MessageItem{role: :user, content: "Hello", engine: :none}
  """
  def from_map(%{"role" => role, "content" => content} = map) do
    engine = Map.get(map, "engine", :none)
    name = Map.get(map, "name")

    new(%{
      role: String.to_atom(role),
      content: content,
      engine: engine,
      name: name
    })
  end

  @doc """
  Creates a new text content part.

  ## Examples

      iex> Jido.AI.Prompt.MessageItem.text_part("Hello")
      %{type: :text, text: "Hello"}
  """
  def text_part(text) when is_binary(text) do
    %{type: :text, text: text}
  end

  @doc """
  Creates a new image content part.

  ## Examples

      iex> Jido.AI.Prompt.MessageItem.image_part("https://example.com/image.jpg")
      %{type: :image_url, image_url: "https://example.com/image.jpg"}
  """
  def image_part(url) when is_binary(url) do
    %{type: :image_url, image_url: url}
  end

  @doc """
  Creates a new file content part.

  ## Examples

      iex> Jido.AI.Prompt.MessageItem.file_part("https://example.com/document.pdf")
      %{type: :file_url, file_url: "https://example.com/document.pdf"}
  """
  def file_part(url) when is_binary(url) do
    %{type: :file_url, file_url: url}
  end

  @doc """
  Creates a new MessageItem with multi-part content.

  ## Examples

      iex> Jido.AI.Prompt.MessageItem.new_multipart(:user, [
      ...>   Jido.AI.Prompt.MessageItem.text_part("Check out this image:"),
      ...>   Jido.AI.Prompt.MessageItem.image_part("https://example.com/image.jpg")
      ...> ])
      %Jido.AI.Prompt.MessageItem{role: :user, content: [
        %{type: :text, text: "Check out this image:"},
        %{type: :image_url, image_url: "https://example.com/image.jpg"}
      ], engine: :none}
  """
  def new_multipart(role, parts) when is_atom(role) and is_list(parts) do
    new(%{role: role, content: parts})
  end
end
