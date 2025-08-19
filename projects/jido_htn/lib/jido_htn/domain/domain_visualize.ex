defmodule Jido.HTN.Visualize do
  @moduledoc """
  Provides advanced visualization capabilities for Jido.HTN.Domain structures.
  """

  alias Jido.HTN.CompoundTask
  alias Jido.HTN.Domain
  alias Jido.HTN.PrimitiveTask

  @doc """
  Generates a detailed Mermaid diagram string from a Jido.HTN.Domain struct.

  ## Parameters

  - domain: A Jido.HTN.Domain struct

  ## Returns

  A string containing the Mermaid diagram code.
  """
  @spec generate_mermaid(Domain.t()) :: String.t()
  def generate_mermaid(%Domain{} = domain) do
    tasks = domain.tasks

    diagram =
      [
        "graph TD",
        generate_nodes(tasks),
        generate_edges(tasks),
        generate_task_details(tasks),
        generate_subgraphs(tasks),
        generate_legend(),
        generate_styles(tasks)
      ]
      |> List.flatten()
      |> Enum.join("\n")

    diagram
  end

  defp generate_nodes(tasks) do
    Enum.map(tasks, fn {name, task} ->
      case task do
        %CompoundTask{} -> "    #{node_id(name)}{{\"#{name}\"}}"
        %PrimitiveTask{} -> "    #{node_id(name)}[\"#{name}\"]"
      end
    end)
  end

  defp generate_edges(tasks) do
    Enum.flat_map(tasks, fn {name, task} ->
      case task do
        %CompoundTask{methods: methods} ->
          Enum.flat_map(methods, fn method ->
            subtasks = Map.get(method, :subtasks) || []
            conditions = Map.get(method, :conditions) || []
            condition_string = extract_conditions(conditions)

            Enum.map(subtasks, fn subtask ->
              "    #{node_id(name)} -->|\"#{condition_string}\"| #{node_id(subtask)}"
            end)
          end)

        _ ->
          []
      end
    end)
  end

  defp generate_task_details(tasks) do
    Enum.flat_map(tasks, fn {name, task} ->
      case task do
        %PrimitiveTask{} = pt ->
          [
            "    subgraph \"#{name} Details\"",
            "        #{node_id(name)}_pre[\"Preconditions:<br/>#{extract_conditions(pt.preconditions)}\"]",
            "        #{node_id(name)}_eff[\"Effects:<br/>#{extract_effects(pt.effects)}\"]",
            "        #{node_id(name)} --> #{node_id(name)}_pre",
            "        #{node_id(name)} --> #{node_id(name)}_eff",
            "    end"
          ]

        _ ->
          []
      end
    end)
  end

  defp generate_subgraphs(tasks) do
    compound_tasks =
      Enum.filter(tasks, fn {_, task} -> match?(%CompoundTask{}, task) end)

    primitive_tasks =
      Enum.filter(tasks, fn {_, task} -> match?(%PrimitiveTask{}, task) end)

    [
      "    subgraph Compound Tasks",
      Enum.map(compound_tasks, fn {name, _} -> "        #{node_id(name)}" end),
      "    end",
      "",
      "    subgraph Primitive Tasks",
      Enum.map(primitive_tasks, fn {name, _} -> "        #{node_id(name)}" end),
      "    end"
    ]
  end

  defp generate_legend do
    [
      "    subgraph Legend",
      "        compound_legend{{\"Compound Task\"}}",
      "        primitive_legend[\"Primitive Task\"]",
      "        condition_legend[\"Condition/Precondition/Effect\"]",
      "    end",
      "    class compound_legend compound;",
      "    class primitive_legend primitive;",
      "    class condition_legend details;"
    ]
  end

  defp generate_styles(tasks) do
    """
    classDef compound fill:#f9f,stroke:#333,stroke-width:2px;
    classDef primitive fill:#bbf,stroke:#333,stroke-width:2px;
    classDef details fill:#dfd,stroke:#333,stroke-width:1px;

    class #{get_compound_task_ids(tasks)} compound;
    class #{get_primitive_task_ids(tasks)} primitive;
    class #{get_detail_ids(tasks)} details;
    """
  end

  defp node_id(name) do
    "node_" <> String.replace(name, ~r/[^a-zA-Z0-9]/, "_")
  end

  defp extract_conditions(conditions) do
    conditions
    |> Enum.map(&extract_function_name/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.join(", ")
  end

  defp extract_effects(effects) do
    effects
    |> Enum.map(&extract_function_name/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.join(", ")
  end

  defp extract_function_name(func) when is_function(func) do
    func
    |> Function.info()
    |> Keyword.get(:name)
    |> case do
      nil -> nil
      name -> name |> Atom.to_string() |> String.replace("?", "")
    end
  end

  defp extract_function_name(_), do: nil

  defp get_compound_task_ids(tasks) do
    tasks
    |> Enum.filter(fn {_, task} -> match?(%CompoundTask{}, task) end)
    |> Enum.map_join(",", fn {name, _} -> node_id(name) end)
  end

  defp get_primitive_task_ids(tasks) do
    tasks
    |> Enum.filter(fn {_, task} -> match?(%PrimitiveTask{}, task) end)
    |> Enum.map_join(",", fn {name, _} -> node_id(name) end)
  end

  defp get_detail_ids(tasks) do
    tasks
    |> Enum.filter(fn {_, task} -> match?(%PrimitiveTask{}, task) end)
    |> Enum.flat_map(fn {name, _} -> ["#{node_id(name)}_pre", "#{node_id(name)}_eff"] end)
    |> Enum.join(",")
  end
end
