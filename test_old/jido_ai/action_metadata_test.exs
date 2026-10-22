defmodule Jido.AI.ActionMetadataTest do
  use ExUnit.Case, async: true

  test "quota, retrieval, and reasoning Actions expose release metadata" do
    modules = [
      Jido.AI.Actions.Quota.GetStatus,
      Jido.AI.Actions.Quota.Reset,
      Jido.AI.Actions.Retrieval.ClearMemory,
      Jido.AI.Actions.Retrieval.RecallMemory,
      Jido.AI.Actions.Retrieval.UpsertMemory,
      Jido.AI.Actions.Reasoning.Analyze,
      Jido.AI.Actions.Reasoning.Explain,
      Jido.AI.Actions.Reasoning.Infer,
      Jido.AI.Actions.Skill.LoadResource,
      Jido.AI.Actions.Skill.LoadSkill,
      Jido.AI.Actions.LLM.Chat,
      Jido.AI.Actions.LLM.Complete,
      Jido.AI.Actions.LLM.Embed,
      Jido.AI.Actions.LLM.GenerateObject,
      Jido.AI.Actions.Planning.Decompose,
      Jido.AI.Actions.Planning.Plan,
      Jido.AI.Actions.Planning.Prioritize,
      Jido.AI.Actions.ToolCalling.CallWithTools,
      Jido.AI.Actions.ToolCalling.ExecuteTool,
      Jido.AI.Actions.ToolCalling.ListTools,
      Jido.AI.Reasoning.ReAct.Actions.Cancel,
      Jido.AI.Reasoning.ReAct.Actions.Collect,
      Jido.AI.Reasoning.ReAct.Actions.Continue,
      Jido.AI.Reasoning.ReAct.Actions.Start
    ]

    for module <- modules do
      assert module.category() == "ai"
      assert module.vsn() == "1.0.0"
      assert is_list(module.tags())
      assert module.tags() != []
    end
  end
end
