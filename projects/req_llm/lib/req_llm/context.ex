defmodule ReqLLM.Context do
  @moduledoc """
  Context represents a conversation history as a collection of messages.

  Provides canonical message constructor functions that can be imported
  for clean, readable message creation.

  ## Example

      import ReqLLM.Context
      
      context = Context.new([
        system("You are a helpful assistant"),
        user("What's the weather like?"),
        assistant("I'll check that for you")
      ])
      
      Context.validate!(context)
  """

  use TypedStruct

  alias ReqLLM.Message
  alias ReqLLM.Message.ContentPart

  typedstruct enforce: true do
    field(:messages, [Message.t()], default: [])
  end

  @spec new([Message.t()]) :: t()
  def new(list \\ []), do: %__MODULE__{messages: list}

  @spec to_list(t()) :: [Message.t()]
  def to_list(%__MODULE__{messages: msgs}), do: msgs

  @spec text(atom(), String.t(), map()) :: Message.t()
  def text(role, content, meta \\ %{}) when is_binary(content) do
    %Message{
      role: role,
      content: [ContentPart.text(content)],
      metadata: meta
    }
  end

  @spec with_image(atom(), String.t(), String.t(), map()) :: Message.t()
  def with_image(role, text, url, meta \\ %{}) do
    %Message{
      role: role,
      content: [ContentPart.text(text), ContentPart.image_url(url)],
      metadata: meta
    }
  end

  # Message constructor functions that support both strings and content part arrays
  @spec user([ContentPart.t()] | String.t(), map()) :: Message.t()
  def user(content, meta \\ %{})
  def user(content, meta) when is_binary(content), do: text(:user, content, meta)

  def user(content, meta) when is_list(content) do
    %Message{role: :user, content: content, metadata: meta}
  end

  @spec assistant([ContentPart.t()] | String.t(), map()) :: Message.t()
  def assistant(content, meta \\ %{})
  def assistant(content, meta) when is_binary(content), do: text(:assistant, content, meta)

  def assistant(content, meta) when is_list(content) do
    %Message{role: :assistant, content: content, metadata: meta}
  end

  @spec system([ContentPart.t()] | String.t(), map()) :: Message.t()
  def system(content, meta \\ %{})
  def system(content, meta) when is_binary(content), do: text(:system, content, meta)

  def system(content, meta) when is_list(content) do
    %Message{role: :system, content: content, metadata: meta}
  end

  @spec new(atom(), [ContentPart.t()], map()) :: Message.t()
  def new(role, content, meta \\ %{}) when is_list(content) do
    %Message{role: role, content: content, metadata: meta}
  end

  @spec validate(t()) :: {:ok, t()} | {:error, String.t()}
  def validate(%__MODULE__{messages: msgs} = context) do
    with :ok <- validate_system_messages(msgs),
         :ok <- validate_message_structure(msgs) do
      {:ok, context}
    end
  end

  @spec validate!(t()) :: t()
  def validate!(context) do
    case validate(context) do
      {:ok, context} -> context
      {:error, reason} -> raise ArgumentError, "Invalid context: #{reason}"
    end
  end

  @doc """
  Wrap a context with provider-specific tagged struct.

  Takes a `ReqLLM.Context` and `ReqLLM.Model` and wraps the context
  in the appropriate provider-specific struct for encoding/decoding.

  ## Parameters

    * `context` - A `ReqLLM.Context` to wrap
    * `model` - A `ReqLLM.Model` indicating the provider

  ## Returns

    * Provider-specific tagged struct ready for encoding

  ## Examples

      context = ReqLLM.Context.new([ReqLLM.Context.user("Hello")])
      model = ReqLLM.Model.from("anthropic:claude-3-haiku-20240307")
      tagged = ReqLLM.Context.wrap(context, model)
      #=> %ReqLLM.Providers.Anthropic{context: context}

  """
  @spec wrap(t(), ReqLLM.Model.t()) :: term()
  def wrap(%__MODULE__{} = ctx, %ReqLLM.Model{provider: provider_atom}) do
    {:ok, provider_mod} = ReqLLM.provider(provider_atom)
    provider_mod.wrap_context(ctx)
  end

  defp validate_system_messages(messages) do
    system_count = Enum.count(messages, &(&1.role == :system))

    case system_count do
      0 -> {:error, "Context should have exactly one system message, found 0"}
      1 -> :ok
      n -> {:error, "Context should have exactly one system message, found #{n}"}
    end
  end

  defp validate_message_structure(messages) do
    case Enum.all?(messages, &Message.valid?/1) do
      true -> :ok
      false -> {:error, "Context contains invalid messages"}
    end
  end

  defimpl Inspect do
    def inspect(%{messages: msgs}, opts) do
      roles =
        msgs
        |> Enum.map(& &1.role)
        |> Enum.join(",")

      Inspect.Algebra.concat([
        "#Context<",
        Inspect.Algebra.to_doc(length(msgs), opts),
        " msgs: ",
        roles,
        ">"
      ])
    end
  end

  defimpl Enumerable do
    def count(%ReqLLM.Context{messages: messages}), do: {:ok, length(messages)}

    def member?(%ReqLLM.Context{messages: messages}, element) do
      {:ok, Enum.member?(messages, element)}
    end

    def reduce(%ReqLLM.Context{messages: messages}, acc, fun) do
      Enumerable.reduce(messages, acc, fun)
    end

    def slice(%ReqLLM.Context{messages: messages}) do
      {:ok, length(messages), &Enum.slice(messages, &1, &2)}
    end
  end

  defimpl Collectable do
    def into(%ReqLLM.Context{messages: messages}) do
      collector = fn
        list, {:cont, message} -> [message | list]
        list, :done -> %ReqLLM.Context{messages: Enum.reverse(list, messages)}
        _list, :halt -> :ok
      end

      {[], collector}
    end
  end
end
