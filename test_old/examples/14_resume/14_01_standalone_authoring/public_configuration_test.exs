defmodule JidoAI.Examples.StandaloneConfigurationTest do
  use JidoAI.Examples.Case
  alias JidoAI.Examples.StandaloneAuthoring, as: Example

  test "public Config runs an aliased tool with bounded work", %{jido: jido} do
    {mock, _} =
      mock([
        %{reply: {:tools, [%{id: "multiply", name: "multiply", arguments: %{a: 3, b: 4}}]}},
        %{reply: {:text, "Twelve"}}
      ])

    config = Example.config(model: MockLLM.model(), llm_opts: MockLLM.options(mock))
    result = Example.run("Multiply 3 and 4", config, %{jido: jido})
    assert result.result == "Twelve"
    assert result.termination_reason == :final_answer
    assert Enum.count(result.trace, &(&1.kind == :tool_completed)) == 1
    assert_script_done(mock)
  end

  test "provider failure returns a terminal error", %{jido: jido} do
    {mock, _} = mock([%{reply: {:error, 500, "unavailable"}}])
    config = Example.config(model: MockLLM.model(), llm_opts: MockLLM.options(mock))
    result = Example.run("Answer", config, %{jido: jido})
    [failed] = Enum.filter(result.trace, &(&1.kind == :request_failed))
    assert failed.data.error != nil
    assert result.termination_reason == :failed
    assert result.result == failed.data.error
    assert_script_done(mock)
  end
end
