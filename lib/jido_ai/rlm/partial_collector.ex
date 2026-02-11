defmodule Jido.AI.RLM.PartialCollector do
  @moduledoc """
  Lightweight GenServer that receives partial result events from child agents
  and writes them into the parent workspace under the `:spawn_partials` key.

  This enables the parent to see child progress before children complete.

  ## Usage

      {:ok, ref} = WorkspaceStore.init("req-1")
      {:ok, pid} = PartialCollector.start_link(ref)
      :ok = PartialCollector.emit(pid, %{chunk_id: "c1", type: :content, text: "hello", at_ms: 1000})
      :ok = PartialCollector.stop(pid)
  """

  use GenServer

  alias Jido.AI.RLM.Workspace

  @default_max_chars_per_chunk 2000

  @type event :: %{
          chunk_id: String.t(),
          type: :content | :thinking | :done,
          text: String.t(),
          at_ms: integer()
        }

  @spec start_link(Workspace.ref(), keyword()) :: GenServer.on_start()
  def start_link(workspace_ref, opts \\ []) do
    GenServer.start_link(__MODULE__, {workspace_ref, opts})
  end

  @spec emit(pid(), event()) :: :ok
  def emit(pid, event) do
    GenServer.cast(pid, {:emit, event})
  end

  @spec stop(pid()) :: :ok
  def stop(pid) do
    GenServer.stop(pid, :normal)
    :ok
  end

  @impl GenServer
  def init({workspace_ref, opts}) do
    max_chars = Keyword.get(opts, :max_chars_per_chunk, @default_max_chars_per_chunk)

    {:ok,
     %{
       workspace_ref: workspace_ref,
       max_chars_per_chunk: max_chars,
       partials: %{}
     }}
  end

  @impl GenServer
  def handle_cast({:emit, event}, state) do
    state = apply_event(state, event)
    flush(state)
    {:noreply, state}
  end

  @impl GenServer
  def terminate(_reason, state) do
    flush(state)
    :ok
  end

  defp apply_event(state, %{chunk_id: chunk_id, type: type, text: text, at_ms: at_ms}) do
    max = state.max_chars_per_chunk

    existing = Map.get(state.partials, chunk_id, %{text: "", type: type, updated_at_ms: 0, done?: false})

    new_text =
      case type do
        :done -> existing.text
        _ -> truncate_tail(existing.text <> text, max)
      end

    entry = %{
      text: new_text,
      type: type,
      updated_at_ms: at_ms,
      done?: type == :done || existing.done?
    }

    put_in(state, [:partials, chunk_id], entry)
  end

  defp truncate_tail(text, max) when byte_size(text) <= max, do: text

  defp truncate_tail(text, max) do
    binary_part(text, byte_size(text) - max, max)
  end

  defp flush(%{workspace_ref: ref, partials: partials}) do
    Workspace.update(ref, :spawn_partials, %{}, fn _existing -> partials end)
  end
end
