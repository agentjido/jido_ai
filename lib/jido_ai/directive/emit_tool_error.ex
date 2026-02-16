defmodule Jido.AI.Directive.EmitToolError do
  @moduledoc """
  Directive to immediately emit a tool error result signal.

  Used when a tool cannot be executed (e.g., unknown tool name, configuration error).
  This directive ensures the Machine receives a tool_result signal and doesn't deadlock
  waiting for a response that will never arrive.

  Unlike `ToolExec`, this directive does not spawn a task - it synchronously emits
  an error signal back to the agent.
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              id: Zoi.string(description: "Tool call ID from LLM (ReqLLM.ToolCall.id)"),
              tool_name: Zoi.string(description: "Name of the tool that could not be resolved"),
              error: Zoi.any(description: "Error tuple or map describing the failure")
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc false
  def schema, do: @schema

  @doc "Create a new EmitToolError directive."
  def new!(attrs) when is_map(attrs) do
    case Zoi.parse(@schema, attrs) do
      {:ok, directive} -> directive
      {:error, errors} -> raise "Invalid EmitToolError: #{inspect(errors)}"
    end
  end
end

defimpl Jido.AgentServer.DirectiveExec, for: Jido.AI.Directive.EmitToolError do
  @moduledoc """
  Immediately emits a tool error result signal without spawning a task.

  Used when a tool cannot be resolved (Issue #1 fix). This ensures the Machine
  receives a tool_result signal for every pending tool call, preventing deadlock.
  """

  alias Jido.AI.Signal

  def exec(directive, _input_signal, state) do
    %{
      id: call_id,
      tool_name: tool_name,
      error: error
    } = directive

    agent_pid = self()

    # Emit the error result synchronously (no task needed)
    signal =
      Signal.ToolResult.new!(%{
        call_id: call_id,
        tool_name: tool_name,
        result: {:error, error}
      })

    Jido.AgentServer.cast(agent_pid, signal)

    {:ok, state}
  end
end
