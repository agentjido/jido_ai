defmodule Jido.AI.Actions.Reasoning.RunStrategyFastTest do
  @moduledoc """
  Fast-smoke subset for `RunStrategy` used by `mix test.fast`.

  Full strategy-matrix coverage lives in `run_strategy_action_test.exs`.
  """

  use ExUnit.Case, async: false
  use Mimic

  alias Jido.AI.Actions.Reasoning.RunStrategy
  alias Jido.AI.TestSupport.FakeReqLLM

  @moduletag :stable_smoke
  @moduletag :unit
  @moduletag :capture_log

  setup :set_mimic_from_context
  setup :stub_req_llm

  defp stub_req_llm(context), do: FakeReqLLM.setup_stubs(context)

  test "executes representative strategy path for fast gate" do
    params = %{strategy: :cot, prompt: "Explain 2+2", timeout: 750}

    assert {:ok, payload} = RunStrategy.run(params, %{})
    assert payload.strategy == :cot
    assert payload.status == :success
    assert not is_nil(payload.output)
    assert is_map(payload.usage)
    assert is_map(payload.diagnostics)
    refute Map.has_key?(payload.diagnostics, :recovered_error)
  end

  test "rejects invalid strategy request in fast gate" do
    assert {:error, :invalid_strategy_request} = RunStrategy.run(%{prompt: "Missing strategy"}, %{})
    assert {:error, :invalid_strategy_request} = RunStrategy.run(%{strategy: :cot}, %{})
  end
end
