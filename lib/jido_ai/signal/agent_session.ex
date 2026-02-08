if Code.ensure_loaded?(AgentSessionManager.SessionManager) do
  defmodule Jido.AI.Signal.AgentSession do
    @moduledoc """
    Signal types for autonomous agent session events.

    These signals wrap normalized events from `agent_session_manager` into the
    jido signal system. They are observational — jido_ai watches what the
    autonomous agent does but does not control it.

    ## Signal Types

    - `Started` - Agent session began execution (`ai.agent_session.started`)
    - `Message` - Text output from the agent (`ai.agent_session.message`)
    - `ToolCall` - Agent invoked a tool (`ai.agent_session.tool_call`)
    - `Progress` - Progress update for long-running sessions (`ai.agent_session.progress`)
    - `Completed` - Agent finished successfully (`ai.agent_session.completed`)
    - `Failed` - Agent failed or was cancelled (`ai.agent_session.failed`)

    ## Helper Functions

    - `from_event/2` - Convert an agent_session_manager event to a jido signal
    - `completed/2` - Build a Completed signal from a run result
    - `failed/2` - Build a Failed signal from an error
    """

    defmodule Started do
      @moduledoc """
      Signal emitted when an agent session begins execution.

      ## Data Fields

      - `:session_id` (required) - Session identifier
      - `:run_id` (required) - Run identifier
      - `:directive_id` (optional) - Originating directive ID
      - `:adapter` (optional) - Adapter module used
      - `:model` (optional) - Model identifier
      - `:input` (optional) - Input prompt sent to the agent
      - `:metadata` (optional) - Arbitrary metadata
      """

      use Jido.Signal,
        type: "ai.agent_session.started",
        default_source: "/ai/agent_session",
        schema: [
          session_id: [type: :string, required: true, doc: "Session identifier"],
          run_id: [type: :string, required: true, doc: "Run identifier"],
          directive_id: [type: :string, doc: "Originating directive ID"],
          adapter: [type: :atom, doc: "Adapter module used"],
          model: [type: :string, doc: "Model identifier"],
          input: [type: :string, doc: "Input prompt sent to the agent"],
          metadata: [type: :map, default: %{}, doc: "Arbitrary metadata"]
        ]
    end

    defmodule Message do
      @moduledoc """
      Signal for text output from the agent (streaming or complete).

      ## Data Fields

      - `:session_id` (required) - Session identifier
      - `:run_id` (required) - Run identifier
      - `:content` (required) - Text content
      - `:role` (optional) - Message role (default: `:assistant`)
      - `:delta` (optional) - Whether this is a streaming chunk (default: `false`)
      """

      use Jido.Signal,
        type: "ai.agent_session.message",
        default_source: "/ai/agent_session",
        schema: [
          session_id: [type: :string, required: true, doc: "Session identifier"],
          run_id: [type: :string, required: true, doc: "Run identifier"],
          role: [type: :atom, default: :assistant, doc: "Message role: :assistant or :system"],
          content: [type: :string, required: true, doc: "Text content"],
          delta: [type: :boolean, default: false, doc: "true = streaming chunk, false = complete message"]
        ]
    end

    defmodule ToolCall do
      @moduledoc """
      Signal emitted when the agent invokes a tool.

      This is observational — jido_ai cannot intercept or modify it.

      ## Data Fields

      - `:session_id` (required) - Session identifier
      - `:run_id` (required) - Run identifier
      - `:tool_name` (required) - Name of the tool
      - `:status` (required) - Tool call status (`:started`, `:completed`, or `:failed`)
      - `:tool_input` (optional) - Tool input parameters
      - `:tool_id` (optional) - Tool call identifier
      """

      use Jido.Signal,
        type: "ai.agent_session.tool_call",
        default_source: "/ai/agent_session",
        schema: [
          session_id: [type: :string, required: true, doc: "Session identifier"],
          run_id: [type: :string, required: true, doc: "Run identifier"],
          tool_name: [type: :string, required: true, doc: "Name of the tool"],
          tool_input: [type: :map, default: %{}, doc: "Tool input parameters"],
          tool_id: [type: :string, doc: "Tool call identifier"],
          status: [type: :atom, required: true, doc: "Status: :started, :completed, or :failed"]
        ]
    end

    defmodule Progress do
      @moduledoc """
      Signal for progress updates during long-running agent sessions.

      ## Data Fields

      - `:session_id` (required) - Session identifier
      - `:run_id` (required) - Run identifier
      - `:turn` (optional) - Current turn number
      - `:max_turns` (optional) - Maximum turns allowed
      - `:tokens_used` (optional) - Token usage so far
      """

      use Jido.Signal,
        type: "ai.agent_session.progress",
        default_source: "/ai/agent_session",
        schema: [
          session_id: [type: :string, required: true, doc: "Session identifier"],
          run_id: [type: :string, required: true, doc: "Run identifier"],
          turn: [type: :integer, doc: "Current turn number"],
          max_turns: [type: :integer, doc: "Maximum turns allowed"],
          tokens_used: [type: :map, default: %{}, doc: "Token usage so far"]
        ]
    end

    defmodule Completed do
      @moduledoc """
      Signal emitted when the agent finishes successfully.

      ## Data Fields

      - `:session_id` (required) - Session identifier
      - `:run_id` (required) - Run identifier
      - `:output` (required) - Final output from the agent
      - `:directive_id` (optional) - Originating directive ID
      - `:token_usage` (optional) - Total token usage
      - `:duration_ms` (optional) - Total execution duration in milliseconds
      - `:metadata` (optional) - Arbitrary metadata
      """

      use Jido.Signal,
        type: "ai.agent_session.completed",
        default_source: "/ai/agent_session",
        schema: [
          session_id: [type: :string, required: true, doc: "Session identifier"],
          run_id: [type: :string, required: true, doc: "Run identifier"],
          directive_id: [type: :string, doc: "Originating directive ID"],
          output: [type: :any, required: true, doc: "Final output from the agent"],
          token_usage: [type: :map, default: %{}, doc: "Total token usage"],
          duration_ms: [type: :integer, doc: "Execution duration in milliseconds"],
          metadata: [type: :map, default: %{}, doc: "Arbitrary metadata"]
        ]
    end

    defmodule Failed do
      @moduledoc """
      Signal emitted when the agent fails or is cancelled.

      ## Data Fields

      - `:session_id` (required) - Session identifier
      - `:run_id` (required) - Run identifier
      - `:reason` (required) - Failure reason (`:timeout`, `:cancelled`, or `:error`)
      - `:directive_id` (optional) - Originating directive ID
      - `:error_message` (optional) - Human-readable error message
      - `:partial_output` (optional) - Any output produced before failure
      - `:token_usage` (optional) - Token usage before failure
      - `:metadata` (optional) - Arbitrary metadata
      """

      use Jido.Signal,
        type: "ai.agent_session.failed",
        default_source: "/ai/agent_session",
        schema: [
          session_id: [type: :string, required: true, doc: "Session identifier"],
          run_id: [type: :string, required: true, doc: "Run identifier"],
          directive_id: [type: :string, doc: "Originating directive ID"],
          reason: [type: :atom, required: true, doc: "Failure reason: :timeout, :cancelled, or :error"],
          error_message: [type: :string, doc: "Human-readable error message"],
          partial_output: [type: :any, doc: "Output produced before failure"],
          token_usage: [type: :map, default: %{}, doc: "Token usage before failure"],
          metadata: [type: :map, default: %{}, doc: "Arbitrary metadata"]
        ]
    end

    # ==========================================================================
    # Helper Functions
    # ==========================================================================

    @doc """
    Converts an agent_session_manager event into a jido signal.

    Maps normalized event types to the corresponding signal:

    | Event Type              | Signal Type    |
    |------------------------|----------------|
    | `:run_started`          | `Started`      |
    | `:message_received`     | `Message`      |
    | `:message_streamed`     | `Message`      |
    | `:tool_call_started`    | `ToolCall`     |
    | `:tool_call_completed`  | `ToolCall`     |
    | `:tool_call_failed`     | `ToolCall`     |
    | `:run_completed`        | `Completed`    |
    | `:run_failed`           | `Failed`       |
    | `:run_cancelled`        | `Failed`       |
    | `:token_usage_updated`  | `Progress`     |
    | (other)                 | `Progress`     |

    ## Parameters

    - `event` - An agent_session_manager event (map with `:type`, `:data`, `:session_id`, `:run_id`)
    - `context` - Context map with `:session_id`, `:run_id`, `:directive_id`, `:metadata`

    ## Examples

        event = %{type: :message_streamed, data: %{delta: "Hello"}, session_id: "s1", run_id: "r1"}
        context = %{session_id: "s1", run_id: "r1", directive_id: "d1", metadata: %{}}
        signal = AgentSession.from_event(event, context)
        signal.type
        #=> "ai.agent_session.message"
    """
    @spec from_event(map(), map()) :: Jido.Signal.t()
    def from_event(%{type: :run_started} = event, context) do
      %{
        session_id: event_session_id(event, context),
        run_id: event_run_id(event, context),
        metadata: context[:metadata] || %{}
      }
      |> maybe_put_optional(:directive_id, context[:directive_id])
      |> Started.new!()
    end

    def from_event(%{type: :message_received} = event, context) do
      data = event_data(event)

      Message.new!(%{
        session_id: event_session_id(event, context),
        run_id: event_run_id(event, context),
        content: data[:content] || data["content"] || "",
        role: to_role(data[:role] || data["role"]),
        delta: false
      })
    end

    def from_event(%{type: :message_streamed} = event, context) do
      data = event_data(event)
      content = data[:delta] || data["delta"] || data[:content] || data["content"] || ""

      Message.new!(%{
        session_id: event_session_id(event, context),
        run_id: event_run_id(event, context),
        content: content,
        role: :assistant,
        delta: true
      })
    end

    def from_event(%{type: :tool_call_started} = event, context) do
      build_tool_call_signal(event, context, :started)
    end

    def from_event(%{type: :tool_call_completed} = event, context) do
      build_tool_call_signal(event, context, :completed)
    end

    def from_event(%{type: :tool_call_failed} = event, context) do
      build_tool_call_signal(event, context, :failed)
    end

    def from_event(%{type: :run_completed} = event, context) do
      data = event_data(event)

      %{
        session_id: event_session_id(event, context),
        run_id: event_run_id(event, context),
        output: data[:output] || data["output"] || data[:content] || data["content"] || "",
        token_usage: data[:token_usage] || data["token_usage"] || %{},
        metadata: context[:metadata] || %{}
      }
      |> maybe_put_optional(:directive_id, context[:directive_id])
      |> Completed.new!()
    end

    def from_event(%{type: :run_failed} = event, context) do
      data = event_data(event)

      error_msg =
        data[:error_message] ||
          data["error_message"] ||
          ((data[:reason] || data["reason"]) && to_string(data[:reason] || data["reason"])) ||
          "run failed"

      %{
        session_id: event_session_id(event, context),
        run_id: event_run_id(event, context),
        reason: :error,
        error_message: error_msg,
        metadata: context[:metadata] || %{}
      }
      |> maybe_put_optional(:directive_id, context[:directive_id])
      |> Failed.new!()
    end

    def from_event(%{type: :run_cancelled} = event, context) do
      %{
        session_id: event_session_id(event, context),
        run_id: event_run_id(event, context),
        reason: :cancelled,
        metadata: context[:metadata] || %{}
      }
      |> maybe_put_optional(:directive_id, context[:directive_id])
      |> Failed.new!()
    end

    def from_event(%{type: :token_usage_updated} = event, context) do
      data = event_data(event)

      Progress.new!(%{
        session_id: event_session_id(event, context),
        run_id: event_run_id(event, context),
        tokens_used: Map.delete(data, :raw)
      })
    end

    # Fallback for unrecognized event types
    def from_event(event, context) do
      Progress.new!(%{
        session_id: event_session_id(event, context),
        run_id: event_run_id(event, context)
      })
    end

    @doc """
    Builds a `Completed` signal from a `run_once/4` result.

    ## Parameters

    - `run_result` - Result map from `SessionManager.run_once/4` with `:output`, `:token_usage`, etc.
    - `context` - Context map with `:session_id`, `:run_id`, `:directive_id`, `:metadata`
    """
    @spec completed(map(), map()) :: Jido.Signal.t()
    def completed(run_result, context) do
      %{
        session_id: map_get(context, :session_id, "unknown"),
        run_id: map_get(context, :run_id, "unknown"),
        output: map_get(run_result, :output, ""),
        token_usage: map_get(run_result, :token_usage, %{}),
        metadata: context[:metadata] || %{}
      }
      |> maybe_put_optional(:directive_id, context[:directive_id])
      |> Completed.new!()
    end

    @doc """
    Builds a `Failed` signal from an error.

    ## Parameters

    - `error` - Error value (string, map, or struct)
    - `context` - Context map with `:session_id`, `:run_id`, `:directive_id`, `:metadata`
    """
    @spec failed(term(), map()) :: Jido.Signal.t()
    def failed(error, context) when is_binary(error) do
      %{
        session_id: map_get(context, :session_id, "unknown"),
        run_id: map_get(context, :run_id, "unknown"),
        reason: :error,
        error_message: error,
        metadata: context[:metadata] || %{}
      }
      |> maybe_put_optional(:directive_id, context[:directive_id])
      |> Failed.new!()
    end

    def failed(error, context) do
      reason = extract_failed_reason(error)

      error_message =
        cond do
          is_map(error) && Map.has_key?(error, :message) -> to_string(error.message)
          is_map(error) && Map.has_key?(error, :reason) -> to_string(error.reason)
          true -> inspect(error)
        end

      %{
        session_id: map_get(context, :session_id, "unknown"),
        run_id: map_get(context, :run_id, "unknown"),
        reason: reason,
        error_message: error_message,
        metadata: context[:metadata] || %{}
      }
      |> maybe_put_optional(:directive_id, context[:directive_id])
      |> Failed.new!()
    end

    # Private helpers

    defp event_session_id(event, context) do
      map_get(event, :session_id, map_get(context, :session_id, "unknown"))
    end

    defp event_run_id(event, context) do
      map_get(event, :run_id, map_get(context, :run_id, "unknown"))
    end

    defp event_data(event) do
      case map_get(event, :data, %{}) do
        data when is_map(data) -> data
        _ -> %{}
      end
    end

    defp map_get(map, key, default) when is_map(map) and is_atom(key) do
      case Map.fetch(map, key) do
        {:ok, value} ->
          value

        :error ->
          case Map.fetch(map, Atom.to_string(key)) do
            {:ok, value} -> value
            :error -> default
          end
      end
    end

    defp map_get(map, key, default) when is_map(map) do
      Map.get(map, key, default)
    end

    defp map_get(_other, _key, default), do: default

    defp maybe_put_optional(attrs, _key, nil), do: attrs
    defp maybe_put_optional(attrs, key, value), do: Map.put(attrs, key, value)

    defp to_role(nil), do: :assistant
    defp to_role(:assistant), do: :assistant
    defp to_role(:system), do: :system
    defp to_role(:user), do: :user
    defp to_role(:tool), do: :tool

    defp to_role(role) when is_binary(role) do
      case String.downcase(role) do
        "assistant" -> :assistant
        "system" -> :system
        "user" -> :user
        "tool" -> :tool
        _ -> :assistant
      end
    end

    defp to_role(_role), do: :assistant

    defp extract_failed_reason(error) when is_map(error) do
      case Map.get(error, :reason) do
        :timeout -> :timeout
        :cancelled -> :cancelled
        :error -> :error
        "timeout" -> :timeout
        "cancelled" -> :cancelled
        "error" -> :error
        _ -> :error
      end
    end

    defp extract_failed_reason(_error), do: :error

    defp build_tool_call_signal(event, context, status) do
      data = event_data(event)

      %{
        session_id: event_session_id(event, context),
        run_id: event_run_id(event, context),
        tool_name: map_get(data, :tool_name, map_get(data, :name, "unknown")),
        tool_input: normalize_tool_input(map_get(data, :tool_input, map_get(data, :input, %{}))),
        status: status
      }
      |> maybe_put_optional(
        :tool_id,
        map_get(data, :tool_id, map_get(data, :tool_call_id, map_get(data, :call_id, nil)))
      )
      |> ToolCall.new!()
    end

    defp normalize_tool_input(input) when is_map(input) do
      if Enum.all?(Map.keys(input), &is_atom/1), do: input, else: %{}
    end

    defp normalize_tool_input(_), do: %{}
  end
end
