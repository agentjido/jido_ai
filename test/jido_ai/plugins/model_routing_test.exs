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

  test "applies default model for chat.simple when no model override is provided" do
    routes = %{"chat.simple" => :fast}
    signal = Signal.new!("chat.simple", %{prompt: "hello"}, source: "/test")

    assert {:ok, {:continue, rewritten}} = ModelRouting.handle_signal(signal, ctx(routes))
    assert rewritten.data.model == :fast
  end

  test "respects explicit model override" do
    routes = %{"chat.simple" => :fast}
    signal = Signal.new!("chat.simple", %{prompt: "hello", model: "custom:model"}, source: "/test")

    assert {:ok, :continue} = ModelRouting.handle_signal(signal, ctx(routes))
  end

  test "supports wildcard route matching for reasoning strategy runs" do
    routes = %{"reasoning.*.run" => :reasoning}
    signal = Signal.new!("reasoning.cot.run", %{prompt: "solve"}, source: "/test")

    assert {:ok, {:continue, rewritten}} = ModelRouting.handle_signal(signal, ctx(routes))
    assert rewritten.data.model == :reasoning
  end
end
