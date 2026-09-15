defmodule Jido.AI.ToolCatalog do
  @moduledoc "One validated catalog for provider tool schemas and core execution."
  alias Jido.AI.Profile

  @doc "Checks static Action and Flow tool declarations without executing them."
  def new(tools) do
    with {:ok, entries} <- Profile.traverse(tools, &entry/1) do
      names = Enum.map(entries, & &1.name)

      if names == Enum.uniq(names),
        do: {:ok, entries},
        else: Profile.error("tools", "Duplicate public tool name")
    end
  end

  @doc false
  def from_input(input, defaults \\ %{}) do
    with {:ok, tools} <- Jido.AI.Reasoning.ReAct.ToolSelection.normalize_input(input) do
      tools
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {name, module} ->
        Map.merge(defaults, %{
          name: name,
          target: module,
          description: module.description() || name
        })
      end)
      |> new()
    end
  end

  defp entry(value) do
    with {:ok, value} <-
           Profile.fields(
             value,
             [
               :name,
               :target,
               :description,
               :forward_context,
               :timeout,
               :max_retries,
               :retry_backoff,
               :idempotency,
               :approval,
               :metadata
             ],
             "tools"
           ),
         {:ok, name} <- tool_name(value[:name], value[:target]),
         value =
           value
           |> Map.put(:name, name)
           |> normalize_portable_options(),
         true <- is_binary(value[:name]) and Regex.match?(~r/\A[a-zA-Z0-9_-]{1,64}\z/, value.name),
         :ok <- compiled(value[:target]),
         :ok <- Jido.Executable.validate(value[:target]),
         :ok <- flow_contract(value[:target]),
         {:ok, schema} <- schema(value.target),
         {:ok, _} <-
           ReqLLM.Tool.new(
             name: value.name,
             description: Map.get(value, :description, value.name),
             parameter_schema: Jido.AI.ToolAdapter.parameter_schema(schema, strict?(value.target)),
             strict: strict?(value.target),
             callback: &__MODULE__.unreachable/1
           ),
         fields = Map.get(value, :forward_context, :public),
         timeout = Map.get(value, :timeout, 5_000),
         true <- valid_context_policy?(fields),
         true <- is_integer(timeout) and timeout > 0,
         true <- nonnegative?(Map.get(value, :max_retries, 0)),
         true <- nonnegative?(Map.get(value, :retry_backoff, 0)),
         true <- Map.get(value, :idempotency, :idempotent) in [:idempotent, :unsafe_once],
         true <- is_map(Map.get(value, :metadata, %{})) do
      value =
        value
        |> Map.update(:metadata, %{}, &Profile.portable_data/1)
        |> Map.update(:approval, nil, &Profile.portable_data/1)

      {:ok,
       Map.merge(
         %{
           description: value.name,
           forward_context: fields,
           timeout: timeout,
           idempotency: :idempotent,
           metadata: %{}
         },
         value
       )}
    else
      false -> Profile.error("tools", "Invalid name, context projection, or timeout")
      {:error, reason} when is_exception(reason) -> {:error, reason}
      {:error, reason} -> Profile.error("tools", inspect(reason))
    end
  end

  defp nonnegative?(value), do: is_integer(value) and value >= 0

  defp valid_context_policy?(value) when value in [:all, :public, :none], do: true
  defp valid_context_policy?({kind, fields}) when kind in [:only, :except], do: atom_list?(fields)
  defp valid_context_policy?(fields), do: atom_list?(fields)

  defp atom_list?(fields), do: is_list(fields) and Enum.all?(fields, &is_atom/1)

  defp normalize_portable_options(value) do
    value
    |> normalize_context_policy()
    |> normalize_known(:forward_context, [:all, :public, :none])
    |> normalize_known(:idempotency, [:idempotent, :unsafe_once])
  end

  defp normalize_context_policy(value) do
    case Map.get(value, :forward_context) do
      %{} = policy ->
        Enum.find_value([:only, :except], value, fn kind ->
          fields = Map.get(policy, kind, Map.get(policy, Atom.to_string(kind)))

          if is_list(fields) do
            case existing_fields(fields) do
              {:ok, fields} -> Map.put(value, :forward_context, {kind, fields})
              :error -> value
            end
          end
        end)

      _ ->
        value
    end
  end

  defp existing_fields(fields) do
    fields
    |> Enum.reduce_while({:ok, []}, fn
      field, {:ok, acc} when is_atom(field) ->
        {:cont, {:ok, [field | acc]}}

      field, {:ok, acc} when is_binary(field) ->
        try do
          {:cont, {:ok, [String.to_existing_atom(field) | acc]}}
        rescue
          ArgumentError -> {:halt, :error}
        end

      _, _ ->
        {:halt, :error}
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      :error -> :error
    end
  end

  defp normalize_known(value, key, allowed) do
    case Map.get(value, key) do
      text when is_binary(text) ->
        case Enum.find(allowed, &(Atom.to_string(&1) == text)) do
          nil -> value
          atom -> Map.put(value, key, atom)
        end

      _ ->
        value
    end
  end

  defp tool_name(name, _) when is_atom(name) and name not in [nil, true, false],
    do: {:ok, Atom.to_string(name)}

  defp tool_name(name, _) when is_binary(name), do: {:ok, name}
  defp tool_name(nil, %Jido.Flow{name: name}) when is_binary(name), do: {:ok, name}

  defp tool_name(nil, module) when is_atom(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :name, 0),
      do: {:ok, module.name()},
      else: Profile.error("tools.name", "Tool has no public name")
  end

  defp tool_name(_, _), do: Profile.error("tools.name", "Expected a public tool name")

  defp compiled(%Jido.Flow{}), do: :ok

  defp compiled(module) when is_atom(module) do
    case Code.ensure_compiled(module) do
      {:module, _} -> :ok
      _ -> Profile.error("tools", "Tool module is not available")
    end
  end

  defp compiled(_), do: Profile.error("tools", "Expected an Action or Flow")

  defp flow_contract(target) do
    case Jido.Executable.resolve(target) do
      {:ok, %{kind: :action}} ->
        :ok

      {:ok, %{kind: :flow}} ->
        flow = if is_struct(target, Jido.Flow), do: target, else: target.flow()
        with {:ok, _} <- Jido.Flow.validate_executable(flow), do: :ok
    end
  end

  defp schema(%Jido.Flow{schema: schema}), do: {:ok, schema}

  defp schema(module) do
    if compiled(module) == :ok and function_exported?(module, :schema, 0),
      do: {:ok, module.schema()},
      else: Profile.error("tools", "Tool must expose a schema")
  end

  @doc false
  def definitions(catalog) do
    Enum.map(catalog, fn tool ->
      {:ok, schema} = schema(tool.target)

      ReqLLM.Tool.new!(
        name: tool.name,
        description: tool.description,
        parameter_schema: Jido.AI.ToolAdapter.parameter_schema(schema, strict?(tool.target)),
        strict: strict?(tool.target),
        callback: &__MODULE__.unreachable/1
      )
    end)
  end

  @doc false
  def unreachable(_), do: raise("Tool execution belongs to Jido.Exec")

  defp strict?(module) when is_atom(module),
    do: function_exported?(module, :strict?, 0) and module.strict?()

  defp strict?(_), do: false

  @doc "Validates the full model batch before any tool starts."
  def admit(catalog, calls, prepare \\ fn call -> {:ok, call} end) do
    with {:ok, batch} <-
           Profile.traverse(calls, fn raw ->
             call = ReqLLM.ToolCall.to_map(raw)

             with tool when not is_nil(tool) <- Enum.find(catalog, &(&1.name == call.name)),
                  true <- is_binary(call.id) and call.id != "",
                  true <- is_map(call.arguments) do
               {:ok, Map.put(call, :tool, tool)}
             else
               _ ->
                 Profile.error(
                   "tools.batch",
                   "Unknown tool, invalid call ID, or invalid arguments"
                 )
             end
           end),
         true <- length(batch) == length(Enum.uniq_by(batch, & &1.id)),
         {:ok, batch} <- Profile.traverse(batch, prepare) do
      Profile.traverse(batch, fn call ->
        with {:ok, schema} <- schema(call.tool.target),
             arguments = Jido.AI.SchemaInput.normalize_tool(schema, call.arguments),
             {:ok, arguments} <- validate(call.tool.target, arguments),
             do:
               {:ok,
                call
                |> Map.put(:prepared_arguments, call.arguments)
                |> Map.put(:arguments, arguments)}
      end)
    else
      false -> Profile.error("tools.batch", "Duplicate call ID")
      error -> error
    end
  end

  defp validate(%Jido.Flow{schema: schema}, args),
    do: Jido.Action.Validation.open_validate(schema, args, %{context: "AI Flow tool"})

  defp validate(module, args), do: module.validate_params(args)
end
