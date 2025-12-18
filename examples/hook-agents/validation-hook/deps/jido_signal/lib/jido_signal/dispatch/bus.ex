# defmodule Jido.Signal.Dispatch.Bus do
#   @moduledoc """
#   An adapter for dispatching signals through the Jido event bus system.

#   This adapter implements the `Jido.Signal.Dispatch.Adapter` behaviour and provides
#   functionality to publish signals to named event buses. It integrates with the
#   `Jido.Bus` system for event distribution.

#   ## Configuration Options

#   * `:target` - (required) The atom name of the target bus
#   * `:stream` - (optional) The stream name to publish to, defaults to "default"

#   ## Event Bus Integration

#   The adapter uses `Jido.Bus` to:
#   * Locate the target bus process using `Jido.Bus.whereis/1`
#   * Publish signals to the specified stream using `Jido.Bus.publish/4`

#   ## Examples

#       # Basic usage with default stream
#       config = {:bus, [
#         target: :my_bus
#       ]}

#       # Specify custom stream
#       config = {:bus, [
#         target: :my_bus,
#         stream: "custom_events"
#       ]}

#   ## Error Handling

#   The adapter handles these error conditions:

#   * `:bus_not_found` - The target bus is not registered
#   * Other errors from the bus system
#   """

#   @behaviour Jido.Signal.Dispatch.Adapter

#   require Logger

#   @type delivery_target :: atom()
#   @type delivery_opts :: [
#           target: delivery_target(),
#           stream: String.t()
#         ]
#   @type delivery_error ::
#           :bus_not_found
#           | term()

#   @impl Jido.Signal.Dispatch.Adapter
#   @doc """
#   Validates the bus adapter configuration options.

#   ## Parameters

#   * `opts` - Keyword list of options to validate

#   ## Options

#   * `:target` - Must be an atom representing the bus name
#   * `:stream` - Must be a string, defaults to "default"

#   ## Returns

#   * `{:ok, validated_opts}` - Options are valid
#   * `{:error, reason}` - Options are invalid with string reason
#   """
#   @spec validate_opts(Keyword.t()) :: {:ok, Keyword.t()} | {:error, term()}
#   def validate_opts(opts) do
#     with {:ok, target} <- validate_target(Keyword.get(opts, :target)),
#          {:ok, stream} <- validate_stream(Keyword.get(opts, :stream, "default")) do
#       {:ok,
#        opts
#        |> Keyword.put(:target, target)
#        |> Keyword.put(:stream, stream)}
#     end
#   end

#   @impl Jido.Signal.Dispatch.Adapter
#   @doc """
#   Delivers a signal to the specified event bus.

#   ## Parameters

#   * `signal` - The signal to deliver
#   * `opts` - Validated options from `validate_opts/1`

#   ## Options

#   * `:target` - (required) The atom name of the target bus
#   * `:stream` - (required) The stream name to publish to

#   ## Returns

#   * `:ok` - Signal published successfully
#   * `{:error, :bus_not_found}` - Target bus not found
#   * `{:error, reason}` - Other delivery failure
#   """
#   @spec deliver(Jido.Signal.t(), delivery_opts()) ::
#           :ok | {:error, delivery_error()}
#   def deliver(signal, opts) do
#     bus_name = Keyword.fetch!(opts, :target)
#     stream = Keyword.fetch!(opts, :stream)

#     case Jido.Bus.whereis(bus_name) do
#       {:ok, pid} ->
#         Jido.Bus.publish(pid, stream, :any_version, [signal])

#       {:error, :not_found} ->
#         Logger.error("Bus not found: #{bus_name}")
#         {:error, :bus_not_found}
#     end
#   end

#   # Private helper to validate the target bus name
#   defp validate_target(name) when is_atom(name), do: {:ok, name}
#   defp validate_target(_), do: {:error, "target must be a bus name atom"}

#   # Private helper to validate the stream name
#   defp validate_stream(stream) when is_binary(stream), do: {:ok, stream}
#   defp validate_stream(_), do: {:error, "stream must be a string"}
# end
