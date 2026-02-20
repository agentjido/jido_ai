defmodule Jido.AI.Plugins.RetrievalTest do
  use ExUnit.Case, async: false

  alias Jido.AI.Plugins.Retrieval
  alias Jido.AI.Retrieval.Store
  alias Jido.Signal

  @ns "retrieval_plugin_test"

  setup do
    _ = Store.clear(@ns)
    _ = Store.clear("team_weather")
    :ok
  end

  defp ctx(state) do
    %{
      agent: %Jido.Agent{state: %{retrieval: state}},
      plugin_instance: %{state_key: :retrieval}
    }
  end

  describe "prompt enrichment" do
    test "enriches chat.message prompt with recalled snippets" do
      Store.upsert(@ns, %{id: "m1", text: "Tokyo weather trends and weekend forecasts", metadata: %{tag: "weather"}})

      signal = Signal.new!("chat.message", %{prompt: "What is the weekend weather in Tokyo?"}, source: "/test")

      state = %{enabled: true, namespace: @ns, top_k: 3, max_snippet_chars: 120}

      assert {:ok, {:continue, enriched}} = Retrieval.handle_signal(signal, ctx(state))
      assert enriched.data.prompt =~ "Relevant memory:"
      assert enriched.data.prompt =~ "Tokyo weather trends"
      assert enriched.data.retrieval.namespace == @ns
      assert [%{id: "m1", metadata: %{tag: "weather"}}] = enriched.data.retrieval.snippets
    end

    test "skips enrichment when disable_retrieval flag is set" do
      signal =
        Signal.new!("chat.message", %{prompt: "What is the weekend weather in Tokyo?", disable_retrieval: true},
          source: "/test"
        )

      state = %{enabled: true, namespace: @ns, top_k: 3, max_snippet_chars: 120}

      assert {:ok, :continue} = Retrieval.handle_signal(signal, ctx(state))
    end

    test "skips enrichment when disable_retrieval string flag is set" do
      signal =
        Signal.new!("chat.message", %{"prompt" => "What is the weekend weather in Tokyo?", "disable_retrieval" => true},
          source: "/test"
        )

      state = %{enabled: true, namespace: @ns, top_k: 3, max_snippet_chars: 120}

      assert {:ok, :continue} = Retrieval.handle_signal(signal, ctx(state))
    end
  end

  describe "namespace behavior" do
    test "mount uses configured namespace when provided" do
      agent = %Jido.Agent{id: "agent_weather"}

      assert {:ok, state} =
               Retrieval.mount(agent, %{namespace: "team_weather", top_k: 5, max_snippet_chars: 300})

      assert state.namespace == "team_weather"
      assert state.top_k == 5
      assert state.max_snippet_chars == 300
    end

    test "mount falls back to agent id namespace when config is missing" do
      agent = %Jido.Agent{id: "agent_weather"}

      assert {:ok, state} = Retrieval.mount(agent, %{})
      assert state.namespace == "agent_weather"
    end

    test "mount falls back to default namespace without agent id" do
      assert {:ok, state} = Retrieval.mount(%{}, %{})
      assert state.namespace == "default"
    end
  end
end
