defmodule JidoAITest.Authoring.Compiler do
  @moduledoc false
  import ExUnit.Assertions

  def require_file!(path) do
    {_, diagnostics} = run(fn -> Code.require_file(path) end)
    assert diagnostics == [], "Unexpected compiler diagnostics: #{inspect(diagnostics)}"
  end

  def compile_file(path), do: run(fn -> Code.compile_file(path) end)

  # A monitor also catches failures from Spark's after_verify checker.
  def run(fun) do
    owner = self()
    {pid, ref} = spawn_monitor(fn -> send(owner, {self(), Code.with_diagnostics([log: false], fun)}) end)

    receive do
      {:DOWN, ^ref, :process, ^pid, :normal} ->
        assert_receive {^pid, result}
        result

      {:DOWN, ^ref, :process, ^pid, {error, stack}} when is_exception(error) ->
        reraise error, stack

      {:DOWN, ^ref, :process, ^pid, reason} ->
        flunk("Compiler exited: #{inspect(reason)}")
    after
      15_000 ->
        Process.exit(pid, :kill)
        assert_receive {:DOWN, ^ref, :process, ^pid, _}
        flunk("Compiler exceeded 15 seconds")
    end
  end
end
