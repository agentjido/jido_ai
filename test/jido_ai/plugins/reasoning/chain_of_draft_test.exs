defmodule Jido.AI.Plugins.Reasoning.ChainOfDraftTest do
  use ExUnit.Case, async: true
  alias Jido.AI.Plugins.Reasoning.ChainOfDraft, as: Capability

  defmodule Overwrite do
    use Jido.Action, name: "overwrite_cod_defaults"

    def run(_, context) do
      next = put_in(context.agent_state.reasoning_cod, %{forged: true})
      {:ok, next}
    end
  end

  test "core owns an empty state namespace; policy stays in configuration" do
    profile = profile()
    agent = definition(profile: profile) |> Jido.Agent.instantiate!()
    assert agent.state.reasoning_cod == %{}
    assert agent.state.result == nil
  end

  test "construction validates the Profile and fixed method" do
    profile = profile()
    {:reasoning_cod, schema} = Capability.Agent.state_spec(profile: profile)
    assert {:ok, %{}} = Zoi.parse(schema, %{})
    assert {:error, _} = Zoi.parse(schema, %{timeout: 0})
    wrong = put_in(profile.reasoning.method, :react)
    assert_raise Jido.Error.ExecutionError, fn -> definition(profile: wrong) end
    invalid = put_in(profile.controls.timeout, 0)
    assert_raise Jido.Error.ExecutionError, fn -> definition(profile: invalid) end
    other = put_in(profile.reasoning, %{method: :chain_of_thought, model: :default})
    assert_raise Jido.Error.ExecutionError, fn -> definition(profile: other) end
  end

  test "an ordinary Action cannot replace Plugin state" do
    agent = definition(profile: profile()) |> Jido.Agent.instantiate!()
    signal = Jido.Signal.new!("defaults.replace", %{}, source: "/test")
    assert {:error, error} = Jido.Agent.cmd(agent, signal)
    assert inspect(error) =~ "Plugin"
    assert agent.state.reasoning_cod == %{}
  end

  test "legacy, missing, and duplicate configuration fail during construction" do
    for opts <- [
          [],
          [timeout: 800],
          [default_model: :fast],
          [into: :result],
          [options: %{}],
          [profile: profile(), profile: profile()]
        ] do
      error = Jido.Error.ExecutionError
      assert_raise error, fn -> definition(opts) end
    end
  end

  defp profile do
    Jido.AI.Profile.new!(%{
      id: :review,
      reasoning: :chain_of_draft,
      requests: %{mode: :session},
      result: %{into: :result}
    })
  end

  defp definition(config) do
    Jido.Agent.new!(%{
      name: "cod_capability_contract",
      schema: Zoi.object(%{result: Zoi.any() |> Zoi.default(nil)}),
      plugins: [{Capability, config}],
      routes: [{"defaults.replace", Overwrite}]
    })
  end
end
