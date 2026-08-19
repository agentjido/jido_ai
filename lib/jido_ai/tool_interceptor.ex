defmodule Jido.AI.ToolInterceptor do
  @moduledoc """
  Optional AI-agent callbacks for canonical tool-call interception.

  These hooks are invoked by tool-capable strategies around a logical tool
  execution. They are optional: modules that do not export the callbacks use
  identity behavior.
  """

  alias Jido.AI.Effects

  @type tool_call :: %{
          required(:id) => String.t(),
          required(:name) => String.t(),
          required(:arguments) => map(),
          required(:action_module) => module()
        }

  @type tool_result :: {:ok, term(), [term()]} | {:error, term(), [term()]}

  @callback before_tool_call(tool_call(), map()) ::
              {:ok, tool_call()} | {:error, term()} | {:interrupt, term()}

  @callback after_tool_call(tool_call(), tool_result(), map()) ::
              {:ok, tool_result()} | {:error, term()}

  @doc false
  @spec before_tool_call(module() | nil, map(), map()) ::
          {:ok, tool_call()} | {:error, term()} | {:interrupt, term()}
  def before_tool_call(agent_module, tool_call, context) when is_map(tool_call) and is_map(context) do
    with {:ok, original} <- normalize_tool_call(tool_call) do
      case exports_callback?(agent_module, :before_tool_call, 2) do
        true ->
          agent_module.before_tool_call(original, context)
          |> normalize_before_result(original, agent_module)

        false ->
          {:ok, original}
      end
    end
  rescue
    error -> {:error, callback_exception(:before_tool_call, agent_module, error)}
  end

  def before_tool_call(_agent_module, tool_call, _context) do
    {:error, {:invalid_tool_call, tool_call}}
  end

  @doc false
  @spec after_tool_call(module() | nil, tool_call(), term(), map()) :: {:ok, tool_result()} | {:error, term()}
  def after_tool_call(agent_module, tool_call, result, context) when is_map(tool_call) and is_map(context) do
    with {:ok, normalized_call} <- normalize_tool_call(tool_call) do
      normalized_result = Effects.normalize_result(result)

      transformed_result =
        case exports_callback?(agent_module, :after_tool_call, 3) do
          true -> agent_module.after_tool_call(normalized_call, normalized_result, context)
          false -> {:ok, normalized_result}
        end

      case transformed_result do
        {:ok, result} ->
          policy = Effects.policy_from_context(context, Effects.default_policy())
          {filtered_result, _stats} = Effects.filter_result(result, policy)
          {:ok, filtered_result}

        {:error, reason} ->
          {:error, {:tool_interceptor, :after_tool_call, agent_module, reason}}

        other ->
          {:error, {:invalid_tool_interceptor_result, :after_tool_call, agent_module, other}}
      end
    end
  rescue
    error -> {:error, callback_exception(:after_tool_call, agent_module, error)}
  end

  def after_tool_call(agent_module, tool_call, _result, _context) do
    {:error, {:invalid_tool_call, agent_module, tool_call}}
  end

  defp exports_callback?(module, name, arity) when is_atom(module) and not is_nil(module) do
    Code.ensure_loaded?(module) and function_exported?(module, name, arity)
  end

  defp exports_callback?(_module, _name, _arity), do: false

  defp normalize_before_result({:ok, %{} = tool_call}, original, agent_module) do
    with {:ok, normalized} <- normalize_tool_call(tool_call),
         :ok <- preserve_identity(original, normalized, agent_module) do
      {:ok, normalized}
    end
  end

  defp normalize_before_result({:error, reason}, _original, agent_module) do
    {:error, {:tool_interceptor, :before_tool_call, agent_module, reason}}
  end

  defp normalize_before_result({:interrupt, value}, _original, _agent_module), do: {:interrupt, value}

  defp normalize_before_result(other, _original, agent_module) do
    {:error, {:invalid_tool_interceptor_result, :before_tool_call, agent_module, other}}
  end

  defp normalize_tool_call(%{} = tool_call) do
    id = Map.get(tool_call, :id, Map.get(tool_call, "id", Map.get(tool_call, :call_id, Map.get(tool_call, "call_id"))))

    name =
      Map.get(
        tool_call,
        :name,
        Map.get(tool_call, "name", Map.get(tool_call, :tool_name, Map.get(tool_call, "tool_name")))
      )

    arguments = Map.get(tool_call, :arguments, Map.get(tool_call, "arguments", %{})) || %{}
    action_module = Map.get(tool_call, :action_module, Map.get(tool_call, "action_module"))

    cond do
      not is_binary(id) -> {:error, {:invalid_tool_call_id, id}}
      not is_binary(name) -> {:error, {:invalid_tool_call_name, name}}
      not is_map(arguments) -> {:error, {:invalid_tool_call_arguments, arguments}}
      not is_atom(action_module) or is_nil(action_module) -> {:error, {:invalid_tool_call_action_module, action_module}}
      true -> {:ok, %{id: id, name: name, arguments: arguments, action_module: action_module}}
    end
  end

  defp preserve_identity(original, transformed, agent_module) do
    cond do
      transformed.id != original.id ->
        {:error, {:tool_interceptor_changed_id, agent_module, original.id, transformed.id}}

      transformed.name != original.name ->
        {:error, {:tool_interceptor_changed_name, agent_module, original.name, transformed.name}}

      transformed.action_module != original.action_module ->
        {:error,
         {:tool_interceptor_changed_action_module, agent_module, original.action_module, transformed.action_module}}

      true ->
        :ok
    end
  end

  defp callback_exception(callback, agent_module, error) do
    {:tool_interceptor_exception, callback, agent_module, %{type: error.__struct__, message: Exception.message(error)}}
  end
end
