defmodule Jido.AI.Runner.ReAct.ToolRegistry do
  @moduledoc """
  Manages tool registration, description, and execution for ReAct.

  The ToolRegistry provides a unified interface for working with tools in ReAct,
  whether they are:
  - Jido Actions (preferred for production)
  - Simple function callbacks (testing)
  - External API wrappers
  - Custom tool implementations

  ## Tool Format

  Tools can be provided in several formats:

  ### Jido Action
  ```elixir
  %{
    name: "search",
    description: "Search the web for information",
    action: Jido.Actions.WebSearch,
    parameters: [:query]
  }
  ```

  ### Function Tool
  ```elixir
  %{
    name: "calculator",
    description: "Perform mathematical calculations",
    function: fn input -> {:ok, evaluate(input)} end,
    parameters: [:expression]
  }
  ```

  ### Map Tool
  ```elixir
  %{
    name: "weather",
    description: "Get weather information",
    execute: fn location -> fetch_weather(location) end,
    parameters: [:location]
  }
  ```

  ## Examples

      # Register tools
      tools = [
        %{name: "search", description: "Search the web", function: &search/1},
        %{name: "calculate", description: "Do math", function: &calc/1}
      ]

      # Format for LLM
      description = ToolRegistry.format_tool_description(tools)

      # Execute tool
      {:ok, result} = ToolRegistry.execute_tool(search_tool, "Elixir lang", context)
  """

  @doc """
  Formats a tool description for inclusion in thought prompts.

  Creates a clear, concise description of the tool that helps the LLM
  understand when and how to use it.

  ## Parameters

  - `tool` - The tool to describe

  ## Returns

  - Formatted tool description string

  ## Examples

      format_tool_description(%{
        name: "search",
        description: "Search the web",
        parameters: [:query]
      })
      # => "search(query): Search the web"
  """
  @spec format_tool_description(map() | keyword()) :: String.t()
  def format_tool_description(tool) when is_map(tool) do
    name = tool_name(tool)
    description = tool_description(tool)
    parameters = tool_parameters(tool)

    param_str =
      if Enum.empty?(parameters) do
        ""
      else
        params =
          parameters
          |> Enum.map_join(", ", &to_string/1)

        "(#{params})"
      end

    "#{name}#{param_str}: #{description}"
  end

  def format_tool_description(tool) when is_list(tool) do
    format_tool_description(Enum.into(tool, %{}))
  end

  @doc """
  Extracts the tool name from a tool definition.

  ## Parameters

  - `tool` - Tool definition

  ## Returns

  - Tool name as string
  """
  @spec tool_name(map() | keyword()) :: String.t()
  def tool_name(tool) when is_map(tool) do
    cond do
      Map.has_key?(tool, :name) -> to_string(tool.name)
      Map.has_key?(tool, "name") -> to_string(tool["name"])
      true -> "unknown_tool"
    end
  end

  def tool_name(tool) when is_list(tool) do
    tool_name(Enum.into(tool, %{}))
  end

  @doc """
  Extracts the tool description.

  ## Parameters

  - `tool` - Tool definition

  ## Returns

  - Tool description string
  """
  @spec tool_description(map() | keyword()) :: String.t()
  def tool_description(tool) when is_map(tool) do
    cond do
      Map.has_key?(tool, :description) -> to_string(tool.description)
      Map.has_key?(tool, "description") -> to_string(tool["description"])
      true -> "No description available"
    end
  end

  def tool_description(tool) when is_list(tool) do
    tool_description(Enum.into(tool, %{}))
  end

  @doc """
  Extracts tool parameters.

  ## Parameters

  - `tool` - Tool definition

  ## Returns

  - List of parameter names
  """
  @spec tool_parameters(map() | keyword()) :: list()
  def tool_parameters(tool) when is_map(tool) do
    cond do
      Map.has_key?(tool, :parameters) -> List.wrap(tool.parameters)
      Map.has_key?(tool, "parameters") -> List.wrap(tool["parameters"])
      Map.has_key?(tool, :params) -> List.wrap(tool.params)
      Map.has_key?(tool, "params") -> List.wrap(tool["params"])
      true -> []
    end
  end

  def tool_parameters(tool) when is_list(tool) do
    tool_parameters(Enum.into(tool, %{}))
  end

  @doc """
  Executes a tool with the given input.

  Handles different tool types:
  - Jido Actions
  - Function callbacks
  - Custom execute functions

  ## Parameters

  - `tool` - The tool to execute
  - `input` - Input for the tool
  - `context` - Execution context (for Jido actions)

  ## Returns

  - `{:ok, result}` - Tool executed successfully
  - `{:error, reason}` - Execution failed
  """
  @spec execute_tool(map() | keyword(), term(), map()) :: {:ok, term()} | {:error, term()}
  def execute_tool(tool, input, context \\ %{})

  def execute_tool(tool, input, context) when is_map(tool) do
    cond do
      # Jido Action
      Map.has_key?(tool, :action) ->
        execute_jido_action(tool.action, input, context)

      # Function tool
      Map.has_key?(tool, :function) ->
        execute_function_tool(tool.function, input)

      # Custom execute function
      Map.has_key?(tool, :execute) ->
        execute_function_tool(tool.execute, input)

      # Map with string keys
      Map.has_key?(tool, "action") ->
        execute_jido_action(tool["action"], input, context)

      Map.has_key?(tool, "function") ->
        execute_function_tool(tool["function"], input)

      Map.has_key?(tool, "execute") ->
        execute_function_tool(tool["execute"], input)

      true ->
        {:error, {:invalid_tool, "No executable function found"}}
    end
  end

  def execute_tool(tool, input, context) when is_list(tool) do
    execute_tool(Enum.into(tool, %{}), input, context)
  end

  @doc """
  Validates that a tool has the required fields.

  ## Parameters

  - `tool` - Tool to validate

  ## Returns

  - `:ok` - Tool is valid
  - `{:error, reason}` - Tool is invalid
  """
  @spec validate_tool(map() | keyword()) :: :ok | {:error, term()}
  def validate_tool(tool) when is_map(tool) do
    errors = []

    # Check for name
    errors =
      if Map.has_key?(tool, :name) || Map.has_key?(tool, "name") do
        errors
      else
        [:missing_name | errors]
      end

    # Check for description
    errors =
      if Map.has_key?(tool, :description) || Map.has_key?(tool, "description") do
        errors
      else
        [:missing_description | errors]
      end

    # Check for executable
    has_executable =
      Map.has_key?(tool, :action) ||
        Map.has_key?(tool, :function) ||
        Map.has_key?(tool, :execute) ||
        Map.has_key?(tool, "action") ||
        Map.has_key?(tool, "function") ||
        Map.has_key?(tool, "execute")

    errors =
      if has_executable do
        errors
      else
        [:missing_executable | errors]
      end

    if Enum.empty?(errors) do
      :ok
    else
      {:error, {:invalid_tool, errors}}
    end
  end

  def validate_tool(tool) when is_list(tool) do
    validate_tool(Enum.into(tool, %{}))
  end

  @doc """
  Creates a simple function-based tool.

  Convenience function for creating tools from functions.

  ## Parameters

  - `name` - Tool name
  - `description` - Tool description
  - `function` - Function to execute (arity 1, returns {:ok, result} or {:error, reason})
  - `opts` - Additional options:
    - `:parameters` - List of parameter names

  ## Returns

  - Tool map

  ## Examples

      search_tool = ToolRegistry.create_function_tool(
        "search",
        "Search the web for information",
        fn query -> {:ok, search_web(query)} end,
        parameters: [:query]
      )
  """
  @spec create_function_tool(String.t(), String.t(), function(), keyword()) :: map()
  def create_function_tool(name, description, function, opts \\ []) do
    parameters = Keyword.get(opts, :parameters, [])

    %{
      name: name,
      description: description,
      function: function,
      parameters: parameters
    }
  end

  @doc """
  Creates a Jido Action-based tool.

  ## Parameters

  - `name` - Tool name
  - `description` - Tool description
  - `action_module` - Jido Action module
  - `opts` - Additional options

  ## Returns

  - Tool map
  """
  @spec create_action_tool(String.t(), String.t(), module(), keyword()) :: map()
  def create_action_tool(name, description, action_module, opts \\ []) do
    parameters = Keyword.get(opts, :parameters, [])

    %{
      name: name,
      description: description,
      action: action_module,
      parameters: parameters
    }
  end

  # Private functions

  defp execute_jido_action(action_module, input, context) do
    # Prepare parameters for Jido action
    params =
      if is_map(input) do
        input
      else
        %{input: input}
      end

    # Execute action
    case action_module.run(params, context) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
      other -> {:ok, other}
    end
  rescue
    error -> {:error, {:action_execution_failed, error}}
  end

  defp execute_function_tool(function, input) when is_function(function, 1) do
    case function.(input) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
      result -> {:ok, result}
    end
  rescue
    error -> {:error, {:function_execution_failed, error}}
  end

  defp execute_function_tool(function, _input) when is_function(function, 0) do
    # Zero-arity function, ignore input
    case function.() do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
      result -> {:ok, result}
    end
  rescue
    error -> {:error, {:function_execution_failed, error}}
  end

  defp execute_function_tool(_function, _input) do
    {:error, {:invalid_function, "Function must have arity 0 or 1"}}
  end
end
