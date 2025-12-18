defmodule Jido.AI.Runner.GEPA.Scheduler.Queue do
  @moduledoc """
  Priority queue for evaluation tasks.

  Implements a multi-level priority queue supporting critical, high, normal, and low
  priority tasks with efficient enqueue/dequeue operations.

  ## Priority Levels

  - `:critical` - Highest priority, processed immediately
  - `:high` - High priority, before normal tasks
  - `:normal` - Standard priority (default)
  - `:low` - Lowest priority, processed when idle

  ## Implementation

  Uses separate Erlang queues for each priority level with O(1) enqueue/dequeue
  operations. Tasks are dispatched from highest to lowest priority queues.
  """

  use TypedStruct

  alias Jido.AI.Runner.GEPA.Scheduler.Task

  typedstruct do
    field(:critical, :queue.queue(), default: :queue.new())
    field(:high, :queue.queue(), default: :queue.new())
    field(:normal, :queue.queue(), default: :queue.new())
    field(:low, :queue.queue(), default: :queue.new())
    field(:task_index, map(), default: %{})
    field(:enable_priorities, boolean(), default: true)
  end

  @doc """
  Creates a new empty queue.

  ## Options

  - `:enable_priorities` - Enable priority-based scheduling (default: true)

  ## Examples

      queue = Queue.new()
      queue = Queue.new(enable_priorities: false)
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      critical: :queue.new(),
      high: :queue.new(),
      normal: :queue.new(),
      low: :queue.new(),
      task_index: %{},
      enable_priorities: Keyword.get(opts, :enable_priorities, true)
    }
  end

  @doc """
  Enqueues a task based on its priority.

  ## Examples

      queue = Queue.enqueue(queue, task)
  """
  @spec enqueue(t(), Task.t()) :: t()
  def enqueue(%__MODULE__{} = queue, %Task{} = task) do
    priority_level = if queue.enable_priorities, do: task.priority, else: :normal

    updated_queue =
      case priority_level do
        :critical ->
          %{queue | critical: :queue.in(task, queue.critical)}

        :high ->
          %{queue | high: :queue.in(task, queue.high)}

        :normal ->
          %{queue | normal: :queue.in(task, queue.normal)}

        :low ->
          %{queue | low: :queue.in(task, queue.low)}
      end

    # Add to index for quick lookup
    %{updated_queue | task_index: Map.put(updated_queue.task_index, task.id, priority_level)}
  end

  @doc """
  Dequeues the highest priority task.

  Returns `{:ok, task, updated_queue}` if a task is available,
  or `{:empty, queue}` if the queue is empty.

  ## Examples

      {:ok, task, queue} = Queue.dequeue(queue)
      {:empty, queue} = Queue.dequeue(empty_queue)
  """
  @spec dequeue(t()) :: {:ok, Task.t(), t()} | {:empty, t()}
  def dequeue(%__MODULE__{} = queue) do
    # Try each priority level in order
    cond do
      not :queue.is_empty(queue.critical) ->
        dequeue_from_level(queue, :critical)

      not :queue.is_empty(queue.high) ->
        dequeue_from_level(queue, :high)

      not :queue.is_empty(queue.normal) ->
        dequeue_from_level(queue, :normal)

      not :queue.is_empty(queue.low) ->
        dequeue_from_level(queue, :low)

      true ->
        {:empty, queue}
    end
  end

  @doc """
  Dequeues multiple tasks up to the specified limit.

  Returns `{tasks, updated_queue}` where tasks is a list of dequeued tasks.

  ## Examples

      {tasks, queue} = Queue.dequeue_many(queue, 5)
      # => {[task1, task2, task3], updated_queue}
  """
  @spec dequeue_many(t(), pos_integer()) :: {list(Task.t()), t()}
  def dequeue_many(%__MODULE__{} = queue, limit) when limit > 0 do
    do_dequeue_many(queue, limit, [])
  end

  @doc """
  Returns the number of tasks in the queue.

  ## Examples

      size = Queue.size(queue)
  """
  @spec size(t()) :: non_neg_integer()
  def size(%__MODULE__{} = queue) do
    :queue.len(queue.critical) +
      :queue.len(queue.high) +
      :queue.len(queue.normal) +
      :queue.len(queue.low)
  end

  @doc """
  Returns true if the queue is empty.

  ## Examples

      true = Queue.empty?(empty_queue)
      false = Queue.empty?(queue_with_tasks)
  """
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{} = queue) do
    size(queue) == 0
  end

  @doc """
  Checks if a task with the given ID is in the queue.

  ## Examples

      true = Queue.contains?(queue, "task_123")
      false = Queue.contains?(queue, "nonexistent")
  """
  @spec contains?(t(), String.t()) :: boolean()
  def contains?(%__MODULE__{} = queue, task_id) do
    Map.has_key?(queue.task_index, task_id)
  end

  @doc """
  Removes a task from the queue by ID.

  Returns `{:ok, updated_queue}` if the task was found and removed,
  or `{:error, :not_found}` if the task is not in the queue.

  ## Examples

      {:ok, queue} = Queue.remove(queue, "task_123")
      {:error, :not_found} = Queue.remove(queue, "nonexistent")
  """
  @spec remove(t(), String.t()) :: {:ok, t()} | {:error, :not_found}
  def remove(%__MODULE__{} = queue, task_id) do
    case Map.fetch(queue.task_index, task_id) do
      {:ok, priority_level} ->
        updated_queue = remove_from_level(queue, task_id, priority_level)
        updated_index = Map.delete(updated_queue.task_index, task_id)
        {:ok, %{updated_queue | task_index: updated_index}}

      :error ->
        {:error, :not_found}
    end
  end

  # Private Functions

  defp dequeue_from_level(queue, level) do
    level_queue = Map.get(queue, level)

    case :queue.out(level_queue) do
      {{:value, task}, updated_level_queue} ->
        updated_queue = %{queue | level => updated_level_queue}
        updated_index = Map.delete(updated_queue.task_index, task.id)
        {:ok, task, %{updated_queue | task_index: updated_index}}

      {:empty, _} ->
        {:empty, queue}
    end
  end

  defp do_dequeue_many(queue, 0, acc), do: {Enum.reverse(acc), queue}

  defp do_dequeue_many(queue, limit, acc) do
    case dequeue(queue) do
      {:ok, task, updated_queue} ->
        do_dequeue_many(updated_queue, limit - 1, [task | acc])

      {:empty, queue} ->
        {Enum.reverse(acc), queue}
    end
  end

  defp remove_from_level(queue, task_id, level) do
    level_queue = Map.get(queue, level)
    filtered_queue = filter_queue(level_queue, task_id)
    Map.put(queue, level, filtered_queue)
  end

  defp filter_queue(q, task_id_to_remove) do
    # Convert queue to list, filter, and back to queue
    q
    |> :queue.to_list()
    |> Enum.reject(fn task -> task.id == task_id_to_remove end)
    |> :queue.from_list()
  end
end
