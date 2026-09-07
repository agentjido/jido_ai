defmodule Jido.AI.Runtime.Preflight do
  @moduledoc false

  def check(profile, batch, context, deadline) do
    with :ok <- each(batch, &Jido.AI.Control.check(profile, :operation, &1, context, deadline)),
         :ok <- each(batch, &legacy(&1, context, deadline)) do
      :ok
    else
      {:error, _} = error ->
        Jido.AI.Session.failure_type(context, :tool_guardrail)
        error
    end
  end

  defp each(batch, check) do
    Enum.reduce_while(batch, :ok, fn call, :ok ->
      case check.(call) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp legacy(call, context, deadline) do
    if is_function(context[:__tool_guardrail_callback__], 1) do
      remaining = deadline - System.monotonic_time(:millisecond)

      if remaining > 0 do
        case Jido.Exec.run(Jido.AI.Runtime.ToolGuardrail, %{call: call}, context,
               timeout: remaining
             ) do
          {:ok, _} -> :ok
          error -> error
        end
      else
        Jido.AI.Profile.error("controls.operation", "AI request deadline reached")
      end
    else
      :ok
    end
  end
end

defmodule Jido.AI.Runtime.ToolGuardrail do
  @moduledoc false
  use Jido.Action, name: "ai_tool_guardrail"

  def run(params, context), do: Jido.AI.Error.capture(fn -> execute(params, context) end)

  defp execute(%{call: call}, context) do
    input = %{
      tool_name: call.name,
      tool_call_id: call.id,
      arguments: call.prepared_arguments,
      validated_arguments: call.arguments,
      context: context
    }

    case context.__tool_guardrail_callback__.(input) do
      :ok -> {:ok, %{}}
      {:error, _} = error -> error
      {:interrupt, value} -> {:error, {:interrupt, value}}
      other -> {:error, {:tool_guardrail_callback_invalid_result, other}}
    end
  rescue
    error -> {:error, {:tool_guardrail_callback_failed, Exception.message(error)}}
  catch
    kind, reason -> {:error, {:tool_guardrail_callback_failed, {kind, reason}}}
  end
end
