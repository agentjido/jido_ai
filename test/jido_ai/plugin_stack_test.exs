defmodule Jido.AI.PluginStackTest do
  use ExUnit.Case, async: true

  alias Jido.AI.PluginStack
  alias Jido.AI.Plugins.TaskSupervisor

  test "default_plugins/1 includes default-on runtime plugins" do
    plugins = PluginStack.default_plugins([])

    plugin_mods =
      Enum.map(plugins, fn
        {mod, _cfg} -> mod
        mod -> mod
      end)

    assert Jido.AI.Plugins.TaskSupervisor in plugin_mods
    assert Jido.AI.Plugins.Policy in plugin_mods
    assert Jido.AI.Plugins.ModelRouting in plugin_mods
  end

  test "default_plugins/1 keeps TaskSupervisor first in runtime stack" do
    assert [TaskSupervisor | _] = PluginStack.default_plugins([])
  end

  test "default_plugins/1 supports opt-in retrieval and quota plugins" do
    plugins = PluginStack.default_plugins(retrieval: true, quota: %{max_total_tokens: 1000})

    assert Jido.AI.Plugins.Retrieval in plugins

    assert {Jido.AI.Plugins.Quota, %{max_total_tokens: 1000}} in plugins
  end

  describe "default plugin overrides" do
    test ":skip_default_plugins drops named modules from the stack" do
      plugins =
        PluginStack.default_plugins(skip_default_plugins: [Jido.AI.Plugins.Policy])

      plugin_mods = plugin_modules(plugins)

      refute Jido.AI.Plugins.Policy in plugin_mods
      assert Jido.AI.Plugins.TaskSupervisor in plugin_mods
      assert Jido.AI.Plugins.ModelRouting in plugin_mods
    end

    test ":default_plugin_config replaces a bare module entry with a {module, config} tuple" do
      plugins =
        PluginStack.default_plugins(
          default_plugin_config: [
            {Jido.AI.Plugins.Policy, %{mode: :monitor, block_on_validation_error: false}}
          ]
        )

      assert {Jido.AI.Plugins.Policy, %{mode: :monitor, block_on_validation_error: false}} in plugins
      # And it stays in position (doesn't accidentally get removed or duplicated).
      refute Jido.AI.Plugins.Policy in plugins
      assert length(Enum.filter(plugins, &matches_policy?/1)) == 1
    end

    test ":default_plugin_config accepts keyword-list config and normalises to map" do
      plugins =
        PluginStack.default_plugins(
          default_plugin_config: [{Jido.AI.Plugins.Policy, [mode: :monitor]}]
        )

      assert {Jido.AI.Plugins.Policy, %{mode: :monitor}} in plugins
    end

    test ":default_plugin_config wins over :skip_default_plugins for the same module" do
      plugins =
        PluginStack.default_plugins(
          skip_default_plugins: [Jido.AI.Plugins.Policy],
          default_plugin_config: [{Jido.AI.Plugins.Policy, %{mode: :monitor}}]
        )

      assert {Jido.AI.Plugins.Policy, %{mode: :monitor}} in plugins
    end

    test "optional plugins still layer on top of overrides" do
      plugins =
        PluginStack.default_plugins(
          retrieval: true,
          skip_default_plugins: [Jido.AI.Plugins.Policy]
        )

      plugin_mods = plugin_modules(plugins)
      refute Jido.AI.Plugins.Policy in plugin_mods
      assert Jido.AI.Plugins.Retrieval in plugin_mods
    end
  end

  defp plugin_modules(plugins) do
    Enum.map(plugins, fn
      {mod, _cfg} -> mod
      mod -> mod
    end)
  end

  defp matches_policy?({Jido.AI.Plugins.Policy, _}), do: true
  defp matches_policy?(Jido.AI.Plugins.Policy), do: true
  defp matches_policy?(_), do: false
end
