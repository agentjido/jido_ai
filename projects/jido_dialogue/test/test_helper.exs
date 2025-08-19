ExUnit.start()

defmodule Jido.Dialogue.TestHelper do
  def start_supervised_app do
    # Start the application
    {:ok, _} = Application.ensure_all_started(:jido_dialogue)

    # Wait for processes to start
    wait_for_process(Jido.Dialogue.DialogueManager)
    wait_for_process(Jido.Dialogue.ScriptManager)
    wait_for_process(Jido.Dialogue.CharacterRegistry)
    wait_for_process(Jido.Dialogue.CharacterSupervisor)

    :ok
  end

  def stop_supervised_app do
    :ok = Application.stop(:jido_dialogue)
  end

  defp wait_for_process(module) do
    case Process.whereis(module) do
      nil ->
        Process.sleep(10)
        wait_for_process(module)

      pid when is_pid(pid) ->
        :ok
    end
  end
end
