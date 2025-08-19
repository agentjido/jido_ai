defmodule Demo do
  def run do
    # Define initial world state
    world_state = %{
      energy: 100,
      location: :home,
      task_complete: false
    }

    # Get domain and plan
    case Jido.HTN.plan(domain(), world_state) do
      {:ok, plan, _mtr} ->
        IO.puts("Generated plan:")

        Enum.each(plan, fn {action, params} ->
          IO.puts("  #{inspect(action)} with params #{inspect(params)}")
        end)

      # Fallback for older 2-element tuple without MTR
      {:ok, plan} ->
        IO.puts("Generated plan:")

        Enum.each(plan, fn {action, params} ->
          IO.puts("  #{inspect(action)} with params #{inspect(params)}")
        end)

      {:error, reason} ->
        IO.puts("Planning failed: #{reason}")
    end
  end

  def domain do
    alias Jido.HTN.Domain, as: D
    alias Jido.Actions.Basic, as: B

    "DemoBot"
    |> D.new()
    |> D.compound("root",
      methods: [%{subtasks: ["do_work"]}]
    )
    |> D.compound("do_work",
      methods: [
        %{
          subtasks: ["start_work", "perform_work", "finish_work"],
          conditions: [&has_energy?/1]
        }
      ]
    )
    |> D.primitive(
      "start_work",
      {B.Log, message: "Starting work"},
      preconditions: [&at_home?/1],
      expected_effects: [&decrease_energy/1]
    )
    |> D.primitive(
      "perform_work",
      {B.RandomDelay, min_ms: 1000, max_ms: 2000},
      expected_effects: [&do_task/1]
    )
    |> D.primitive(
      "finish_work",
      {B.Log, message: "Work complete"},
      expected_effects: [&mark_complete/1]
    )
    |> D.allow("start_work", B.Log)
    |> D.allow("perform_work", B.RandomDelay)
    |> D.allow("finish_work", B.Log)
    |> D.build!()
  end

  # Predicates
  defp has_energy?(state), do: state.energy > 20
  defp at_home?(state), do: state.location == :home

  # Transformers
  defp decrease_energy(state), do: %{state | energy: state.energy - 10}
  defp do_task(state), do: %{state | energy: state.energy - 20}
  defp mark_complete(state), do: %{state | task_complete: true}
end
