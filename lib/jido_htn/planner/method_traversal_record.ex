defmodule Jido.HTN.Planner.MethodTraversalRecord do
  @moduledoc """
  Tracks the methods chosen during task decomposition.
  This allows for comparing plan priorities and supporting plan repair.
  """

  alias __MODULE__

  @type method_choice :: {String.t(), String.t(), non_neg_integer()}
  @type t :: %MethodTraversalRecord{
          choices: [method_choice()]
        }

  defstruct choices: []

  @doc """
  Creates a new empty MTR.
  """
  def new do
    %MethodTraversalRecord{}
  end

  @doc """
  Records a method choice for a compound task.
  """
  def record_choice(
        %MethodTraversalRecord{choices: choices} = mtr,
        task_name,
        method_name,
        priority
      ) do
    %{mtr | choices: [{task_name, method_name, priority} | choices]}
  end

  @doc """
  Compares two MTRs to determine which has higher priority.
  Returns :gt if mtr1 has higher priority, :lt if mtr2 has higher priority, :eq if equal.
  """
  def compare_priority(%MethodTraversalRecord{choices: choices1}, %MethodTraversalRecord{
        choices: choices2
      }) do
    # Reverse both lists to compare from root to leaf
    choices1 = Enum.reverse(choices1)
    choices2 = Enum.reverse(choices2)

    # Compare each choice pair
    do_compare_priority(choices1, choices2)
  end

  # Private helpers

  defp do_compare_priority([], []), do: :eq
  # Shorter MTR has lower priority
  defp do_compare_priority([], _), do: :lt
  # Longer MTR has higher priority
  defp do_compare_priority(_, []), do: :gt

  defp do_compare_priority([{task, _m1, p1} | rest1], [{task, _m2, p2} | rest2]) do
    cond do
      p1 < p2 -> :gt
      p1 > p2 -> :lt
      true -> do_compare_priority(rest1, rest2)
    end
  end

  # Different tasks at same level - compare by task name as tiebreaker
  defp do_compare_priority([{t1, _, p1} | _], [{t2, _, p2} | _]) do
    cond do
      p1 < p2 -> :gt
      p1 > p2 -> :lt
      t1 < t2 -> :gt
      t1 > t2 -> :lt
      true -> :eq
    end
  end
end
