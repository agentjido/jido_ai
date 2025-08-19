defmodule Jido.Eval.Sample.SingleTurn do
  @moduledoc """
  Single-turn evaluation sample data structure.

  Represents a single interaction between a user and an AI system,
  including input, response, context, and evaluation criteria.

  ## Fields

  - `id`: Unique identifier for the sample
  - `user_input`: User's input message or string
  - `retrieved_contexts`: RAG-retrieved context strings
  - `reference_contexts`: Ground truth context strings
  - `response`: AI system's response message or string
  - `multi_responses`: Multiple response variants for comparison
  - `reference`: Expected/ground truth response
  - `rubrics`: Evaluation criteria as key-value pairs
  - `tags`: Sample-level metadata for categorization

  ## Examples

      iex> sample = %Jido.Eval.Sample.SingleTurn{
      ...>   id: "sample_001",
      ...>   user_input: "What is the capital of France?",
      ...>   response: "The capital of France is Paris.",
      ...>   reference: "Paris is the capital of France.",
      ...>   tags: %{"category" => "geography", "difficulty" => "easy"}
      ...> }
      iex> sample.id
      "sample_001"

  """
  use TypedStruct

  alias Jido.AI.Message

  typedstruct do
    @typedoc "A single-turn evaluation sample"

    field(:id, String.t() | nil, default: nil)
    field(:user_input, Message.t() | String.t() | nil, default: nil)
    field(:retrieved_contexts, [String.t()] | nil, default: nil)
    field(:reference_contexts, [String.t()] | nil, default: nil)
    field(:response, Message.t() | String.t() | nil, default: nil)
    field(:multi_responses, [String.t()] | nil, default: nil)
    field(:reference, String.t() | nil, default: nil)
    field(:rubrics, %{String.t() => String.t()} | nil, default: nil)
    field(:tags, %{String.t() => String.t()}, default: %{})
  end

  @doc """
  Creates a new single-turn sample with validation.

  ## Examples

      iex> {:ok, sample} = Jido.Eval.Sample.SingleTurn.new(%{
      ...>   user_input: "Hello",
      ...>   response: "Hi there!"
      ...> })
      iex> sample.user_input
      "Hello"

  """
  @spec new(map()) :: {:ok, t()} | {:error, String.t()}
  def new(attrs) when is_map(attrs) do
    sample = struct(__MODULE__, attrs)

    case validate(sample) do
      :ok -> {:ok, sample}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Validates a single-turn sample.

  Returns `:ok` if valid, or `{:error, reason}` if invalid.
  """
  @spec validate(t()) :: :ok | {:error, String.t()}
  def validate(%__MODULE__{} = sample) do
    cond do
      has_user_input_or_response?(sample) ->
        :ok

      true ->
        {:error, "Sample must have either user_input or response"}
    end
  end

  @doc """
  Converts string fields to Message structs where appropriate.

  ## Examples

      iex> sample = %Jido.Eval.Sample.SingleTurn{user_input: "Hello"}
      iex> converted = Jido.Eval.Sample.SingleTurn.to_messages(sample)
      iex> converted.user_input.role
      :user

  """
  @spec to_messages(t()) :: t()
  def to_messages(%__MODULE__{} = sample) do
    %{
      sample
      | user_input: string_to_message(sample.user_input, :user),
        response: string_to_message(sample.response, :assistant)
    }
  end

  @doc """
  Converts Message fields to strings where appropriate.

  ## Examples

      iex> message = %Jido.AI.Message{role: :user, content: "Hello"}
      iex> sample = %Jido.Eval.Sample.SingleTurn{user_input: message}
      iex> converted = Jido.Eval.Sample.SingleTurn.to_strings(sample)
      iex> converted.user_input
      "Hello"

  """
  @spec to_strings(t()) :: t()
  def to_strings(%__MODULE__{} = sample) do
    %{
      sample
      | user_input: message_to_string(sample.user_input),
        response: message_to_string(sample.response)
    }
  end

  @doc """
  Converts a sample to a map for serialization.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = sample) do
    sample
    |> Map.from_struct()
    |> Enum.filter(fn
      # Keep empty tags
      {:tags, %{}} -> true
      # Remove nil values
      {_key, nil} -> false
      # Keep everything else
      {_key, _value} -> true
    end)
    |> Map.new()
    |> convert_messages_to_maps()
  end

  @doc """
  Creates a sample from a map, with type conversion.
  """
  @spec from_map(map()) :: {:ok, t()} | {:error, String.t()}
  def from_map(map) when is_map(map) do
    converted_map =
      map
      |> convert_maps_to_messages()
      |> ensure_string_keys()

    new(converted_map)
  end

  # Private helper functions

  defp has_user_input_or_response?(%__MODULE__{user_input: nil, response: nil}), do: false
  defp has_user_input_or_response?(%__MODULE__{}), do: true

  defp string_to_message(nil, _role), do: nil
  defp string_to_message(%Message{} = message, _role), do: message

  defp string_to_message(content, role) when is_binary(content) do
    %Message{role: role, content: content}
  end

  defp message_to_string(nil), do: nil
  defp message_to_string(%Message{content: content}), do: content
  defp message_to_string(content) when is_binary(content), do: content

  defp convert_messages_to_maps(map) do
    map
    |> convert_field_to_map(:user_input)
    |> convert_field_to_map(:response)
  end

  defp convert_field_to_map(map, field) do
    case Map.get(map, field) do
      %Message{} = message -> Map.put(map, field, Map.from_struct(message))
      # Leave the map unchanged if not a Message
      _other -> map
    end
  end

  defp convert_maps_to_messages(map) do
    map
    |> convert_field_to_message(:user_input, :user)
    |> convert_field_to_message(:response, :assistant)
  end

  defp convert_field_to_message(map, field, _role) do
    case Map.get(map, field) do
      %{role: _, content: _} = message_map ->
        # Convert atom keys if they're strings
        converted_map =
          Map.new(message_map, fn
            {key, value} when is_binary(key) ->
              case key do
                "role" -> {:role, String.to_existing_atom(value)}
                "content" -> {:content, value}
                "name" -> {:name, value}
                "tool_call_id" -> {:tool_call_id, value}
                "tool_calls" -> {:tool_calls, value}
                "metadata" -> {:metadata, value}
                _ -> {String.to_atom(key), value}
              end

            {key, value} when is_atom(key) ->
              {key, value}
          end)

        message = struct(Message, converted_map)
        Map.put(map, field, message)

      content when is_binary(content) ->
        # Don't auto-convert strings to messages during deserialization
        # Let the user decide when to convert using to_messages/1
        Map.put(map, field, content)

      other ->
        Map.put(map, field, other)
    end
  end

  defp ensure_string_keys(map) do
    Map.new(map, fn
      {key, value} when is_atom(key) -> {key, value}
      {key, value} when is_binary(key) -> {String.to_existing_atom(key), value}
    end)
  rescue
    ArgumentError -> map
  end
end
