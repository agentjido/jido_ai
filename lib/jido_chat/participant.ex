defmodule Jido.Chat.Participant do
  @moduledoc """
  A simple struct representing an ephemeral participant.

  This module provides a basic data structure for participants that don't require
  process state. For stateful participants, see `Jido.Chat.Participant.Stateful`.
  """
  use TypedStruct

  typedstruct do
    field(:id, String.t(), enforce: true)
    field(:display_name, String.t())
    field(:type, :human | :agent, enforce: true, default: :human)
    field(:metadata, map(), default: %{})
    # Process ID for direct message delivery
    field(:pid, pid())
    # Custom dispatch configuration for signal bus
    field(:dispatch, term())
  end

  @doc """
  Creates a new participant struct.

  ## Parameters
    * id - Required. Unique identifier for the participant
    * opts - Optional keyword list of options:
      * :display_name - Optional display name (defaults to id)
      * :type - Optional type (defaults to :human)
      * :metadata - Optional map of metadata (defaults to empty map)
      * :pid - Optional process ID for direct message delivery
      * :dispatch - Optional custom dispatch configuration for signal bus

  ## Examples

      iex> alias Jido.Chat.Participant
      iex> Participant.new("user123", display_name: "Alice")
      {:ok, %Jido.Chat.Participant{id: "user123", display_name: "Alice", metadata: %{}}}

      iex> alias Jido.Chat.Participant
      iex> Participant.new("user456", metadata: %{role: "admin"})
      {:ok, %Jido.Chat.Participant{id: "user456", display_name: "user456", metadata: %{role: "admin"}}}
  """
  @spec new(id :: String.t(), opts :: keyword()) :: {:ok, t()}
  def new(id, opts \\ []) when is_binary(id) do
    {:ok,
     %__MODULE__{
       id: id,
       display_name: Keyword.get(opts, :display_name, id),
       type: Keyword.get(opts, :type, :human),
       metadata: Keyword.get(opts, :metadata, %{}),
       pid: Keyword.get(opts, :pid),
       dispatch: Keyword.get(opts, :dispatch)
     }}
  end

  @doc """
  Same as `new/2` but returns the struct directly.
  """
  @spec new!(id :: String.t(), opts :: keyword()) :: t()
  def new!(id, opts \\ []) when is_binary(id) do
    case new(id, opts) do
      {:ok, participant} -> participant
    end
  end

  @doc """
  Returns the display name for a participant.
  If no display name is set, returns the participant's ID.
  """
  @spec display_name(t()) :: String.t()
  def display_name(%__MODULE__{display_name: nil, id: id}), do: id
  def display_name(%__MODULE__{display_name: name}), do: name
end
