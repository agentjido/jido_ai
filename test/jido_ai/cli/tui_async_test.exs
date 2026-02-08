defmodule Jido.AI.CLI.TUIAsyncTest do
  use ExUnit.Case, async: false

  alias Jido.AI.CLI.TUI

  defmodule FakeAdapter do
    @behaviour Jido.AI.CLI.Adapter

    @impl true
    def start_agent(_jido_instance, _agent_module, _config), do: {:ok, self()}

    @impl true
    def submit(_pid, _query, _config), do: :ok

    @impl true
    def await(_pid, _timeout_ms, _config) do
      Process.sleep(200)
      {:ok, %{answer: "ok", meta: %{model: "test"}}}
    end

    @impl true
    def stop(_pid), do: :ok

    @impl true
    def create_ephemeral_agent(_config), do: __MODULE__
  end

  test "do_query update does not block the UI loop" do
    state = %{
      adapter: FakeAdapter,
      agent_module: FakeAdapter,
      agent_pid: nil,
      pending_query_ref: nil,
      timeout: 1000,
      config: %{},
      input_buffer: "",
      messages: [],
      status: :thinking,
      error: nil,
      last_meta: nil
    }

    start_ms = System.monotonic_time(:millisecond)
    {new_state, _commands} = TUI.update({:do_query, "hello"}, state)
    elapsed_ms = System.monotonic_time(:millisecond) - start_ms

    assert elapsed_ms < 100
    assert new_state.status == :thinking
  end
end
