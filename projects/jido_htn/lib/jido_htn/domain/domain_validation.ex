defmodule Jido.HTN.Domain.ValidationHelpers do
  @moduledoc false
  use ExDbug, enabled: false
  alias Jido.HTN.CompoundTask
  alias Jido.HTN.Domain
  alias Jido.HTN.Domain.Builder
  alias Jido.HTN.Method
  alias Jido.HTN.PrimitiveTask

  require Logger

  @type validation_result :: :ok | {:error, String.t() | [String.t()]}

  @doc """
  Validates the domain structure, checking for consistency and completeness.
  """
  @spec validate(Domain.t() | Builder.t() | {:ok, Domain.t()} | {:error, String.t()}) ::
          validation_result
  def validate({:ok, domain}), do: validate(domain)
  def validate({:error, error}) when is_binary(error), do: {:error, error}
  def validate(%Builder{domain: domain, error: nil}), do: validate(domain)
  def validate(%Builder{error: error}) when is_binary(error), do: {:error, error}

  def validate(%Domain{} = domain) do
    dbug("Validating domain structure")

    with {:ok, _} <- validate_non_empty_domain(domain),
         {:ok, _} <- validate_unique_names(domain),
         {:ok, _} <- validate_subtasks(domain),
         {:ok, _} <- validate_allowed_workflows(domain),
         {:ok, _} <- validate_defined_tasks(domain),
         {:ok, _} <- validate_unique_callbacks(domain),
         {:ok, _} <- validate_workflow_module_interface(domain),
         {:ok, _} <- validate_callback_signatures(domain),
         {:ok, _} <- validate_methods_have_subtasks(domain),
         {:ok, _} <- validate_root_task_presence(domain),
         {:ok, _} <- validate_name_conflicts(domain),
         {:ok, _} <- validate_primitive_task_structure(domain),
         {:ok, _} <- validate_naming_conventions(domain),
         {:ok, _} <- validate_workflow_parameters(domain),
         {:ok, _} <- validate_costs_and_durations(domain) do
      :ok
    else
      {:error, errors} when is_list(errors) -> {:error, errors}
      {:error, error} -> {:error, [error]}
    end
  end

  def validate(_), do: {:error, "Invalid domain structure"}

  @doc "Validates that the domain is not empty"
  @spec validate_non_empty_domain(Domain.t()) :: validation_result
  def validate_non_empty_domain(%Domain{tasks: tasks, allowed_workflows: ops}) do
    dbug("Validating non-empty domain")

    cond do
      map_size(tasks) == 0 -> {:error, "Domain must contain at least one task"}
      map_size(ops) == 0 -> {:error, "Domain must contain at least one allowed workflow"}
      true -> {:ok, "Domain is not empty"}
    end
  end

  @doc "Validates unique names across tasks and callbacks"
  @spec validate_unique_names(Domain.t()) :: validation_result
  def validate_unique_names(%Domain{tasks: tasks, callbacks: callbacks}) do
    dbug("Validating unique names")
    task_names = Map.keys(tasks)
    callback_names = Map.keys(callbacks)
    all_names = task_names ++ callback_names
    unique_names = Enum.uniq(all_names)

    if length(all_names) == length(unique_names) do
      {:ok, "All names are unique"}
    else
      duplicates = all_names -- unique_names
      {:error, "Domain contains duplicate names: #{Enum.join(duplicates, ", ")}"}
    end
  end

  @doc "Validates that all subtasks refer to defined tasks"
  @spec validate_subtasks(Domain.t()) :: validation_result
  def validate_subtasks(%Domain{tasks: tasks}) do
    dbug("Validating subtasks")
    task_names = MapSet.new(Map.keys(tasks))

    result =
      Enum.reduce_while(tasks, [], fn
        {_, %CompoundTask{methods: methods}}, acc ->
          case validate_method_subtasks(methods, task_names) do
            :ok -> {:cont, acc}
            {:error, error} -> {:cont, [error | acc]}
          end

        _, acc ->
          {:cont, acc}
      end)

    case result do
      [] -> {:ok, "All subtasks are valid"}
      errors -> {:error, Enum.reverse(errors)}
    end
  end

  @doc "Validates that all allowed workflows are defined"
  @spec validate_allowed_workflows(Domain.t()) :: validation_result
  def validate_allowed_workflows(%Domain{tasks: tasks, allowed_workflows: allowed_ops}) do
    dbug("Validating allowed workflows")

    result =
      Enum.reduce(tasks, [], fn
        {_name, %PrimitiveTask{task: {action, _params}}}, acc ->
          action_string = Atom.to_string(action)

          if Enum.any?(allowed_ops, fn {name, module} ->
               name == action_string or module == action
             end) do
            acc
          else
            ["Action '#{action}' is not allowed" | acc]
          end

        _, acc ->
          acc
      end)

    case result do
      [] -> {:ok, "All actions are allowed"}
      errors -> {:error, errors}
    end
  end

  @doc "Validates that all referenced tasks are defined"
  @spec validate_defined_tasks(Domain.t()) :: validation_result
  @spec validate_defined_tasks(Domain.t()) :: validation_result
  def validate_defined_tasks(%Domain{tasks: tasks}) do
    dbug("Validating defined tasks")

    undefined_tasks =
      Enum.reduce(tasks, MapSet.new(), fn
        {_, %CompoundTask{methods: methods}}, acc ->
          Enum.reduce(methods, acc, fn
            %Method{subtasks: subtasks}, inner_acc ->
              collect_undefined_tasks(subtasks, tasks, inner_acc)

            method, inner_acc when is_map(method) ->
              collect_undefined_tasks(method[:subtasks] || [], tasks, inner_acc)
          end)

        _, acc ->
          acc
      end)

    if MapSet.size(undefined_tasks) == 0 do
      {:ok, "All referenced tasks are defined"}
    else
      {:error, "The following tasks are undefined: #{Enum.join(undefined_tasks, ", ")}"}
    end
  end

  @doc "Validates that callback names are unique"
  @spec validate_unique_callbacks(Domain.t()) :: validation_result
  def validate_unique_callbacks(%Domain{callbacks: callbacks}) do
    dbug("Validating unique callbacks")
    callback_names = Map.keys(callbacks)

    if length(callback_names) == length(Enum.uniq(callback_names)) do
      {:ok, "All callback names are unique"}
    else
      duplicates = callback_names -- Enum.uniq(callback_names)
      {:error, "Domain contains duplicate callback names: #{Enum.join(duplicates, ", ")}"}
    end
  end

  @doc "Validates that workflow modules implement the required run/3 function"
  @spec validate_workflow_module_interface(Domain.t()) :: validation_result
  def validate_workflow_module_interface(%Domain{allowed_workflows: ops}) do
    dbug("Validating workflow module interface")

    result =
      Enum.reduce(ops, [], fn {name, module}, acc ->
        if function_exported?(module, :run, 3) do
          acc
        else
          ["Workflow module '#{name}' does not implement run/3" | acc]
        end
      end)

    case result do
      [] -> {:ok, "All workflow modules implement run/3"}
      errors -> {:error, Enum.reverse(errors)}
    end
  end

  @doc "Validates callback function signatures and behavior"
  @spec validate_callback_signatures(Domain.t()) :: validation_result
  def validate_callback_signatures(%Domain{callbacks: callbacks}) do
    dbug("Validating callback signatures")

    result =
      Enum.reduce(callbacks, [], fn {name, callback}, acc ->
        cond do
          not is_function(callback, 1) ->
            ["Callback '#{name}' is not a function with arity 1" | acc]

          not valid_callback_return?(callback) ->
            ["Callback '#{name}' does not return a boolean or map" | acc]

          true ->
            acc
        end
      end)

    case result do
      [] -> {:ok, "All callbacks have valid signatures"}
      errors -> {:error, Enum.reverse(errors)}
    end
  end

  @doc "Validates that each method in compound tasks has at least one subtask"
  @spec validate_methods_have_subtasks(Domain.t()) :: validation_result
  def validate_methods_have_subtasks(%Domain{tasks: tasks}) do
    dbug("Validating methods have subtasks")

    result =
      Enum.reduce(tasks, [], fn
        {name, %CompoundTask{methods: methods}}, acc ->
          invalid_methods = Enum.filter(methods, &(length(&1.subtasks) == 0))

          if length(invalid_methods) > 0 do
            ["Compound task '#{name}' has methods without subtasks" | acc]
          else
            acc
          end

        _, acc ->
          acc
      end)

    case result do
      [] -> {:ok, "All methods have subtasks"}
      errors -> {:error, Enum.reverse(errors)}
    end
  end

  @doc "Validates the presence of at least one root task"
  @spec validate_root_task_presence(Domain.t()) :: validation_result
  def validate_root_task_presence(%Domain{root_tasks: root_tasks, tasks: tasks}) do
    dbug("Validating root task presence")

    cond do
      MapSet.size(root_tasks) == 0 ->
        {:error, "Domain must have at least one root task"}

      Enum.any?(root_tasks, fn name -> not Map.has_key?(tasks, name) end) ->
        {:error,
         "Some root tasks are not defined: #{root_tasks |> Enum.filter(&(not Map.has_key?(tasks, &1))) |> Enum.join(", ")}"}

      Enum.any?(root_tasks, fn name ->
        case Map.get(tasks, name) do
          %CompoundTask{} -> false
          _ -> true
        end
      end) ->
        {:error, "All root tasks must be compound tasks"}

      true ->
        {:ok, "Domain has valid root tasks"}
    end
  end

  @doc "Validates that there are no name conflicts between tasks and callbacks"
  @spec validate_name_conflicts(Domain.t()) :: validation_result
  def validate_name_conflicts(%Domain{tasks: tasks, callbacks: callbacks}) do
    dbug("Validating name conflicts")

    task_names = MapSet.new(Map.keys(tasks))
    callback_names = MapSet.new(Map.keys(callbacks))
    conflicts = MapSet.intersection(task_names, callback_names)

    if MapSet.size(conflicts) == 0 do
      {:ok, "No name conflicts between tasks and callbacks"}
    else
      {:error, "Name conflicts found: #{Enum.join(conflicts, ", ")}"}
    end
  end

  @doc "Validates the structure of primitive tasks"
  @spec validate_primitive_task_structure(Domain.t()) :: validation_result
  def validate_primitive_task_structure(%Domain{tasks: tasks}) do
    dbug("Validating primitive task structure")

    result =
      Enum.reduce(tasks, [], fn
        {name,
         %PrimitiveTask{
           task: task,
           cost: cost,
           duration: duration,
           scheduling_constraints: constraints
         }},
        acc ->
          errors = []

          # Validate task action
          errors =
            case validate_task_action(task) do
              :ok -> errors
              {:error, reason} -> ["Invalid task structure for '#{name}': #{reason}" | errors]
            end

          # Validate cost type and value
          errors =
            cond do
              is_nil(cost) ->
                errors

              not is_integer(cost) ->
                ["Invalid task structure for '#{name}': Cost must be an integer" | errors]

              cost < 0 ->
                ["Invalid task structure for '#{name}': Cost must be non-negative" | errors]

              true ->
                errors
            end

          # Validate duration type and value
          errors =
            cond do
              is_nil(duration) ->
                errors

              not is_integer(duration) ->
                ["Invalid task structure for '#{name}': Duration must be an integer" | errors]

              duration < 0 ->
                ["Invalid task structure for '#{name}': Duration must be non-negative" | errors]

              true ->
                errors
            end

          # Validate scheduling constraints
          errors =
            case validate_scheduling_constraints(constraints) do
              :ok -> errors
              {:error, reason} -> ["Invalid task structure for '#{name}': #{reason}" | errors]
            end

          errors ++ acc

        _, acc ->
          acc
      end)

    case result do
      [] -> {:ok, "All primitive tasks have valid structure"}
      errors -> {:error, Enum.reverse(errors)}
    end
  end

  @doc "Validates naming conventions for tasks and callbacks"
  @spec validate_naming_conventions(Domain.t()) :: validation_result
  def validate_naming_conventions(%Domain{tasks: tasks, callbacks: callbacks}) do
    dbug("Validating naming conventions")

    all_names = Map.keys(tasks) ++ Map.keys(callbacks)
    invalid_names = Enum.filter(all_names, &(!valid_name?(&1)))

    if length(invalid_names) == 0 do
      {:ok, "All names follow the naming convention"}
    else
      {:error, "Invalid names found: #{Enum.join(invalid_names, ", ")}"}
    end
  end

  @doc "Validates workflow parameters and options"
  @spec validate_workflow_parameters(Domain.t()) :: validation_result
  def validate_workflow_parameters(%Domain{tasks: tasks}) do
    dbug("Validating workflow parameters")

    result =
      Enum.reduce(tasks, [], fn
        {name, %PrimitiveTask{task: {action, params}}}, acc ->
          errors = []
          errors = if is_atom(action), do: errors, else: ["Invalid action for '#{name}'" | errors]
          errors = if is_list(params), do: errors, else: ["Invalid params for '#{name}'" | errors]
          errors ++ acc

        _, acc ->
          acc
      end)

    case result do
      [] -> {:ok, "All workflow parameters are valid"}
      errors -> {:error, Enum.reverse(errors)}
    end
  end

  @doc "Validates that costs and durations are non-negative"
  @spec validate_costs_and_durations(Domain.t()) :: validation_result
  def validate_costs_and_durations(%Domain{tasks: tasks}) do
    dbug("Validating costs and durations")

    result =
      Enum.reduce(tasks, [], fn
        {name, %PrimitiveTask{cost: cost, duration: duration}}, acc ->
          errors = []

          errors =
            if cost != nil && cost < 0 do
              ["Task '#{name}' has invalid cost: #{cost}" | errors]
            else
              errors
            end

          errors =
            if duration != nil && duration < 0 do
              ["Task '#{name}' has invalid duration: #{duration}" | errors]
            else
              errors
            end

          errors ++ acc

        _, acc ->
          acc
      end)

    case result do
      [] -> {:ok, "All costs and durations are valid"}
      errors -> {:error, Enum.reverse(errors)}
    end
  end

  # Helper functions

  defp validate_method_subtasks(methods, task_names) do
    Enum.reduce_while(methods, :ok, fn
      %Method{subtasks: subtasks}, _ ->
        case Enum.find(subtasks, &(not MapSet.member?(task_names, &1))) do
          nil ->
            {:cont, :ok}

          invalid_subtask ->
            {:halt, {:error, "Subtask '#{invalid_subtask}' does not refer to a valid task"}}
        end

      method, _ when is_map(method) ->
        case Enum.find(method[:subtasks] || [], &(not MapSet.member?(task_names, &1))) do
          nil ->
            {:cont, :ok}

          invalid_subtask ->
            {:halt, {:error, "Subtask '#{invalid_subtask}' does not refer to a valid task"}}
        end
    end)
  end

  defp collect_undefined_tasks(subtasks, tasks, acc) do
    Enum.reduce(subtasks, acc, fn subtask, set ->
      if Map.has_key?(tasks, subtask), do: set, else: MapSet.put(set, subtask)
    end)
  end

  defp valid_callback_return?(callback) do
    result = callback.(%{})
    is_boolean(result) or is_map(result)
  rescue
    _ -> false
  end

  defp validate_task_action({action, params}) when is_atom(action) and is_list(params), do: :ok

  defp validate_task_action(_), do: {:error, "Invalid Action structure"}

  defp valid_name?(name) do
    name = to_string(name)
    String.match?(name, ~r/^[a-z][a-z0-9_]*$/)
  end

  defp validate_scheduling_constraints(nil), do: :ok

  defp validate_scheduling_constraints(constraints) when is_map(constraints) do
    earliest = Map.get(constraints, :earliest_start_time)
    latest = Map.get(constraints, :latest_end_time)

    cond do
      not is_nil(earliest) and not is_integer(earliest) ->
        {:error, "earliest_start_time must be an integer"}

      not is_nil(latest) and not is_integer(latest) ->
        {:error, "latest_end_time must be an integer"}

      not is_nil(earliest) and earliest < 0 ->
        {:error, "earliest_start_time must be non-negative"}

      not is_nil(latest) and latest < 0 ->
        {:error, "latest_end_time must be non-negative"}

      not is_nil(earliest) and not is_nil(latest) and earliest > latest ->
        {:error, "earliest_start_time cannot be greater than latest_end_time"}

      map_size(constraints) > 0 and not Map.has_key?(constraints, :earliest_start_time) and
          not Map.has_key?(constraints, :latest_end_time) ->
        {:error,
         "scheduling_constraints can only contain earliest_start_time and latest_end_time"}

      true ->
        :ok
    end
  end

  defp validate_scheduling_constraints(_), do: {:error, "scheduling_constraints must be a map"}
end
