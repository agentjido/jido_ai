defmodule Jido.AI.Plugins.ModelRoutingTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Plugins.ModelRouting
  alias Jido.Signal

  defp command(signal, routes \\ %{}) do
    definition =
      Jido.Agent.new!(%{
        name: "routing_test",
        schema: Zoi.object(%{}),
        plugins: [{ModelRouting, [routes: routes]}]
      })

    %Jido.Agent.Command{agent: Jido.Agent.instantiate!(definition), signal: signal, context: %{}}
  end

  describe "prepare/2 routing" do
    test "applies the built-in default route from declared state" do
      signal = Signal.new!("chat.simple", %{prompt: "hello"}, source: "/test")

      assert {:ok, %{signal: rewritten}} = ModelRouting.prepare(command(signal), [])
      assert rewritten.data.model == :fast
    end

    test "respects explicit model override" do
      routes = %{"chat.simple" => :fast}

      signal =
        Signal.new!("chat.simple", %{prompt: "hello", model: "custom:model"}, source: "/test")

      assert {:ok, %{signal: ^signal}} = ModelRouting.prepare(command(signal, routes), [])
    end

    test "prefers exact route match over wildcard route match" do
      routes = %{
        "reasoning.*.run" => :reasoning,
        "reasoning.cot.run" => :capable
      }

      signal = Signal.new!("reasoning.cot.run", %{prompt: "solve"}, source: "/test")

      assert {:ok, %{signal: rewritten}} = ModelRouting.prepare(command(signal, routes), [])
      assert rewritten.data.model == :capable
    end

    test "supports wildcard route matching for reasoning strategy runs" do
      routes = %{"reasoning.*.run" => :reasoning}
      signal = Signal.new!("reasoning.cot.run", %{prompt: "solve"}, source: "/test")

      assert {:ok, %{signal: rewritten}} = ModelRouting.prepare(command(signal, routes), [])
      assert rewritten.data.model == :reasoning
    end

    test "does not match wildcard route across multiple dot segments" do
      routes = %{"reasoning.*.run" => :reasoning}
      signal = Signal.new!("reasoning.cot.worker.run", %{prompt: "solve"}, source: "/test")

      assert {:ok, %{signal: ^signal}} = ModelRouting.prepare(command(signal, routes), [])
    end
  end
end
