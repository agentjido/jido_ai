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
end
