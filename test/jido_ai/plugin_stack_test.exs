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

  test "docs classify TaskSupervisor only as internal runtime infrastructure" do
    plugin_guide = File.read!("guides/developer/plugins_and_actions_composition.md")
    examples_readme = File.read!("lib/examples/README.md")

    [public_section | _] = String.split(plugin_guide, "Internal runtime plugin:")

    assert plugin_guide =~ "### TaskSupervisor Internal Runtime Contract"
    assert plugin_guide =~ "Plugin state key is `:__task_supervisor_skill__`"
    assert plugin_guide =~ "linked supervisor terminates automatically"
    refute public_section =~ "Jido.AI.Plugins.TaskSupervisor"

    assert examples_readme =~ "Internal runtime infrastructure note:"
    assert examples_readme =~ "Jido.AI.Plugins.TaskSupervisor"
    assert examples_readme =~ "not a capability plugin row"
  end
end
