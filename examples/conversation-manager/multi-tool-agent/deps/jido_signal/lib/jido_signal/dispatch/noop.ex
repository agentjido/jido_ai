defmodule Jido.Signal.Dispatch.NoopAdapter do
  @moduledoc """
  A no-operation adapter that silently discards all signals.

  This adapter implements the `Jido.Signal.Dispatch.Adapter` behaviour but performs
  no actual signal delivery. It's useful for:

  * Testing and development environments where signals should be ignored
  * Disabling signal delivery without changing configuration structure
  * Performance testing without signal delivery overhead
  * Mocking signal dispatch in test environments

  ## Configuration

  This adapter accepts any options but ignores them all. No configuration is needed
  or used.

  ## Examples

      # Basic usage
      config = {:noop, []}

      # Options are allowed but ignored
      config = {:noop, [
        any_option: :is_ignored
      ]}

  ## Use Cases

  * Test environments
  * Development configurations
  * Performance benchmarking
  * Signal flow testing
  * Temporary signal suppression

  ## Notes

  * All signals are silently discarded
  * No errors are ever returned
  * No side effects are produced
  * Completely thread-safe and concurrent
  """

  @behaviour Jido.Signal.Dispatch.Adapter

  @impl Jido.Signal.Dispatch.Adapter
  @doc """
  Validates the noop adapter configuration options.

  This adapter accepts any options but doesn't use them. All options are
  considered valid.

  ## Parameters

  * `opts` - Keyword list of options (ignored)

  ## Returns

  * `{:ok, opts}` - Always returns ok with the unchanged options
  """
  @spec validate_opts(Keyword.t()) :: {:ok, Keyword.t()}
  def validate_opts(opts), do: {:ok, opts}

  @impl Jido.Signal.Dispatch.Adapter
  @doc """
  Silently discards the signal without performing any operation.

  ## Parameters

  * `_signal` - The signal to discard (ignored)
  * `_opts` - Options (ignored)

  ## Returns

  * `:ok` - Always returns `:ok`

  ## Examples

      iex> signal = %Jido.Signal{type: "test:event"}
      iex> NoopAdapter.deliver(signal, [])
      :ok
  """
  @spec deliver(Jido.Signal.t(), Keyword.t()) :: :ok
  def deliver(_signal, _opts), do: :ok
end
