defmodule Jido.AI.PluginFacetsTest do
  use ExUnit.Case, async: true

  @packages [
    Jido.AI.Runtime.Plugin,
    Jido.AI.Session.Plugin,
    Jido.AI.Context.Operations.Plugin,
    Jido.AI.Plugins.Chat,
    Jido.AI.Plugins.Planning,
    Jido.AI.Plugins.ModelRouting,
    Jido.AI.Plugins.Policy,
    Jido.AI.Plugins.Retrieval,
    Jido.AI.Plugins.Quota,
    Jido.AI.Plugins.TaskSupervisor,
    Jido.AI.Plugins.Reasoning.ChainOfThought,
    Jido.AI.Plugins.Reasoning.ChainOfDraft,
    Jido.AI.Plugins.Reasoning.AlgorithmOfThoughts,
    Jido.AI.Plugins.Reasoning.TreeOfThoughts,
    Jido.AI.Plugins.Reasoning.GraphOfThoughts,
    Jido.AI.Plugins.Reasoning.TRM,
    Jido.AI.Plugins.Reasoning.Adaptive
  ]

  test "AI Plugin packages use owner-specific facets" do
    for package <- @packages do
      assert {:ok, [%Jido.Plugin.Spec{} = spec]} = Jido.Plugin.normalize_all([package])
      assert spec.module == package
      refute spec.legacy?
      assert %Jido.Plugin.Manifest{module: ^package} = spec.manifest
      assert spec.agent != nil or spec.agent_server != nil
    end
  end

  test "the complete-Agent preparation bridge is the only mixed compatibility Plugin" do
    legacy_plugins =
      :jido_ai
      |> Application.spec(:modules)
      |> Enum.filter(fn module ->
        Code.ensure_loaded?(module) and library_module?(module) and function_exported?(module, :__jido_plugin__, 0) and
          module.__jido_plugin__() == :agent
      end)

    assert MapSet.new(legacy_plugins) ==
             MapSet.new([
               Jido.AI.Runtime.PreparationPlugin,
               Jido.AI.Session.PreparationPlugin
             ])

    for plugin <- legacy_plugins do
      assert {:ok, [%{legacy?: true, state_key: nil, agent_server: nil}]} =
               Jido.Plugin.normalize_all([plugin])
    end
  end

  defp library_module?(module) do
    module
    |> apply(:module_info, [:compile])
    |> Keyword.fetch!(:source)
    |> to_string()
    |> String.contains?("/lib/")
  end
end
