defmodule Jido.AI.ToolInterceptor do
  @moduledoc """
  Optional AI-agent callbacks for canonical tool-call interception.

  Tool-capable agent strategies invoke these hooks around one logical tool
  execution. Modules that do not export a hook use identity behavior.

  `before_tool_call/2` runs after the runtime resolves the action module and
  before argument validation, execution, and retries. It can change only the
  `:arguments` map. The tool call `:id`, `:name`, and `:action_module` are
  immutable.

  `after_tool_call/3` runs once after retries produce a final canonical result.
  It can change the result payload and effects. The runtime applies the active
  effect policy to the returned effects.

  Hooks run in the strategy execution path. They must return quickly and must
  not depend on being called from the action process. A callback error, invalid
  return, exception, throw, or exit stops the current tool round with a
  structured interceptor error.

  These hooks apply to agent-managed tool execution. Direct calls through
  `Jido.AI.Turn`, `Jido.Exec`, or the standalone tool-calling actions do not
  invoke agent callbacks.
  """

  alias Jido.AI.Effects

  @type tool_call :: %{
          required(:id) => String.t(),
          required(:name) => String.t(),
          required(:arguments) => map(),
          required(:action_module) => module()
        }

  @type tool_result :: {:ok, term(), [term()]} | {:error, term(), [term()]}

  @doc """
  Transforms a resolved tool call before argument validation and execution.

  The callback can change only `tool_call.arguments`. Return `{:interrupt,
  value}` to stop the current tool round without executing the tool.
  """
  @callback before_tool_call(tool_call(), map()) ::
              {:ok, tool_call()} | {:error, term()} | {:interrupt, term()}

  @doc """
  Transforms the final canonical result after tool retries finish.

  Return the transformed result inside `{:ok, result}`. Return `{:error,
  reason}` to stop the current tool round because the interceptor failed.
  """
  @callback after_tool_call(tool_call(), tool_result(), map()) ::
              {:ok, tool_result()} | {:error, term()}

  @optional_callbacks before_tool_call: 2, after_tool_call: 3

  @doc false
  @spec before_tool_call(module() | nil, map(), map()) ::
          {:ok, tool_call()} | {:error, term()} | {:interrupt, term()}
  def before_tool_call(agent_module, tool_call, context) when is_map(tool_call) and is_map(context) do
    with {:ok, original} <- normalize_tool_call(tool_call),
         {:ok, callback_result} <- invoke_before_callback(agent_module, original, context) do
      normalize_before_result(callback_result, original, agent_module)
    end
  end

  def before_tool_call(_agent_module, tool_call, _context) do
    {:error, {:invalid_tool_call, tool_call}}
  end

  @doc false
  @spec after_tool_call(module() | nil, tool_call(), term(), map()) :: {:ok, tool_result()} | {:error, term()}
  def after_tool_call(agent_module, tool_call, result, context) when is_map(tool_call) and is_map(context) do
    with {:ok, normalized_call} <- normalize_tool_call(tool_call),
         normalized_result <- Effects.normalize_result(result),
         {:ok, callback_result} <-
           invoke_after_callback(agent_module, normalized_call, normalized_result, context) do
      normalize_after_result(callback_result, agent_module, context)
    end
  end

  def after_tool_call(agent_module, tool_call, _result, _context) do
    {:error, {:invalid_tool_call, agent_module, tool_call}}
  end

  defp exports_callback?(module, name, arity) when is_atom(module) and not is_nil(module) do
    Code.ensure_loaded?(module) and function_exported?(module, name, arity)
  end

  defp exports_callback?(_module, _name, _arity), do: false

  defp invoke_before_callback(agent_module, tool_call, context) do
    case exports_callback?(agent_module, :before_tool_call, 2) do
      true -> invoke_callback(agent_module, :before_tool_call, [tool_call, context])
      false -> {:ok, {:ok, tool_call}}
    end
  end

  defp invoke_after_callback(agent_module, tool_call, result, context) do
    case exports_callback?(agent_module, :after_tool_call, 3) do
      true -> invoke_callback(agent_module, :after_tool_call, [tool_call, result, context])
      false -> {:ok, {:ok, result}}
    end
  end

  defp invoke_callback(agent_module, callback, args) do
    {:ok, apply(agent_module, callback, args)}
  rescue
    error -> {:error, callback_exception(callback, agent_module, error)}
  catch
    kind, reason -> {:error, callback_catch(callback, agent_module, kind, reason)}
  end

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

  defp normalize_after_result({:ok, result}, agent_module, context) do
    case canonical_tool_result(result) do
      {:ok, normalized_result} ->
        policy = Effects.policy_from_context(context, Effects.default_policy())
        {filtered_result, _stats} = Effects.filter_result(normalized_result, policy)
        {:ok, filtered_result}

      :error ->
        {:error, {:invalid_tool_interceptor_result, :after_tool_call, agent_module, {:ok, result}}}
    end
  end

  defp normalize_after_result({:error, reason}, agent_module, _context) do
    {:error, {:tool_interceptor, :after_tool_call, agent_module, reason}}
  end

  defp normalize_after_result(other, agent_module, _context) do
    {:error, {:invalid_tool_interceptor_result, :after_tool_call, agent_module, other}}
  end

  defp canonical_tool_result({status, _payload, effects} = result)
       when status in [:ok, :error] and is_list(effects),
       do: {:ok, result}

  defp canonical_tool_result(_result), do: :error

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

  defp callback_catch(callback, agent_module, kind, reason) do
    {:tool_interceptor_catch, callback, agent_module, %{kind: kind, reason: inspect(reason)}}
  end
end
