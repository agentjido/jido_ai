defmodule Jido.AI.Actions.Planning.PrioritizeTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Jido.AI.Actions.Planning.Prioritize, as: Action
  alias Jido.AI.TestSupport.FakeReqLLM

  setup :set_mimic_from_context
  setup :stub_req_llm

  defp stub_req_llm(context), do: FakeReqLLM.setup_stubs(context)

  test "the public schema remains static and supplies the Action generation defaults" do
    assert :ok = Jido.Action.validate_static_data(Action.schema())
    assert {:ok, params} = Action.validate_params(%{tasks: ["Release"]})
    assert params.max_tokens == 4096 and params.temperature == 0.5
  end

  test "invalid required inputs fail before model resolution" do
    assert {:error, _} = Action.run(%{}, %{})
    assert {:error, _} = Jido.Exec.run(Action, %{}, %{})
  end

  test "the catalog retains the Action name category tags and version" do
    assert Action.name() == "planning_prioritize"
    assert Action.category() == "ai" and Action.vsn() == "1.0.0"
    assert "planning" in Action.tags()
  end

  test "extracts the arrow-separated execution order requested by its prompt" do
    expect(ReqLLM.Generation, :generate_text, fn model, _messages, _opts ->
      {:ok,
       %{
         message: %{
           content: "## Recommended Execution Order\n1. [Fix critical bug] → 2. [Add tests] → 3. [Release]"
         },
         finish_reason: :stop,
         usage: %{},
         model: model
       }}
    end)

    assert {:ok, params} = Action.validate_params(%{tasks: ["Fix critical bug", "Add tests", "Release"]})
    assert {:ok, result} = Action.run(params, %{})
    assert result.ordered_tasks == ["Fix critical bug", "Add tests", "Release"]
  end
end
