defmodule Jido.AI.Reasoning.HelpersTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Jido.AI.Reasoning.Helpers

  setup :set_mimic_from_context

  setup do
    Mimic.copy(Jido.Exec)
    :ok
  end

  defmodule TestJido do
    use Jido, otp_app: :jido_ai
  end

  defmodule FailingAction do
    use Jido.Action,
      name: "failing_action",
      description: "Always fails",
      schema: []

    @impl true
    def run(_params, _context), do: {:error, :something_broke}
  end

  describe "execute_action_instruction/3" do
    test "error details include the failure reason" do
      agent = %Jido.Agent{id: "test-agent", name: "test", state: %{}}

      instruction = %Jido.Instruction{
        action: FailingAction,
        params: %{},
        context: %{}
      }

      {_agent, [%Jido.Agent.Directive.Error{error: error}]} =
        Helpers.execute_action_instruction(agent, instruction)

      assert error.message == "Instruction failed"
      assert %{reason: _} = error.details
      assert error.details != %{}
    end

    test "applies global action observability options" do
      preserve_env(:jido, :telemetry)

      for log_args <- [:none, :keys_only] do
        Application.put_env(:jido, :telemetry, log_level: :debug, log_args: log_args)

        expect_exec_opts(fn opts ->
          assert opts[:log_level] == :warning
          assert opts[:telemetry] == :silent
        end)

        Helpers.execute_action_instruction(test_agent(), test_instruction())
      end
    end

    test "preserves explicit instruction options" do
      expect_exec_opts(fn opts ->
        assert opts[:log_level] == :error
        assert opts[:telemetry] == :full
        assert opts[:retry] == false
      end)

      instruction =
        test_instruction()
        |> Map.put(:opts, log_level: :error, telemetry: :full, retry: false)

      Helpers.execute_action_instruction(test_agent(), instruction)
    end

    test "uses per-instance observability options from strategy context" do
      preserve_env(:jido_ai, TestJido)
      Application.put_env(:jido_ai, TestJido, telemetry: [log_level: :debug, log_args: :full])

      expect_exec_opts(fn opts ->
        assert opts[:log_level] == :debug
        assert opts[:telemetry] == :full
      end)

      Helpers.execute_action_instruction(test_agent(), test_instruction(), %{jido_instance: TestJido})
    end
  end

  defp expect_exec_opts(assertion) do
    Mimic.expect(Jido.Exec, :run, fn %Jido.Instruction{opts: opts} ->
      assertion.(opts)
      {:error, :something_broke}
    end)
  end

  defp test_agent, do: %Jido.Agent{id: "test-agent", name: "test", state: %{}}

  defp preserve_env(app, key) do
    original = Application.fetch_env(app, key)

    on_exit(fn ->
      case original do
        {:ok, value} -> Application.put_env(app, key, value)
        :error -> Application.delete_env(app, key)
      end
    end)
  end

  defp test_instruction do
    %Jido.Instruction{action: FailingAction, params: %{}, context: %{}}
  end
end
