defmodule Jido.Eval.Store do
  @moduledoc """
  Behavior for persistent storage of evaluation results.

  Stores handle the persistence of evaluation data to various backends
  like databases, files, or cloud storage services.

  ## Callbacks

  - `c:init/1` - Initialize the store (required)
  - `c:persist/2` - Store evaluation data (required)
  - `c:finalize/1` - Cleanup and finalize storage (required)

  ## Examples

      defmodule FileStore do
        @behaviour Jido.Eval.Store
        
        def init(opts) do
          path = Keyword.get(opts, :path, "results.json")
          {:ok, %{path: path, data: []}}
        end
        
        def persist(data, state) do
          updated_data = [data | state.data]
          {:ok, %{state | data: updated_data}}
        end
        
        def finalize(state) do
          File.write!(state.path, Jason.encode!(state.data))
          :ok
        end
      end
  """

  @doc """
  Initialize the store.

  Called once at the start of an evaluation run to set up the storage backend.

  ## Parameters

  - `opts` - Store configuration options

  ## Returns

  - `{:ok, state}` - Success with initial state
  - `{:error, reason}` - Initialization failed
  """
  @callback init(opts :: keyword()) ::
              {:ok, any()} | {:error, any()}

  @doc """
  Persist evaluation data.

  Called to store evaluation results during the run.

  ## Parameters

  - `data` - The data to persist
  - `state` - Current store state

  ## Returns

  - `{:ok, new_state}` - Success with updated state
  - `{:error, reason}` - Storage failed
  """
  @callback persist(data :: any(), state :: any()) ::
              {:ok, any()} | {:error, any()}

  @doc """
  Finalize storage operations.

  Called at the end of an evaluation run to cleanup and finalize storage.

  ## Parameters

  - `state` - Final store state

  ## Returns

  - `:ok` - Success
  - `{:error, reason}` - Finalization failed
  """
  @callback finalize(state :: any()) ::
              :ok | {:error, any()}
end
