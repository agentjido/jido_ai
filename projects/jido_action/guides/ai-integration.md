# AI Integration

**Prerequisites**: [Tools Reference](tools-reference.md)

Jido Action provides seamless integration with AI systems through automatic tool conversion, enabling actions to be used with LLMs for function calling and autonomous agents.

## Action to Tool Conversion

Every action automatically converts to an AI-compatible tool definition:

```elixir
defmodule MyApp.Actions.SearchUsers do
  use Jido.Action,
    name: "search_users",
    description: "Search for users by name or email",
    schema: [
      query: [
        type: :string, 
        required: true,
        doc: "Search query (name or email)"
      ],
      limit: [
        type: :integer, 
        default: 10,
        min: 1,
        max: 100,
        doc: "Maximum number of results"
      ],
      include_inactive: [
        type: :boolean,
        default: false,
        doc: "Include inactive users in results"
      ]
    ]

  def run(params, _context) do
    users = search_database(params.query, params.limit, params.include_inactive)
    {:ok, %{users: users, count: length(users)}}
  end
end

# Convert to AI tool definition
tool_def = MyApp.Actions.SearchUsers.to_tool()
```

This generates an OpenAI-compatible function definition:

```json
{
  "type": "function",
  "function": {
    "name": "search_users",
    "description": "Search for users by name or email", 
    "parameters": {
      "type": "object",
      "properties": {
        "query": {
          "type": "string",
          "description": "Search query (name or email)"
        },
        "limit": {
          "type": "integer", 
          "description": "Maximum number of results",
          "minimum": 1,
          "maximum": 100
        },
        "include_inactive": {
          "type": "boolean",
          "description": "Include inactive users in results"
        }
      },
      "required": ["query"]
    }
  }
}
```

## Using with OpenAI

### Basic Function Calling

```elixir
defmodule MyApp.AI.Assistant do
  @available_tools [
    MyApp.Actions.SearchUsers,
    MyApp.Actions.CreateUser,
    MyApp.Actions.SendEmail,
    Jido.Tools.Weather,
    Jido.Tools.Files.ReadFile
  ]

  def chat_with_tools(messages, context \\ %{}) do
    # Convert actions to tool definitions
    tools = Enum.map(@available_tools, & &1.to_tool())
    
    # Make OpenAI request with tools
    response = OpenAI.chat_completion(%{
      model: "gpt-4",
      messages: messages,
      tools: tools,
      tool_choice: "auto"
    })
    
    # Handle function calls
    case response do
      %{"choices" => [%{"message" => %{"tool_calls" => tool_calls}}]} ->
        handle_tool_calls(tool_calls, context)
      
      %{"choices" => [%{"message" => %{"content" => content}}]} ->
        {:ok, content}
    end
  end

  defp handle_tool_calls(tool_calls, context) do
    results = Enum.map(tool_calls, fn tool_call ->
      %{
        "id" => id,
        "function" => %{
          "name" => function_name,
          "arguments" => arguments_json
        }
      } = tool_call
      
      # Parse arguments
      {:ok, arguments} = Jason.decode(arguments_json)
      
      # Find and execute action
      action = find_action_by_name(function_name)
      {:ok, result} = Jido.Action.Tool.execute_action(action, arguments, context)
      
      %{
        tool_call_id: id,
        result: result
      }
    end)
    
    {:ok, results}
  end

  defp find_action_by_name(name) do
    Enum.find(@available_tools, fn action ->
      action.action_name() == name
    end)
  end
end
```

### Agent Conversation Flow

```elixir
defmodule MyApp.AI.Agent do
  def process_user_request(user_message, context) do
    messages = [
      %{
        "role" => "system",
        "content" => """
        You are a helpful assistant that can:
        - Search for users
        - Create new users  
        - Send emails
        - Check weather
        - Read files
        
        Use the available tools to help users accomplish their tasks.
        """
      },
      %{
        "role" => "user", 
        "content" => user_message
      }
    ]
    
    case MyApp.AI.Assistant.chat_with_tools(messages, context) do
      {:ok, tool_results} when is_list(tool_results) ->
        # AI used tools, continue conversation with results
        continue_conversation_with_results(messages, tool_results, context)
      
      {:ok, text_response} ->
        # AI responded with text
        {:ok, text_response}
      
      {:error, reason} ->
        {:error, "AI request failed: #{reason}"}
    end
  end

  defp continue_conversation_with_results(messages, tool_results, context) do
    # Add tool results to conversation
    tool_messages = Enum.map(tool_results, fn %{tool_call_id: id, result: result} ->
      %{
        "role" => "tool",
        "tool_call_id" => id,
        "content" => Jason.encode!(result)
      }
    end)
    
    updated_messages = messages ++ tool_messages
    
    # Get AI's final response
    response = OpenAI.chat_completion(%{
      model: "gpt-4",
      messages: updated_messages
    })
    
    case response do
      %{"choices" => [%{"message" => %{"content" => content}}]} ->
        {:ok, content}
      _ ->
        {:error, "Unexpected AI response format"}
    end
  end
end
```

## Tool Parameter Mapping

### Type Conversion

Actions automatically handle type conversion between JSON and Elixir:

```elixir
# AI provides JSON parameters
ai_params = %{
  "user_id" => "123",           # String
  "age" => 25,                  # Integer  
  "active" => true,             # Boolean
  "tags" => ["admin", "user"],  # Array
  "metadata" => %{"role" => "admin"}  # Object
}

# Action receives validated Elixir types
defmodule MyApp.Actions.UpdateUser do
  use Jido.Action,
    schema: [
      user_id: [type: :string, required: true],
      age: [type: :integer, min: 0],
      active: [type: :boolean, default: true],
      tags: [type: {:list, :string}, default: []],
      metadata: [type: :map, default: %{}]
    ]

  def run(params, _context) do
    # params is validated and type-converted
    %{
      user_id: user_id,    # String
      age: age,           # Integer
      active: active,     # Boolean
      tags: tags,         # List of strings
      metadata: metadata  # Map
    } = params
    
    {:ok, update_user_in_db(params)}
  end
end

# Execute from AI tool call
{:ok, result} = Jido.Action.Tool.execute_action(
  MyApp.Actions.UpdateUser,
  ai_params,  # JSON from AI
  %{}
)
```

### Schema Documentation

Action schemas provide rich documentation for AI systems:

```elixir
defmodule MyApp.Actions.ProcessOrder do
  use Jido.Action,
    name: "process_order",
    description: "Process a customer order with payment and shipping",
    schema: [
      order_id: [
        type: :string,
        required: true,
        doc: "Unique order identifier"
      ],
      payment_method: [
        type: :atom,
        in: [:credit_card, :paypal, :bank_transfer],
        required: true,
        doc: "Payment method to use"
      ],
      shipping_address: [
        type: :map,
        required: true,
        doc: "Shipping address with street, city, state, zip"
      ],
      rush_delivery: [
        type: :boolean,
        default: false,
        doc: "Whether to use rush delivery (additional cost)"
      ],
      notes: [
        type: :string,
        doc: "Special delivery instructions"
      ]
    ]
end
```

This generates detailed parameter descriptions that help AI systems understand how to use the tool effectively.

## Multi-Step AI Workflows

### Planning with AI

```elixir
defmodule MyApp.AI.Planner do
  def create_user_onboarding_plan(user_data, context) do
    system_prompt = """
    You are a workflow planner. Create a step-by-step plan to onboard a new user.
    
    Available actions:
    - create_user: Create user account
    - send_welcome_email: Send welcome email
    - setup_preferences: Configure user preferences
    - assign_default_role: Assign default permissions
    
    Create a logical sequence of these actions based on the user data provided.
    """
    
    messages = [
      %{"role" => "system", "content" => system_prompt},
      %{"role" => "user", "content" => "Plan onboarding for: #{inspect(user_data)}"}
    ]
    
    tools = [
      MyApp.Actions.CreateUser.to_tool(),
      MyApp.Actions.SendWelcomeEmail.to_tool(),
      MyApp.Actions.SetupPreferences.to_tool(),
      MyApp.Actions.AssignDefaultRole.to_tool()
    ]
    
    # AI will create a plan using the available tools
    MyApp.AI.Assistant.chat_with_tools(messages, context)
  end
end
```

### Autonomous Agent Loop

```elixir
defmodule MyApp.AI.AutonomousAgent do
  def run_agent_loop(goal, context, max_iterations \\ 10) do
    run_loop(goal, context, [], 0, max_iterations)
  end

  defp run_loop(goal, context, history, iteration, max_iterations) 
       when iteration < max_iterations do
    
    system_prompt = """
    You are an autonomous agent working toward this goal: #{goal}
    
    Previous actions taken: #{format_history(history)}
    
    Available tools: [list of tools]
    
    Analyze the current situation and decide what action to take next.
    If the goal is complete, respond with "GOAL_COMPLETE".
    """
    
    messages = [
      %{"role" => "system", "content" => system_prompt},
      %{"role" => "user", "content" => "What should I do next?"}
    ]
    
    case MyApp.AI.Assistant.chat_with_tools(messages, context) do
      {:ok, "GOAL_COMPLETE"} ->
        {:ok, %{status: :complete, history: history, iterations: iteration}}
      
      {:ok, tool_results} when is_list(tool_results) ->
        # Continue with next iteration
        updated_history = history ++ tool_results
        run_loop(goal, context, updated_history, iteration + 1, max_iterations)
      
      {:ok, response} ->
        # AI provided text response, continue
        updated_history = history ++ [%{type: :text, content: response}]
        run_loop(goal, context, updated_history, iteration + 1, max_iterations)
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp run_loop(_goal, _context, history, iteration, max_iterations) do
    {:ok, %{
      status: :max_iterations_reached, 
      history: history, 
      iterations: iteration
    }}
  end

  defp format_history(history) do
    Enum.map_join(history, "\n", fn item ->
      case item do
        %{tool_call_id: _, result: result} -> "Action result: #{inspect(result)}"
        %{type: :text, content: content} -> "Thought: #{content}"
      end
    end)
  end
end
```

## Error Handling in AI Integration

### Tool Execution Errors

```elixir
defmodule MyApp.AI.ErrorHandler do
  def execute_tool_safely(action, arguments, context) do
    case Jido.Action.Tool.execute_action(action, arguments, context) do
      {:ok, result} ->
        {:ok, result}
      
      {:error, %{type: :validation_error} = error} ->
        # Return error info to AI for parameter correction
        {:error, %{
          type: "parameter_error",
          message: error.message,
          details: error.details,
          suggestion: "Please check the parameter types and values"
        }}
      
      {:error, %{type: :execution_error} = error} ->
        # Log error and return generic message
        Logger.error("Tool execution failed", 
          action: action,
          error: error.message
        )
        
        {:error, %{
          type: "execution_error", 
          message: "The action could not be completed",
          retryable: true
        }}
      
      {:error, error} ->
        {:error, %{
          type: "unknown_error",
          message: "An unexpected error occurred"
        }}
    end
  end
end
```

### AI Response Validation

```elixir
defmodule MyApp.AI.Validator do
  def validate_ai_tool_call(tool_call) do
    required_fields = ["id", "function"]
    function_fields = ["name", "arguments"]
    
    with :ok <- check_required_fields(tool_call, required_fields),
         :ok <- check_required_fields(tool_call["function"], function_fields),
         {:ok, _} <- Jason.decode(tool_call["function"]["arguments"]) do
      :ok
    else
      {:error, reason} ->
        {:error, "Invalid tool call format: #{reason}"}
    end
  end

  defp check_required_fields(map, required_fields) do
    missing = Enum.filter(required_fields, fn field ->
      not Map.has_key?(map, field)
    end)
    
    if Enum.empty?(missing) do
      :ok
    else
      {:error, "Missing required fields: #{Enum.join(missing, ", ")}"}
    end
  end
end
```

## Best Practices

### Action Design for AI
- **Clear Names**: Use descriptive action names that indicate purpose
- **Rich Documentation**: Provide detailed parameter descriptions
- **Predictable Outputs**: Return consistent, well-structured results
- **Error Messages**: Include actionable error information

### Parameter Design
- **Type Safety**: Use appropriate schema types for validation
- **Reasonable Defaults**: Provide sensible defaults for optional parameters
- **Constraints**: Set appropriate min/max values and choices
- **Documentation**: Explain what each parameter does and valid values

### Integration Patterns
- **Tool Registration**: Maintain a clear registry of available tools
- **Context Passing**: Pass relevant context to actions for authorization
- **Error Recovery**: Handle tool failures gracefully in AI workflows
- **Logging**: Log AI tool usage for debugging and monitoring

### Security Considerations
- **Authorization**: Check permissions before executing AI-requested actions
- **Input Validation**: Validate all AI-provided parameters strictly
- **Rate Limiting**: Limit AI tool usage to prevent abuse
- **Audit Logging**: Log all AI-initiated actions for security audit

## Next Steps

**→ [Instructions & Plans](instructions-plans.md)** - Compose actions into AI-driven workflows  
**→ [Testing Guide](testing.md)** - Test AI integrations  
**→ [FAQ](faq.md)** - Common AI integration questions

---
← [Tools Reference](tools-reference.md) | **Next: [Testing Guide](testing.md)** →
