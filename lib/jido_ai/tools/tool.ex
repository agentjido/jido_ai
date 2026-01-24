defmodule Jido.AI.Tools.Tool do
  @moduledoc """
  Defines a lightweight tool behavior for simple LLM function implementations.

  This provides a simpler alternative to `Jido.Action` when you only need a basic
  function exposed to the LLM without Action's full machinery (lifecycle hooks,
  output schema validation, etc.).

  ## When to Use Tool vs Action

  **Use `Jido.AI.Tools.Tool` when:**
  - You need a simple function with basic input validation
  - No lifecycle hooks (before/after callbacks) are needed
  - No output schema validation is required
  - The function is primarily for LLM tool calling

  **Use `Jido.Action` when:**
  - You need lifecycle hooks (`on_before_validate_params`, `on_after_run`, etc.)
  - You need output schema validation
  - The action is part of a larger Jido workflow
  - You need action composition or chaining

  ## Usage

      defmodule MyApp.Tools.Calculator do
        use Jido.AI.Tools.Tool,
          name: "calculator",
          description: "Performs basic arithmetic operations"

        @impl true
        def schema do
          [
            a: [type: :number, required: true, doc: "First operand"],
            b: [type: :number, required: true, doc: "Second operand"],
            operation: [type: :string, required: true, doc: "Operation: add, subtract, multiply, divide"]
          ]
        end

        @impl true
        def run(params, _context) do
          result = case params.operation do
            "add" -> params.a + params.b
            "subtract" -> params.a - params.b
            "multiply" -> params.a * params.b
            "divide" when params.b != 0 -> params.a / params.b
            "divide" -> {:error, "Division by zero"}
            _ -> {:error, "Unknown operation: \#{params.operation}"}
          end

          case result do
            {:error, reason} -> {:error, reason}
            value -> {:ok, %{result: value}}
          end
        end
      end

  ## Converting to ReqLLM.Tool

  Tools can be converted to ReqLLM.Tool structs for use with LLM calls:

      # Using the module function
      tool = MyApp.Tools.Calculator.to_reqllm_tool()

      # Or using the module-level function
      tool = Jido.AI.Tools.Tool.to_reqllm_tool(MyApp.Tools.Calculator)

      # Use with ReqLLM
      ReqLLM.stream_text(model, messages, tools: [tool])

  ## Execution

  Tools are executed via the registry/executor system, not via ReqLLM callbacks:

      # The tool's run/2 callback is invoked by the executor
      {:ok, result} = MyApp.Tools.Calculator.run(%{a: 5, b: 3, operation: "add"}, %{})
      # => {:ok, %{result: 8}}

  ## Context Parameter

  The `run/2` callback receives a context map as its second parameter. This context
  is passed through from the executor and may include:

  - `:agent_id` - Identifier of the calling agent (if available)
  - `:conversation_id` - Current conversation/session ID
  - `:user_id` - User identifier (if authenticated)
  - `:metadata` - Additional metadata from the caller

  **Security Note**: If context is received from untrusted sources (e.g., external
  LLM calls), treat it as potentially malicious. Validate and sanitize any context
  values before using them in sensitive operations.

  ## Rate Limiting

  The tool system does not implement rate limiting internally. Rate limiting is
  the caller's responsibility. If you need to limit tool execution rates, consider:

  - Using `Hammer` (https://hex.pm/packages/hammer) for token bucket rate limiting
  - Implementing rate limiting at the API layer before tool execution
  - Using agent-level rate limiting in the calling context

  Example with Hammer:

      # In your application
      case Hammer.check_rate("tool:\#{tool_name}:\#{user_id}", 60_000, 10) do
        {:allow, _count} -> Executor.execute(tool_name, params, context)
        {:deny, _limit} -> {:error, :rate_limited}
      end
  """

  alias Jido.Action.Schema, as: ActionSchema

  @doc """
  Returns the tool's name as used in LLM tool calls.

  The name should be a lowercase string with underscores (snake_case).
  """
  @callback name() :: String.t()

  @doc """
  Returns a description of what the tool does.

  This description is shown to the LLM to help it decide when to use the tool.
  """
  @callback description() :: String.t()

  @doc """
  Returns the NimbleOptions-style schema for the tool's parameters.

  The schema is used for:
  - Validating parameters before execution
  - Generating JSON Schema for the LLM

  This uses the same schema format as `Jido.Action` for consistency.

  ## Example

      def schema do
        [
          query: [type: :string, required: true, doc: "Search query"],
          limit: [type: :integer, default: 10, doc: "Max results"]
        ]
      end
  """
  @callback schema() :: keyword()

  @doc """
  Executes the tool with the given parameters and context.

  ## Arguments

    * `params` - Map of validated parameters matching the schema
    * `context` - Map of execution context (may include caller info, metadata, etc.)

  ## Returns

    * `{:ok, result}` - Successful execution with result
    * `{:error, reason}` - Execution failed with reason
  """
  @callback run(params :: map(), context :: map()) :: {:ok, term()} | {:error, term()}

  @doc """
  Converts a tool module's Zoi schema to ReqLLM.Tool struct.

  Uses the same JSON Schema generation as `Jido.AI.ToolAdapter` for consistency.

  ## Arguments

    * `tool_module` - A module implementing the `Jido.AI.Tools.Tool` behaviour

  ## Returns

    A `ReqLLM.Tool` struct ready for use with ReqLLM.

  ## Example

      tool = Jido.AI.Tools.Tool.to_reqllm_tool(MyApp.Tools.Calculator)
      ReqLLM.stream_text(model, messages, tools: [tool])
  """
  @spec to_reqllm_tool(module()) :: ReqLLM.Tool.t()
  def to_reqllm_tool(tool_module) when is_atom(tool_module) do
    ReqLLM.Tool.new!(
      name: tool_module.name(),
      description: tool_module.description(),
      parameter_schema: build_json_schema(tool_module.schema()),
      callback: &noop_callback/1
    )
  end

  # Noop callback - tools are executed via Jido's executor, not ReqLLM
  defp noop_callback(_args) do
    {:error, :not_executed_via_callback}
  end

  # Convert Zoi schema to JSON Schema
  defp build_json_schema(schema) do
    case ActionSchema.to_json_schema(schema) do
      empty when empty == %{} ->
        %{"type" => "object", "properties" => %{}}

      json_schema ->
        json_schema
    end
  end

  @doc false
  defmacro __using__(opts) do
    quote do
      @behaviour Jido.AI.Tools.Tool

      @tool_name Keyword.get(unquote(opts), :name) ||
                   raise(ArgumentError, "Tool requires :name option")

      @tool_description Keyword.get(unquote(opts), :description) ||
                          raise(ArgumentError, "Tool requires :description option")

      @impl Jido.AI.Tools.Tool
      def name, do: @tool_name

      @impl Jido.AI.Tools.Tool
      def description, do: @tool_description

      @doc """
      Converts this tool to a ReqLLM.Tool struct.

      Returns a `ReqLLM.Tool` ready for use with ReqLLM calls.
      """
      @spec to_reqllm_tool() :: ReqLLM.Tool.t()
      def to_reqllm_tool do
        Jido.AI.Tools.Tool.to_reqllm_tool(__MODULE__)
      end

      defoverridable name: 0, description: 0
    end
  end
end
