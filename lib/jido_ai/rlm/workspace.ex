defmodule Jido.AI.RLM.Workspace do
  @moduledoc """
  Behaviour defining the contract for workspace storage backends.

  A workspace provides per-request key-value storage that tools use during
  exploration. The default adapter is `Jido.AI.RLM.Workspace.ETSAdapter`.

  ## Usage

      {:ok, ref} = Workspace.init("req-123")
      :ok = Workspace.put(ref, :hits, ["match1"])
      {:ok, hits} = Workspace.fetch(ref, :hits)
      :ok = Workspace.update(ref, :count, 0, &(&1 + 1))
      :ok = Workspace.delete_key(ref, :hits)
      :ok = Workspace.destroy(ref)
  """

  @type ref :: %{adapter: module(), pid: pid()}

  @callback init(request_id :: String.t(), opts :: keyword()) :: {:ok, ref()} | {:error, term()}
  @callback destroy(ref()) :: :ok
  @callback fetch(ref(), key :: term()) :: {:ok, term()} | :error
  @callback put(ref(), key :: term(), value :: term()) :: :ok
  @callback delete_key(ref(), key :: term()) :: :ok
  @callback update(ref(), key :: term(), default :: term(), fun :: (term() -> term())) :: :ok

  @spec init(String.t(), keyword()) :: {:ok, ref()} | {:error, term()}
  def init(request_id, opts \\ []) do
    adapter = Keyword.get(opts, :adapter, Jido.AI.RLM.Workspace.ETSAdapter)
    adapter.init(request_id, opts)
  end

  @spec destroy(ref()) :: :ok
  def destroy(ref), do: ref.adapter.destroy(ref)

  @spec fetch(ref(), term()) :: {:ok, term()} | :error
  def fetch(ref, key), do: ref.adapter.fetch(ref, key)

  @spec put(ref(), term(), term()) :: :ok
  def put(ref, key, value), do: ref.adapter.put(ref, key, value)

  @spec delete_key(ref(), term()) :: :ok
  def delete_key(ref, key), do: ref.adapter.delete_key(ref, key)

  @spec update(ref(), term(), term(), (term() -> term())) :: :ok
  def update(ref, key, default, fun), do: ref.adapter.update(ref, key, default, fun)
end
