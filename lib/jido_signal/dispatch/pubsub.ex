defmodule Jido.Signal.Dispatch.PubSub do
  @moduledoc """
  An adapter for dispatching signals through Phoenix.PubSub.

  This adapter implements the `Jido.Signal.Dispatch.Adapter` behaviour and provides
  functionality to broadcast signals through Phoenix.PubSub to all subscribers of a
  specific topic. It integrates with Phoenix's pub/sub system for distributed
  message broadcasting.

  ## Configuration Options

  * `:target` - (required) An atom specifying the PubSub server name
  * `:topic` - (required) A string specifying the topic to broadcast on

  ## Phoenix.PubSub Integration

  The adapter uses `Phoenix.PubSub.broadcast/3` to:
  * Broadcast signals to all subscribers of a topic
  * Handle distributed message delivery across nodes
  * Manage subscription-based message routing

  ## Examples

      # Basic usage
      config = {:pubsub, [
        target: :my_app_pubsub,
        topic: "events"
      ]}

      # Using with specific event topics
      config = {:pubsub, [
        target: :my_app_pubsub,
        topic: "user:123:events"
      ]}

  ## Error Handling

  The adapter handles these error conditions:

  * `:pubsub_not_found` - The target PubSub server is not running
  * Other errors from the Phoenix.PubSub system

  ## Notes

  * Ensure the PubSub server is started in your application supervision tree
  * Topics can be any string, but consider using consistent naming patterns
  * Messages are broadcast to all subscribers, so consider message volume
  """

  @behaviour Jido.Signal.Dispatch.Adapter

  @type delivery_target :: atom()
  @type delivery_opts :: [
          target: delivery_target(),
          topic: String.t()
        ]
  @type delivery_error ::
          :pubsub_not_found
          | term()

  @impl Jido.Signal.Dispatch.Adapter
  @doc """
  Validates the PubSub adapter configuration options.

  ## Parameters

  * `opts` - Keyword list of options to validate

  ## Options

  * `:target` - Must be an atom representing the PubSub server name
  * `:topic` - Must be a string

  ## Returns

  * `{:ok, validated_opts}` - Options are valid
  * `{:error, reason}` - Options are invalid with string reason
  """
  @spec validate_opts(Keyword.t()) :: {:ok, Keyword.t()} | {:error, term()}
  def validate_opts(opts) do
    with {:ok, target} <- validate_target(Keyword.get(opts, :target)),
         {:ok, topic} <- validate_topic(Keyword.get(opts, :topic)) do
      {:ok,
       opts
       |> Keyword.put(:target, target)
       |> Keyword.put(:topic, topic)}
    end
  end

  @impl Jido.Signal.Dispatch.Adapter
  @doc """
  Broadcasts a signal through Phoenix.PubSub.

  ## Parameters

  * `signal` - The signal to broadcast
  * `opts` - Validated options from `validate_opts/1`

  ## Options

  * `:target` - (required) Atom identifying the PubSub server
  * `:topic` - (required) String topic to broadcast on

  ## Returns

  * `:ok` - Signal broadcast successfully
  * `{:error, :pubsub_not_found}` - PubSub server not found
  * `{:error, reason}` - Other broadcast failure
  """
  @spec deliver(Jido.Signal.t(), delivery_opts()) ::
          :ok | {:error, delivery_error()}
  def deliver(signal, opts) do
    target = Keyword.fetch!(opts, :target)
    topic = Keyword.fetch!(opts, :topic)

    try do
      Phoenix.PubSub.broadcast(target, topic, signal)
      :ok
    rescue
      ArgumentError -> {:error, :pubsub_not_found}
    catch
      :exit, {:noproc, _} -> {:error, :pubsub_not_found}
      :exit, reason -> {:error, reason}
    end
  end

  # Private helper to validate the target PubSub server
  defp validate_target(name) when is_atom(name) and not is_nil(name), do: {:ok, name}
  defp validate_target(_), do: {:error, "target must be an atom"}

  # Private helper to validate the topic string
  defp validate_topic(topic) when is_binary(topic) and not is_nil(topic), do: {:ok, topic}
  defp validate_topic(_), do: {:error, "topic must be a string"}
end
