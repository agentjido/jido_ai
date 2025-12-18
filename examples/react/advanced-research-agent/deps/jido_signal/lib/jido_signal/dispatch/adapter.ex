defmodule Jido.Signal.Dispatch.Adapter do
  @moduledoc """
  Defines the behaviour for signal dispatch adapters in the Jido system.

  This behaviour specifies the contract that all signal dispatch adapters must implement.
  Adapters are responsible for validating their configuration options and delivering
  signals to their respective destinations.

  ## Implementing an Adapter

  To create a custom adapter, implement this behaviour in your module:

      defmodule MyApp.CustomAdapter do
        @behaviour Jido.Signal.Dispatch.Adapter

        @impl true
        def validate_opts(opts) do
          # Validate the options and return {:ok, validated_opts} or {:error, reason}
        end

        @impl true
        def deliver(signal, opts) do
          # Deliver the signal using the validated options
          # Return :ok on success or {:error, reason} on failure
        end
      end

  ## Required Callbacks

  * `validate_opts/1` - Validates adapter-specific options before use
  * `deliver/2` - Handles the actual delivery of signals to their destination

  See the callback documentation for detailed specifications.
  """

  @doc """
  Validates the adapter-specific options.

  This callback is called before any signal delivery to ensure the adapter is properly configured.
  It should validate all required options are present and have valid values.

  ## Parameters

  * `opts` - Keyword list of adapter-specific options

  ## Returns

  * `{:ok, validated_opts}` - Options are valid and possibly normalized
  * `{:error, reason}` - Options are invalid with reason for failure
  """
  @callback validate_opts(Keyword.t()) :: {:ok, Keyword.t()} | {:error, term()}

  @doc """
  Delivers a signal using the validated options.

  This callback handles the actual delivery of the signal to its destination. The options
  passed to this function will have already been validated by `validate_opts/1`.

  ## Parameters

  * `signal` - The signal to deliver (type: `Jido.Signal.t()`)
  * `opts` - Keyword list of validated adapter-specific options

  ## Returns

  * `:ok` - Signal was successfully delivered
  * `{:error, reason}` - Delivery failed with reason for failure
  """
  @callback deliver(Jido.Signal.t(), Keyword.t()) :: :ok | {:error, term()}
end
