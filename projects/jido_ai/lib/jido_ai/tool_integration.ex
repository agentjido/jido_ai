defmodule Jido.AI.ToolIntegration do
  @moduledoc """
  Seamless integration between Jido AI and Jido Actions for tool calling.

  This module provides helper functions to easily convert Jido Actions into
  AI-compatible tool definitions and execute tool calls from LLM responses.

  ## Examples

      # Convert actions to OpenAI tool format
      actions = [MyApp.Weather, MyApp.Calculator]
      tools = Jido.AI.ToolIntegration.actions_to_tools(actions)
      
      # Use with generate_text
      Jido.AI.generate_text(
        "openai:gpt-4o",
        messages,
        tools: tools
      )
      
      # Execute tool calls from AI response
      tool_calls = [%{"id" => "call_1", "function" => %{"name" => "calculator", "arguments" => "..."}}]
      results = Jido.AI.ToolIntegration.execute_tool_calls(tool_calls, actions)
  """

  alias Jido.AI.Message

  @doc """
  Converts a list of Jido Actions to OpenAI-compatible tool definitions.

  ## Parameters

    * `actions` - List of action modules implementing Jido.Action behavior
    * `format` - Tool format to use (`:openai` or `:raw`), defaults to `:openai`

  ## Examples

      actions = [MyApp.Actions.Calculator, MyApp.Actions.Weather]
      tools = Jido.AI.ToolIntegration.actions_to_tools(actions)
      
      # Use with OpenAI
      tools = Jido.AI.ToolIntegration.actions_to_tools(actions, :openai)
      
      # Get raw tool definitions  
      raw_tools = Jido.AI.ToolIntegration.actions_to_tools(actions, :raw)
  """
  @spec actions_to_tools([module()], :openai | :raw) :: [map()]
  def actions_to_tools(actions, format \\ :openai) when is_list(actions) do
    Enum.map(actions, fn action ->
      tool_def = action.to_tool()

      case format do
        :openai ->
          %{
            "type" => "function",
            "function" => %{
              "name" => tool_def.name,
              "description" => tool_def.description,
              "parameters" => convert_schema_to_openai_format(tool_def.parameters_schema)
            }
          }

        :raw ->
          tool_def
      end
    end)
  end

  @doc """
  Executes tool calls from AI response using available actions.

  ## Parameters

    * `tool_calls` - List of tool call maps from AI response
    * `actions` - List of available action modules
    * `context` - Optional context map to pass to actions

  ## Returns

    List of tool result messages ready to be added to conversation.

  ## Examples

      tool_calls = [
        %{
          "id" => "call_123",
          "function" => %{
            "name" => "calculator",
            "arguments" => "{\"operation\": \"add\", \"a\": 5, \"b\": 3}"
          }
        }
      ]
      
      actions = [MyApp.Actions.Calculator]
      results = Jido.AI.ToolIntegration.execute_tool_calls(tool_calls, actions)
  """
  @spec execute_tool_calls([map()], [module()], map()) :: [Message.t()]
  def execute_tool_calls(tool_calls, actions, context \\ %{}) do
    # Create action lookup map
    action_map = Map.new(actions, &{&1.name(), &1})

    Enum.map(tool_calls, fn tool_call ->
      execute_single_tool_call(tool_call, action_map, context)
    end)
  end

  @doc """
  Executes a single tool call and returns a tool result message.

  ## Parameters

    * `tool_call` - Tool call map from AI response
    * `action_map` - Map of action names to action modules
    * `context` - Context map to pass to action
  """
  @spec execute_single_tool_call(map(), map(), map()) :: Message.t()
  def execute_single_tool_call(tool_call, action_map, context) do
    %{
      "id" => tool_call_id,
      "function" => %{
        "name" => function_name,
        "arguments" => arguments_json
      }
    } = tool_call

    case Map.get(action_map, function_name) do
      nil ->
        Message.tool_result(tool_call_id, function_name, %{
          error: "Unknown tool: #{function_name}"
        })

      action ->
        case Jason.decode(arguments_json) do
          {:ok, arguments} ->
            tool_def = action.to_tool()

            case tool_def.function.(arguments, context) do
              {:ok, result_json} ->
                result = Jason.decode!(result_json)
                Message.tool_result(tool_call_id, function_name, result)

              {:error, error_json} ->
                error = Jason.decode!(error_json)
                Message.tool_result(tool_call_id, function_name, error)
            end

          {:error, _} ->
            Message.tool_result(tool_call_id, function_name, %{
              error: "Invalid JSON arguments: #{arguments_json}"
            })
        end
    end
  end

  @doc """
  Creates a complete AI assistant workflow with tool calling support.

  This function demonstrates the complete integration pattern between
  jido_ai and jido_action for tool calling workflows.

  ## Parameters

    * `model_spec` - Model specification for jido_ai
    * `messages` - Conversation messages
    * `actions` - List of available action modules
    * `opts` - Additional options

  ## Examples

      actions = [MyApp.Actions.Calculator, MyApp.Actions.Weather]
      
      result = Jido.AI.ToolIntegration.generate_with_tools(
        "openai:gpt-4o",
        [Message.user("Calculate 5 + 3")],
        actions
      )
  """
  @spec generate_with_tools(
          term(),
          [Message.t()],
          [module()],
          keyword()
        ) :: {:ok, String.t()} | {:error, term()}
  def generate_with_tools(model_spec, messages, actions, opts \\ []) do
    # Convert actions to tool definitions
    tools = actions_to_tools(actions, :openai)

    # Add tools to provider options
    provider_opts = Keyword.get(opts, :provider_options, %{})
    updated_provider_opts = Map.put(provider_opts, :tools, tools)
    updated_opts = Keyword.put(opts, :provider_options, updated_provider_opts)

    # Generate with tools
    case Jido.AI.generate_text(model_spec, messages, updated_opts) do
      {:ok, response} ->
        {:ok, response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Helper function to create an action registry for tool execution.

  ## Parameters

    * `actions` - List of action modules

  ## Returns

    Map with action names as keys and action modules as values.
  """
  @spec create_action_registry([module()]) :: map()
  def create_action_registry(actions) when is_list(actions) do
    Map.new(actions, &{&1.name(), &1})
  end

  @doc """
  Validates that all provided modules are valid Jido Actions.

  ## Parameters

    * `actions` - List of modules to validate

  ## Returns

    `:ok` if all modules are valid actions, `{:error, reason}` otherwise.
  """
  @spec validate_actions([module()]) :: :ok | {:error, String.t()}
  def validate_actions(actions) when is_list(actions) do
    invalid_actions =
      Enum.reject(actions, fn action ->
        Code.ensure_loaded?(action) and
          function_exported?(action, :name, 0) and
          function_exported?(action, :description, 0) and
          function_exported?(action, :schema, 0) and
          function_exported?(action, :to_tool, 0)
      end)

    if Enum.empty?(invalid_actions) do
      :ok
    else
      {:error, "Invalid actions: #{inspect(invalid_actions)}"}
    end
  end

  @doc false
  @spec convert_schema_to_openai_format(map()) :: %{String.t() => any()}
  defp convert_schema_to_openai_format(schema) when is_map(schema) do
    %{
      "type" => schema[:type],
      "properties" => schema[:properties],
      "required" => schema[:required]
    }
  end
end
