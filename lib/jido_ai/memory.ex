defmodule Jido.AI.Memory do
  @moduledoc """
  Simple per-agent memory with pluggable backends.

  Provides a behaviour for memory backends and delegates to the configured
  backend (ETS by default). Memory is scoped per-agent using `agent_id`.

  ## Configuration

      config :jido_ai, Jido.AI.Memory,
        backend: Jido.AI.Memory.Backends.ETS

  ## Usage

      alias Jido.AI.Memory

      # Store a memory
      {:ok, entry} = Memory.store("agent_1", "user_name", "Alice", tags: ["profile"])

      # Recall by key
      {:ok, entry} = Memory.recall("agent_1", %{key: "user_name"})

      # Recall by tags
      {:ok, entries} = Memory.recall("agent_1", %{tags: ["profile"]})

      # Forget by key
      {:ok, 1} = Memory.forget("agent_1", %{key: "user_name"})

  ## Implementing a Backend

  Implement the `Jido.AI.Memory` behaviour callbacks:

      defmodule MyApp.Memory.RedisBackend do
        @behaviour Jido.AI.Memory

        @impl true
        def store(agent_id, key, value, opts), do: ...

        @impl true
        def recall(agent_id, query, opts), do: ...

        @impl true
        def forget(agent_id, query, opts), do: ...
      end
  """

  alias Jido.AI.Memory.Entry

  @type agent_id :: String.t()
  @type key :: String.t()
  @type recall_query :: %{optional(:key) => key(), optional(:tags) => [String.t()]}

  @callback store(agent_id(), key(), term(), keyword()) ::
              {:ok, Entry.t()} | {:error, term()}

  @callback recall(agent_id(), recall_query(), keyword()) ::
              {:ok, Entry.t() | nil} | {:ok, [Entry.t()]} | {:error, term()}

  @callback forget(agent_id(), recall_query(), keyword()) ::
              {:ok, non_neg_integer()} | {:error, term()}

  @spec store(agent_id(), key(), term(), keyword()) :: {:ok, Entry.t()} | {:error, term()}
  def store(agent_id, key, value, opts \\ []) do
    backend().store(agent_id, key, value, opts)
  end

  @spec recall(agent_id(), recall_query(), keyword()) ::
          {:ok, Entry.t() | nil} | {:ok, [Entry.t()]} | {:error, term()}
  def recall(agent_id, query, opts \\ []) do
    backend().recall(agent_id, query, opts)
  end

  @spec forget(agent_id(), recall_query(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def forget(agent_id, query, opts \\ []) do
    backend().forget(agent_id, query, opts)
  end

  @doc "Returns the configured memory backend module."
  @spec backend() :: module()
  def backend do
    Application.get_env(:jido_ai, __MODULE__, [])
    |> Keyword.get(:backend, Jido.AI.Memory.Backends.ETS)
  end
end
