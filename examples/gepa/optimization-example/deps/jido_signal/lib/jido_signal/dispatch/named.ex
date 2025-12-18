defmodule Jido.Signal.Dispatch.Named do
  @moduledoc """
  An adapter for dispatching signals to named processes in the Erlang registry.

  This adapter implements the `Jido.Signal.Dispatch.Adapter` behaviour and provides
  functionality to send signals to processes registered under a name in the Erlang
  process registry. It supports both synchronous and asynchronous delivery modes.

  ## Configuration Options

  * `:target` - (required) A tuple of `{:name, atom()}` specifying the registered process name
  * `:delivery_mode` - (optional) Either `:sync` or `:async`, defaults to `:async`
  * `:timeout` - (optional) Timeout for synchronous delivery in milliseconds, defaults to 5000
  * `:message_format` - (optional) Function to format the signal before sending, defaults to wrapping in `{:signal, signal}`

  ## Delivery Modes

  * `:async` - Uses `send/2` to deliver the signal without waiting for a response
  * `:sync` - Uses `GenServer.call/3` to deliver the signal and wait for a response

  ## Examples

      # Asynchronous delivery to named process
      config = {:named, [
        target: {:name, :my_process},
        delivery_mode: :async
      ]}

      # Synchronous delivery with custom timeout
      config = {:named, [
        target: {:name, :my_process},
        delivery_mode: :sync,
        timeout: 10_000
      ]}

      # Custom message format
      config = {:named, [
        target: {:name, :my_process},
        message_format: fn signal -> {:custom_signal, signal} end
      ]}

  ## Error Handling

  The adapter handles these error conditions:

  * `:process_not_found` - The named process is not registered
  * `:process_not_alive` - The process exists but is not alive
  * `:timeout` - Synchronous delivery timed out
  * Other errors from the target process
  """

  @behaviour Jido.Signal.Dispatch.Adapter

  @type delivery_target :: {:name, atom()}
  @type delivery_mode :: :sync | :async
  @type message_format :: (Jido.Signal.t() -> term())
  @type delivery_opts :: [
          target: delivery_target(),
          delivery_mode: delivery_mode(),
          timeout: timeout(),
          message_format: message_format()
        ]
  @type delivery_error ::
          :process_not_found
          | :process_not_alive
          | :timeout
          | term()

  @impl Jido.Signal.Dispatch.Adapter
  @doc """
  Validates the named process adapter configuration options.

  ## Parameters

  * `opts` - Keyword list of options to validate

  ## Options

  * `:target` - Must be a tuple of `{:name, atom()}`
  * `:delivery_mode` - Must be either `:sync` or `:async`

  ## Returns

  * `{:ok, validated_opts}` - Options are valid
  * `{:error, :invalid_target}` - Target is not a valid name tuple
  * `{:error, :invalid_delivery_mode}` - Delivery mode is invalid
  """
  @spec validate_opts(Keyword.t()) :: {:ok, Keyword.t()} | {:error, term()}
  def validate_opts(opts) do
    with {:ok, target} <- validate_target(Keyword.get(opts, :target)),
         {:ok, mode} <- validate_mode(Keyword.get(opts, :delivery_mode, :async)) do
      {:ok,
       opts
       |> Keyword.put(:target, target)
       |> Keyword.put(:delivery_mode, mode)}
    end
  end

  # Private helper to validate the target name tuple
  defp validate_target({:name, name}) when is_atom(name), do: {:ok, {:name, name}}
  defp validate_target(_), do: {:error, :invalid_target}

  # Private helper to validate the delivery mode
  defp validate_mode(mode) when mode in [:sync, :async], do: {:ok, mode}
  defp validate_mode(_), do: {:error, :invalid_delivery_mode}

  @impl Jido.Signal.Dispatch.Adapter
  @doc """
  Delivers a signal to the named process.

  ## Parameters

  * `signal` - The signal to deliver
  * `opts` - Validated options from `validate_opts/1`

  ## Options

  * `:target` - (required) Tuple of `{:name, atom()}` identifying the process
  * `:delivery_mode` - (required) Either `:sync` or `:async`
  * `:timeout` - (optional) Timeout for sync delivery, defaults to 5000ms
  * `:message_format` - (optional) Function to format the signal

  ## Returns

  * `:ok` - Signal delivered successfully (async mode)
  * `{:ok, term()}` - Signal delivered and response received (sync mode)
  * `{:error, reason}` - Delivery failed
  """
  @spec deliver(Jido.Signal.t(), delivery_opts()) ::
          :ok | {:ok, term()} | {:error, delivery_error()}
  def deliver(signal, opts) do
    target = Keyword.fetch!(opts, :target)
    mode = Keyword.fetch!(opts, :delivery_mode)
    timeout = Keyword.get(opts, :timeout, 5000)
    message_format = Keyword.get(opts, :message_format, &default_message_format/1)

    case {target, mode} do
      {{:name, name}, :async} ->
        case Process.whereis(name) do
          nil ->
            {:error, :process_not_found}

          pid ->
            if Process.alive?(pid) do
              send(pid, message_format.(signal))
              :ok
            else
              {:error, :process_not_alive}
            end
        end

      {{:name, name}, :sync} ->
        case Process.whereis(name) do
          nil ->
            {:error, :process_not_found}

          pid ->
            if Process.alive?(pid) do
              try do
                message = message_format.(signal)
                GenServer.call(pid, message, timeout)
              catch
                :exit, {:timeout, _} -> {:error, :timeout}
                :exit, {:noproc, _} -> {:error, :process_not_alive}
                :exit, reason -> {:error, reason}
              end
            else
              {:error, :process_not_alive}
            end
        end
    end
  end

  # Default message format wraps signal in a tuple
  defp default_message_format(signal), do: {:signal, signal}
end
