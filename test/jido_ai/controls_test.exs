defmodule Jido.AI.ControlsTest do
  use ExUnit.Case, async: false

  alias Jido.AI.Controls

  defmodule MemberOnly do
    use Jido.Action,
      name: "controls_test_member_only",
      schema: Zoi.object(%{input: Zoi.string()})

    @impl Jido.Action
    def run(_params, %{member?: true}), do: {:ok, %{allowed: true}}
    def run(_params, _context), do: {:error, :member_required}
  end

  defmodule Effectful do
    use Jido.Action,
      name: "controls_test_effectful",
      schema: Zoi.object(%{input: Zoi.string()})

    @impl Jido.Action
    def run(_params, _context), do: {:ok, %{allowed: true}, [:not_dispatched]}
  end

  defmodule PreparedOnce do
    use Jido.Action,
      name: "controls_test_prepared_once",
      schema: Zoi.object(%{input: Zoi.string()})

    @impl Jido.Action
    def on_before_validate_params(params) do
      send(Process.whereis(__MODULE__), :prepared)
      {:ok, params}
    end

    @impl Jido.Action
    def run(_params, _context), do: {:ok, %{allowed: true}}
  end

  test "an empty control slot permits the value" do
    assert Controls.run(nil, :input, "value", %{}) == :ok
  end

  @tag capture_log: true
  test "a control Action runs through Jido Exec" do
    assert Controls.run(MemberOnly, :input, "value", %{member?: true}) == :ok

    assert {:error, error} = Controls.run(MemberOnly, :input, "value", %{})
    assert Exception.message(error) == "member_required"
  end

  test "control Action effects are not lost" do
    assert Controls.run(Effectful, :input, "value", %{}) ==
             {:error, {:control_effects_not_supported, Effectful, [:not_dispatched]}}
  end

  test "Jido Exec owns control input preparation and runs it once" do
    Process.register(self(), PreparedOnce)

    on_exit(fn ->
      if Process.whereis(PreparedOnce) == self(), do: Process.unregister(PreparedOnce)
    end)

    assert Controls.run(PreparedOnce, :input, "value", %{}) == :ok
    assert_receive :prepared
    refute_receive :prepared
  end
end
