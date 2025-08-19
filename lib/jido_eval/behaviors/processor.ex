defmodule Jido.Eval.Processor do
  @moduledoc """
  Behavior for processing evaluation data.

  Processors handle data transformation and filtering during evaluation runs.
  They can run at different stages (pre/post) to modify or enhance evaluation data.

  ## Callbacks

  - `c:process/3` - Process evaluation data (required)

  ## Examples

      defmodule DataNormalizer do
        @behaviour Jido.Eval.Processor
        
        def process(data, :pre, opts) do
          normalized = normalize_inputs(data)
          {:ok, normalized}
        end
        
        def process(data, :post, opts) do
          enhanced = add_metadata(data)
          {:ok, enhanced}
        end
        
        defp normalize_inputs(data), do: data
        defp add_metadata(data), do: data
      end
  """

  @doc """
  Process evaluation data.

  Called to transform or filter evaluation data during runs.

  ## Parameters

  - `data` - The data to process
  - `stage` - Processing stage (`:pre` or `:post`)
  - `opts` - Processor configuration options

  ## Returns

  - `{:ok, processed_data}` - Success with processed data
  - `{:error, reason}` - Processing failed
  """
  @callback process(data :: any(), stage :: :pre | :post, opts :: keyword()) ::
              {:ok, any()} | {:error, any()}
end
