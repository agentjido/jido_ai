defmodule Jido.Signal.Dispatch.PidAdapter do
  @moduledoc """
  An adapter for dispatching signals directly to Erlang processes using PIDs.

  This adapter implements the `Jido.Signal.Dispatch.Adapter` behaviour and provides
  functionality to send signals to specific processes either synchronously or
  asynchronously.

  ## Configuration Options

  * `:target` - (required) The PID of the destination process
  * `:delivery_mode` - (optional) Either `:sync` or `:async`, defaults to `:async`
  * `:timeout` - (optional) Timeout for synchronous delivery in milliseconds, defaults to 5000
  * `:message_format` - (optional) Function to format the signal before sending, defaults to wrapping in `{:signal, signal}`

  ## Delivery Modes

  * `:async` - Uses `send/2` to deliver the signal without waiting for a response
  * `:sync` - Uses `GenServer.call/3` to deliver the signal and wait for a response

  ## Examples

      # Asynchronous delivery
      config = {:pid, [
        target: destination_pid,
        delivery_mode: :async
      ]}

      # Synchronous delivery with custom timeout
      config = {:pid, [
        target: destination_pid,
        delivery_mode: :sync,
        timeout: 10_000
      ]}

      # Custom message format
      config = {:pid, [
        target: destination_pid,
        message_format: fn signal -> {:custom_signal, signal} end
      ]}

  ## Error Handling

  The adapter handles various error conditions:

  * `:process_not_alive` - The target process is not alive
  * `:timeout` - Synchronous delivery timed out
  * Other errors from the target process
  """

  @behaviour Jido.Signal.Dispatch.Adapter

  @type delivery_target :: pid()
  @type delivery_mode :: :sync | :async
  @type message_format :: (Jido.Signal.t() -> term())
  @type delivery_opts :: [
          target: delivery_target(),
          delivery_mode: delivery_mode(),
          timeout: timeout(),
          message_format: message_format()
        ]
  @type delivery_error ::
          :process_not_alive
          | :timeout
          | term()

  @impl Jido.Signal.Dispatch.Adapter
  @doc """
  Validates the PID adapter configuration options.

  ## Parameters

  * `opts` - Keyword list of options to validate

  ## Options

  * `:target` - Must be a valid PID
  * `:delivery_mode` - Must be either `:sync` or `:async`

  ## Returns

  * `{:ok, validated_opts}` - Options are valid
  * `{:error, :invalid_target}` - Target is not a valid PID
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

  # Private helper to validate the target PID
  defp validate_target(pid) when is_pid(pid), do: {:ok, pid}
  defp validate_target(_), do: {:error, :invalid_target}

  # Private helper to validate the delivery mode
  defp validate_mode(mode) when mode in [:sync, :async], do: {:ok, mode}
  defp validate_mode(_), do: {:error, :invalid_delivery_mode}

  @impl Jido.Signal.Dispatch.Adapter
  @doc """
  Delivers a signal to the target process.

  ## Parameters

  * `signal` - The signal to deliver
  * `opts` - Validated options from `validate_opts/1`

  ## Options

  * `:target` - (required) Target PID to deliver to
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

    case mode do
      :async ->
        if Process.alive?(target) do
          send(target, message_format.(signal))
          :ok
        else
          {:error, :process_not_alive}
        end

      :sync ->
        if Process.alive?(target) do
          try do
            message = message_format.(signal)

            if target == self() do
              {:error, {:calling_self, {GenServer, :call, [target, message, timeout]}}}
            else
              GenServer.call(target, message, timeout)
            end
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

  # Default message format wraps signal in a tuple
  defp default_message_format(signal), do: {:signal, signal}
end
