defmodule Jido.AI.Plugins.ModelRoutingTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Plugins.ModelRouting
  alias Jido.Signal

  defp ctx(routes) do
    %{
      agent: %Jido.Agent{state: %{model_routing: %{routes: routes}}},
      plugin_instance: %{state_key: :model_routing}
    }
  end

  describe "handle_signal/2 routing" do
    test "applies built-in default route when plugin state is unavailable" do
      signal = Signal.new!("chat.simple", %{prompt: "hello"}, source: "/test")

      assert {:ok, {:continue, rewritten}} = ModelRouting.handle_signal(signal, %{})
      assert rewritten.data.model == :fast
    end

    test "respects explicit model override" do
      routes = %{"chat.simple" => :fast}
      signal = Signal.new!("chat.simple", %{prompt: "hello", model: "custom:model"}, source: "/test")

      assert {:ok, :continue} = ModelRouting.handle_signal(signal, ctx(routes))
    end

    test "prefers exact route match over wildcard route match" do
      routes = %{
        "reasoning.*.run" => :reasoning,
        "reasoning.cot.run" => :capable
      }

      signal = Signal.new!("reasoning.cot.run", %{prompt: "solve"}, source: "/test")

      assert {:ok, {:continue, rewritten}} = ModelRouting.handle_signal(signal, ctx(routes))
      assert rewritten.data.model == :capable
    end

    test "supports wildcard route matching for reasoning strategy runs" do
      routes = %{"reasoning.*.run" => :reasoning}
      signal = Signal.new!("reasoning.cot.run", %{prompt: "solve"}, source: "/test")

      assert {:ok, {:continue, rewritten}} = ModelRouting.handle_signal(signal, ctx(routes))
      assert rewritten.data.model == :reasoning
    end

    test "does not match wildcard route across multiple dot segments" do
      routes = %{"reasoning.*.run" => :reasoning}
      signal = Signal.new!("reasoning.cot.worker.run", %{prompt: "solve"}, source: "/test")

      assert {:ok, :continue} = ModelRouting.handle_signal(signal, ctx(routes))
    end
  end
end
