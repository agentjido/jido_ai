defmodule Jido.AI.Plugin.Authoring do
  @moduledoc false

  alias Jido.Agent.Error
  alias Jido.Authoring.Registry

  @config_fields ~w(model instructions tools controls)
  @control_fields ~w(timeout max_iterations max_model_calls max_tool_calls input output)
  @tool_fields ~w(kind target name description timeout)

  @doc false
  def encode(
        %{model: model, instructions: instructions, tools: tools, controls: controls} = config,
        %Registry{} = registry
      )
      when map_size(config) == 4 do
    with {:ok, model} <- encode_model(model),
         {:ok, tools} <- traverse(tools, &encode_tool(&1, registry)),
         {:ok, controls} <- encode_controls(controls, registry) do
      encoded = %{
        "model" => model,
        "instructions" => instructions,
        "tools" => tools,
        "controls" => controls
      }

      {:ok, encoded}
    end
  end

  def encode(data, %Registry{}),
    do: invalid([], "Invalid Jido AI authoring data", %{value: data})

  @doc false
  def decode(config, %Registry{} = registry) do
    with :ok <- object(config, @config_fields, [], []),
         {:ok, model} <- decode_model(config["model"]),
         :ok <- string(config["instructions"], ["instructions"]),
         {:ok, tools} <-
           traverse(config["tools"], &decode_tool(&1, registry), ["tools"]),
         {:ok, controls} <- decode_controls(config["controls"], registry) do
      decoded = %{
        model: model,
        instructions: config["instructions"],
        tools: tools,
        controls: controls
      }

      {:ok, decoded}
    end
  end

  defp encode_model(model) when is_binary(model),
    do: {:ok, %{"kind" => "direct", "value" => model}}

  defp encode_model(model) when is_atom(model) and model not in [nil, true, false],
    do: {:ok, %{"kind" => "alias", "value" => Atom.to_string(model)}}

  defp encode_model(model),
    do: invalid(["model"], "Invalid AI model", %{value: model})

  defp decode_model(%{"kind" => "direct", "value" => value} = model)
       when map_size(model) == 2 and is_binary(value) and byte_size(value) > 0,
       do: {:ok, value}

  defp decode_model(%{"kind" => "alias", "value" => value} = model)
       when map_size(model) == 2 and is_binary(value) and byte_size(value) > 0 do
    case Enum.find(Map.keys(Jido.AI.Models.aliases()), fn
           alias_name when is_atom(alias_name) -> Atom.to_string(alias_name) == value
           _other -> false
         end) do
      nil -> invalid(["model"], "Unknown AI model alias", %{alias: value})
      alias_name -> {:ok, alias_name}
    end
  end

  defp decode_model(model),
    do: invalid(["model"], "Invalid AI model document", %{value: model})

  defp encode_tool(
         %{
           kind: kind,
           target: target,
           name: name,
           description: description,
           timeout: timeout
         },
         registry
       )
       when kind in [:action, :flow] do
    with {:ok, target} <- Registry.encode_reference(registry, kind, target) do
      {:ok,
       %{
         "kind" => Atom.to_string(kind),
         "target" => target,
         "name" => name,
         "description" => description,
         "timeout" => timeout
       }}
    end
  end

  defp encode_tool(tool, _registry),
    do: invalid(["tools"], "Invalid AI tool", %{value: tool})

  defp decode_tool(tool, registry) do
    with :ok <- object(tool, @tool_fields, [], []),
         {:ok, kind} <- executable_kind(tool["kind"]),
         {:ok, target} <- Registry.decode_reference(registry, tool["target"], kind),
         :ok <- string(tool["name"], ["name"]),
         :ok <- string(tool["description"], ["description"]),
         :ok <- positive(tool["timeout"], ["timeout"]) do
      {:ok,
       %{
         kind: kind,
         target: target,
         name: tool["name"],
         description: tool["description"],
         timeout: tool["timeout"]
       }}
    end
  end

  defp executable_kind("action"), do: {:ok, :action}
  defp executable_kind("flow"), do: {:ok, :flow}
  defp executable_kind(value), do: invalid(["kind"], "Invalid AI tool kind", %{value: value})

  defp encode_controls(controls, registry) when is_map(controls) do
    with {:ok, input} <- encode_references(controls.input, :action, registry),
         {:ok, output} <- encode_references(controls.output, :action, registry) do
      {:ok,
       %{
         "timeout" => controls.timeout,
         "max_iterations" => controls.max_iterations,
         "max_model_calls" => controls.max_model_calls,
         "max_tool_calls" => controls.max_tool_calls,
         "input" => input,
         "output" => output
       }}
    end
  end

  defp encode_controls(controls, _registry),
    do: invalid(["controls"], "Invalid AI controls", %{value: controls})

  defp decode_controls(controls, registry) do
    with :ok <- object(controls, @control_fields, [], ["controls"]),
         :ok <- positive(controls["timeout"], ["controls", "timeout"]),
         :ok <-
           positive(
             controls["max_iterations"],
             ["controls", "max_iterations"]
           ),
         :ok <-
           positive(
             controls["max_model_calls"],
             ["controls", "max_model_calls"]
           ),
         :ok <-
           positive(controls["max_tool_calls"], ["controls", "max_tool_calls"]),
         {:ok, input} <-
           decode_references(
             controls["input"],
             :action,
             registry,
             ["controls", "input"]
           ),
         {:ok, output} <-
           decode_references(
             controls["output"],
             :action,
             registry,
             ["controls", "output"]
           ) do
      {:ok,
       %{
         timeout: controls["timeout"],
         max_iterations: controls["max_iterations"],
         max_model_calls: controls["max_model_calls"],
         max_tool_calls: controls["max_tool_calls"],
         input: input,
         output: output
       }}
    end
  end

  defp encode_references(values, kind, registry),
    do: traverse(values, &Registry.encode_reference(registry, kind, &1))

  defp decode_references(values, kind, registry, path),
    do: traverse(values, &Registry.decode_reference(registry, &1, kind), path)

  defp object(value, required, optional, path)
       when is_map(value) and not is_struct(value) do
    keys = Map.keys(value)

    if required -- keys == [] and keys -- (required ++ optional) == [],
      do: :ok,
      else: invalid(path, "Unknown or missing Jido AI authoring fields", %{fields: keys})
  end

  defp object(value, _required, _optional, path),
    do: invalid(path, "Expected a Jido AI authoring object", %{value: value})

  defp string(value, _path) when is_binary(value), do: :ok
  defp string(value, path), do: invalid(path, "Expected a string", %{value: value})

  defp positive(value, _path) when is_integer(value) and value > 0, do: :ok
  defp positive(value, path), do: invalid(path, "Expected a positive integer", %{value: value})

  defp traverse(values, mapper, path \\ [])

  defp traverse(values, mapper, path) when is_list(values) do
    if List.improper?(values) do
      invalid(path, "Expected a proper list")
    else
      values
      |> Enum.with_index()
      |> Enum.reduce_while({:ok, []}, fn {value, index}, {:ok, result} ->
        case mapper.(value) do
          {:ok, value} -> {:cont, {:ok, [value | result]}}
          {:error, error} -> {:halt, {:error, prefix(error, path ++ [index])}}
        end
      end)
      |> reverse()
    end
  end

  defp traverse(value, _mapper, path), do: invalid(path, "Expected a proper list", %{value: value})

  defp reverse({:ok, values}), do: {:ok, Enum.reverse(values)}
  defp reverse(error), do: error

  defp prefix(%{path: error_path} = error, path) when is_list(error_path),
    do: %{error | path: path ++ error_path}

  defp prefix(error, _path), do: error

  defp invalid(path, message, details \\ %{}),
    do: Error.fail(:invalid_ai_authoring_data, path, message, details)
end
