defmodule Jido.AI.Plugins.RetrievalTest do
  use ExUnit.Case, async: false

  alias Jido.AI.Plugins.Retrieval
  alias Jido.AI.Retrieval.Store
  alias Jido.Signal

  @ns "retrieval_plugin_test"

  setup do
    _ = Store.clear(@ns)
    :ok
  end

  defp ctx(state) do
    %{
      agent: %Jido.Agent{state: %{retrieval: state}},
      plugin_instance: %{state_key: :retrieval}
    }
  end

  test "enriches chat.message prompt with recalled snippets" do
    Store.upsert(@ns, %{id: "m1", text: "Tokyo weather trends and weekend forecasts", metadata: %{tag: "weather"}})

    signal = Signal.new!("chat.message", %{prompt: "What is the weekend weather in Tokyo?"}, source: "/test")

    state = %{enabled: true, namespace: @ns, top_k: 3, max_snippet_chars: 120}

    assert {:ok, {:continue, enriched}} = Retrieval.handle_signal(signal, ctx(state))
    assert enriched.data.prompt =~ "Relevant memory:"
    assert enriched.data.prompt =~ "Tokyo weather trends"
    assert is_map(enriched.data.retrieval)
  end

  test "skips enrichment when disable_retrieval flag is set" do
    signal =
      Signal.new!("chat.message", %{prompt: "What is the weekend weather in Tokyo?", disable_retrieval: true},
        source: "/test"
      )

    state = %{enabled: true, namespace: @ns, top_k: 3, max_snippet_chars: 120}

    assert {:ok, :continue} = Retrieval.handle_signal(signal, ctx(state))
  end
end
