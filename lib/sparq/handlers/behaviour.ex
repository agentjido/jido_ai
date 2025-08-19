defmodule Sparq.Handlers.Behaviour do
  @moduledoc """
  Defines the behaviour that all Sparq handlers must implement.
  This ensures a consistent interface across all operation handlers.
  """

  @doc """
  Handles an operation with the given metadata and arguments.
  Returns {result, new_context} tuple.

  ## Parameters
    * op - The operation to handle
    * meta - Metadata about the operation (like line numbers)
    * args - List of evaluated arguments
    * context - Current execution context
  """
  @callback handle(op :: atom(), meta :: map(), args :: list(), context :: map()) ::
              {term(), map()}

  @doc """
  Optional callback for validating operation arguments before evaluation.
  """
  @callback validate(op :: atom(), args :: list()) :: :ok | {:error, term()}

  @optional_callbacks validate: 2

  defmacro __using__(_opts) do
    quote do
      @behaviour Sparq.Handlers.Behaviour

      # Default implementation of validate
      @impl true
      def validate(_op, _args), do: :ok

      defoverridable validate: 2
    end
  end
end
