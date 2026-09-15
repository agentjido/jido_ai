defmodule Jido.AI.PluginFacetsTest do
  use ExUnit.Case, async: true

  @packages [
    Jido.AI.Runtime.Plugin,
    Jido.AI.Session.Plugin,
    Jido.AI.Thread.Control.Plugin,
    Jido.AI.Plugins.Chat,
    Jido.AI.Plugins.Planning,
    Jido.AI.Plugins.ModelRouting,
    Jido.AI.Plugins.Policy,
    Jido.AI.Plugins.Retrieval,
    Jido.AI.Plugins.Quota,
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
      methods = %{
        Jido.AI.Plugins.Reasoning.ChainOfThought => :chain_of_thought,
        Jido.AI.Plugins.Reasoning.ChainOfDraft => :chain_of_draft,
        Jido.AI.Plugins.Reasoning.AlgorithmOfThoughts => :algorithm_of_thoughts,
        Jido.AI.Plugins.Reasoning.TreeOfThoughts => :tree_of_thoughts,
        Jido.AI.Plugins.Reasoning.GraphOfThoughts => :graph_of_thoughts,
        Jido.AI.Plugins.Reasoning.TRM => :trm,
        Jido.AI.Plugins.Reasoning.Adaptive => :adaptive
      }

      opts =
        if method = methods[package] do
          [
            profile:
              Jido.AI.Profile.new!(%{
                id: :review,
                reasoning: method,
                requests: %{mode: :session},
                result: %{into: :answer}
              })
          ]
        else
          []
        end

      assert {:ok, [%Jido.Plugin.Spec{} = spec]} = Jido.Plugin.normalize_all([{package, opts}])
      assert spec.module == package
      refute spec.legacy?
      assert %Jido.Plugin.Manifest{module: ^package} = spec.manifest
      assert spec.agent != nil or spec.agent_server != nil
    end
  end

  test "AI library Plugins do not use the mixed compatibility form" do
    legacy_plugins =
      :jido_ai
      |> Application.spec(:modules)
      |> Enum.filter(fn module ->
        Code.ensure_loaded?(module) and library_module?(module) and function_exported?(module, :__jido_plugin__, 0) and
          module.__jido_plugin__() == :agent
      end)

    assert legacy_plugins == []
  end

  defp library_module?(module) do
    module
    |> apply(:module_info, [:compile])
    |> Keyword.fetch!(:source)
    |> to_string()
    |> String.contains?("/lib/")
  end
end
