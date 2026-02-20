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

  describe "documentation contracts" do
    test "developer guide and module docs define precedence and wildcard behavior" do
      plugin_guide = File.read!("guides/developer/plugins_and_actions_composition.md")
      plugin_module_docs = File.read!("lib/jido_ai/plugins/model_routing.ex")

      assert plugin_guide =~ "### ModelRouting Runtime Contract"
      assert plugin_guide =~ "Route precedence:"
      assert plugin_guide =~ "Exact route keys win first"
      assert plugin_guide =~ "Wildcard behavior:"
      assert plugin_guide =~ "does not match `\"reasoning.cot.worker.run\"`"
      assert plugin_guide =~ "{Jido.AI.Plugins.ModelRouting,"
      assert plugin_guide =~ "routes: %{"

      assert plugin_module_docs =~ "## Route Precedence"
      assert plugin_module_docs =~ "## Wildcard Contracts"
      assert plugin_module_docs =~ "single dot-delimited segment matcher"
      assert plugin_module_docs =~ "## Usage"
    end

    test "examples index includes model_routing plugin configuration shape" do
      examples_readme = File.read!("lib/examples/README.md")

      assert examples_readme =~ "## Plugin Capability Pattern"
      assert examples_readme =~ "| Model routing plugin | Mount `Jido.AI.Plugins.ModelRouting`"
      assert examples_readme =~ "{Jido.AI.Plugins.ModelRouting,"
      assert examples_readme =~ "routes: %{"
      assert examples_readme =~ "reasoning.*.run"
      assert examples_readme =~ "chat.simple"
    end
  end
end
