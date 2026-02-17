defmodule Jido.AI.PluginStackTest do
  use ExUnit.Case, async: true

  defmodule DummyTool do
    use Jido.Action,
      name: "dummy_tool",
      description: "Test tool"

    def run(params, _ctx), do: {:ok, params}
  end

  defmodule DefaultReActAgent do
    use Jido.AI.Agent,
      name: "default_react_policy_agent",
      tools: [DummyTool]
  end

  defmodule DefaultCoTAgent do
    use Jido.AI.CoTAgent,
      name: "default_cot_policy_agent"
  end

  defmodule DefaultToTAgent do
    use Jido.AI.ToTAgent,
      name: "default_tot_policy_agent"
  end

  defmodule DefaultGoTAgent do
    use Jido.AI.GoTAgent,
      name: "default_got_policy_agent"
  end

  defmodule DefaultTRMAgent do
    use Jido.AI.TRMAgent,
      name: "default_trm_policy_agent"
  end

  defmodule DefaultAdaptiveAgent do
    use Jido.AI.AdaptiveAgent,
      name: "default_adaptive_policy_agent"
  end

  defmodule NoPolicyToTAgent do
    use Jido.AI.ToTAgent,
      name: "no_policy_tot_agent",
      policy: false
  end

  defmodule PolicyConfiguredAgent do
    use Jido.AI.Agent,
      name: "configured_policy_agent",
      tools: [DummyTool],
      policy: [query_max_length: 1234]
  end

  defmodule ExplicitPolicyPluginAgent do
    use Jido.AI.Agent,
      name: "explicit_policy_plugin_agent",
      tools: [DummyTool],
      policy: [query_max_length: 9000],
      plugins: [{Jido.AI.Plugins.Policy, %{query_max_length: 77}}]
  end

  describe "default policy plugin inclusion" do
    test "all AI macros include TaskSupervisor and Policy plugins by default" do
      for module <- [
            DefaultReActAgent,
            DefaultCoTAgent,
            DefaultToTAgent,
            DefaultGoTAgent,
            DefaultTRMAgent,
            DefaultAdaptiveAgent
          ] do
        plugins = module.plugins()
        assert Jido.AI.Plugins.TaskSupervisor in plugins
        assert Jido.AI.Plugins.Policy in plugins
      end
    end
  end

  describe "policy option behavior" do
    test "policy: false disables only the default policy plugin" do
      plugins = NoPolicyToTAgent.plugins()
      refute Jido.AI.Plugins.Policy in plugins
      assert Jido.AI.Plugins.TaskSupervisor in plugins
    end

    test "policy config overrides defaults without duplicating plugin module entries" do
      policy_instances =
        PolicyConfiguredAgent.plugin_instances()
        |> Enum.filter(&(&1.module == Jido.AI.Plugins.Policy))

      assert length(policy_instances) == 1
      assert hd(policy_instances).config.query_max_length == 1234
    end

    test "explicit user policy plugin config wins over policy option config" do
      policy_instances =
        ExplicitPolicyPluginAgent.plugin_instances()
        |> Enum.filter(&(&1.module == Jido.AI.Plugins.Policy))

      assert length(policy_instances) == 1
      assert hd(policy_instances).config.query_max_length == 77
    end
  end
end
