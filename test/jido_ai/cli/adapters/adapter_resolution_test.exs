defmodule Jido.AI.CLI.AdapterResolutionTest do
  use ExUnit.Case, async: true

  alias Jido.AI.CLI.Adapter

  defmodule CustomAgentWithCliAdapter do
    @spec cli_adapter() :: module()
    def cli_adapter, do: Jido.AI.Reasoning.ChainOfThought.CLIAdapter
  end

  describe "resolve/2" do
    test "resolves each supported type" do
      expected = %{
        "react" => Jido.AI.Reasoning.ReAct.CLIAdapter,
        "aot" => Jido.AI.Reasoning.AlgorithmOfThoughts.CLIAdapter,
        "cod" => Jido.AI.Reasoning.ChainOfDraft.CLIAdapter,
        "cot" => Jido.AI.Reasoning.ChainOfThought.CLIAdapter,
        "tot" => Jido.AI.Reasoning.TreeOfThoughts.CLIAdapter,
        "got" => Jido.AI.Reasoning.GraphOfThoughts.CLIAdapter,
        "trm" => Jido.AI.Reasoning.TRM.CLIAdapter,
        "adaptive" => Jido.AI.Reasoning.Adaptive.CLIAdapter
      }

      Enum.each(expected, fn {type, adapter} ->
        assert {:ok, ^adapter} = Adapter.resolve(type, nil)
      end)
    end

    test "defaults to react when type is nil" do
      assert {:ok, Jido.AI.Reasoning.ReAct.CLIAdapter} = Adapter.resolve(nil, nil)
    end

    test "prefers module-provided adapter over type option" do
      assert {:ok, Jido.AI.Reasoning.ChainOfThought.CLIAdapter} =
               Adapter.resolve("react", CustomAgentWithCliAdapter)
    end

    test "returns formatted error for unknown type" do
      assert {:error, message} = Adapter.resolve("unknown", nil)
      assert message =~ "Unknown agent type: unknown."

      Enum.each(Adapter.supported_types(), fn type ->
        assert message =~ type
      end)
    end
  end

  describe "supported_types/0" do
    test "returns strategy types expected by mix jido_ai docs and examples" do
      assert Adapter.supported_types() == ~w(react aot cod cot tot got trm adaptive)
    end
  end
end
