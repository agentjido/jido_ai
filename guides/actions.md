# Jido AI Actions

## Introduction to Jido AI Actions

Jido AI Actions are modular, reusable components that encapsulate AI capabilities within your applications. These actions build upon the core Jido SDK action framework, implementing specific AI LLM capabilities that can be composed with other components in the Jido ecosystem. This guide presents an overview of the pre-built actions included with Jido AI and demonstrates how you can extend them to create your own custom actions.

## Core Action Types

Jido AI includes several foundational action types, each designed for specific use cases:

### Instructor-based Actions

These actions use the Instructor library to provide structured responses from AI models:

| Action | Description |
|--------|-------------|
| `Jido.AI.Actions.Instructor` | Base action providing direct access to Instructor's chat completion functionality |
| `Jido.AI.Actions.Instructor.BooleanResponse` | Returns true/false answers with explanations |
| `Jido.AI.Actions.Instructor.ChatResponse` | Provides natural language responses |
| `Jido.AI.Actions.Instructor.ChoiceResponse` | Selects from available options with explanations |

### LangChain-based Actions

These actions leverage LangChain for more complex scenarios:

| Action | Description |
|--------|-------------|
| `Jido.AI.Actions.Langchain` | Base action providing access to LangChain's chat functionality |
| `Jido.AI.Actions.Langchain.ToolResponse` | Coordinates with tools/functions for enhanced capabilities |

### OpenAI-specific Actions

These actions directly interact with OpenAI's APIs:

| Action | Description |
|--------|-------------|
| `Jido.AI.Actions.OpenaiEx` | Chat completion using OpenAI Ex with tool calling support |
| `Jido.AI.Actions.OpenaiEx.Embeddings` | Vector embedding generation |
| `Jido.AI.Actions.OpenaiEx.ImageGeneration` | Image creation from text prompts |
| `Jido.AI.Actions.OpenaiEx.ResponseRetrieve` | Asynchronous response retrieval |
| `Jido.AI.Actions.OpenaiEx.ToolHelper` | Helper for tool/function calling with OpenAI |

## Integration with Jido Ecosystem

Jido AI Actions aren't standalone components - they're designed to integrate seamlessly with the broader Jido ecosystem. By implementing the `Jido.Action` behavior, these AI-specific actions:

1. **Follow consistent patterns**: Share the same interface as other Jido actions
2. **Support workflow composition**: Can be combined with non-AI actions in complex workflows
3. **Leverage core infrastructure**: Utilize the same validation, error handling, and execution context mechanisms

This integration allows you to mix AI capabilities with other types of actions in your application, creating powerful combinations of functionality.

## Action Composition Pattern

Jido AI Actions follow a composition pattern that allows higher-level actions to build upon simpler ones. This aligns with the core Jido SDK design philosophy of building complex systems from simple, composable pieces. For example:

```elixir
# BooleanResponse builds upon the base Instructor action
defmodule Jido.AI.Actions.Instructor.BooleanResponse do
  # Define the schema for boolean responses
  defmodule Schema do
    use Ecto.Schema
    use Instructor

    @llm_doc """
    A boolean response from an AI assistant.
    """
    @primary_key false
    embedded_schema do
      field(:answer, :boolean)
      field(:explanation, :string)
      field(:confidence, :float)
      field(:is_ambiguous, :boolean)
    end
  end

  # Use the Jido.Action behavior
  use Jido.Action,
    name: "get_boolean_response",
    description: "Get a true/false answer to a question with explanation",
    schema: [
      # Schema definition...
    ]

  # Leverage the base Instructor action for implementation
  def run(params, context) do
    # Implementation details...
    case Instructor.run(
      %{
        model: model,
        prompt: enhanced_prompt,
        response_model: Schema,
        # Other parameters...
      },
      context
    ) do
      {:ok, %{result: %Schema{} = response}, _} ->
        {:ok,
          %{
            result: response.answer,
            explanation: response.explanation,
            confidence: response.confidence,
            is_ambiguous: response.is_ambiguous
          }}
      # Error handling...
    end
  end

  # Helper functions...
end
```

## Multi-Provider Support

Jido AI Actions are designed to work with multiple AI providers, including:

- Anthropic (Claude models)
- OpenAI (GPT models)
- OpenRouter (for accessing multiple providers via one API)
- Cloudflare AI
- Ollama
- LlamaCPP
- Together AI

Provider-specific adapters handle the necessary API differences, allowing your actions to be provider-agnostic:

```elixir
# Example of provider-specific configuration
case params.model.provider do
  :anthropic ->
    [
      adapter: Instructor.Adapters.Anthropic,
      api_key: api_key
    ]
  :openai ->
    [
      adapter: Instructor.Adapters.OpenAI,
      openai: [
        api_key: api_key
      ]
    ]
  # Other providers...
end
```

## Creating Your Own Actions

Creating a custom action involves a few key steps:

1. Define your action module using `Jido.Action`
2. Specify the parameters schema
3. Implement the `run/2` function

Here's a simplified example:

```elixir
defmodule MyApp.CustomAction do
  use Jido.Action,
    name: "my_custom_action",
    description: "A custom action for my application",
    schema: [
      model: [
        type: {:custom, Jido.AI.Model, :validate_model_opts, []},
        required: true,
        doc: "The AI model to use"
      ],
      prompt: [
        type: {:custom, Jido.AI.Prompt, :validate_prompt_opts, []},
        required: true,
        doc: "The prompt to use"
      ],
      my_param: [
        type: :string,
        required: true,
        doc: "A custom parameter"
      ]
    ]

  def run(params, context) do
    # Implementation using a base action
    Jido.AI.Actions.Instructor.ChatResponse.run(
      %{
        model: params.model,
        prompt: enhance_prompt(params.prompt, params.my_param),
        temperature: 0.7
      },
      context
    )
  end

  defp enhance_prompt(prompt, my_param) do
    # Custom prompt enhancement logic
    # ...
  end
end
```

### Action Best Practices

1. **Modular Design**: Keep your actions focused on a single responsibility
2. **Consistent Error Handling**: Return `{:ok, result}` or `{:error, reason}`
3. **Documentation**: Include thorough docs and examples
4. **Parameter Validation**: Validate all inputs before processing
5. **Reuse**: Build on existing actions when possible

## Using Actions in Applications

Actions can be used directly in your application code:

```elixir
alias MyApp.CustomAction

def process_user_query(query) do
  params = %{
    model: {:anthropic, [model: "claude-3-haiku-20240307"]},
    prompt: Jido.AI.Prompt.new(:user, query),
    my_param: "some value"
  }

  case CustomAction.run(params, %{}) do
    {:ok, result} -> handle_success(result)
    {:error, reason} -> handle_error(reason)
  end
end
```

Or with the Jido AI Agent:

```elixir
alias Jido.AI.Agent

{:ok, agent} = Agent.start_link(
  skills: [MyApp.CustomSkill],
  model: {:anthropic, [model: "claude-3-haiku-20240307"]}
)

Agent.tool_response(agent, "What is the capital of France?")
```

## Composing with Other Jido Components

Because Jido AI Actions implement the standard Jido Action interface, they can be easily composed with other components in the Jido ecosystem:

```elixir
defmodule MyApp.ComplexWorkflow do
  def execute(input) do
    with {:ok, parsed_data} <- MyApp.DataParser.run(input),
         {:ok, validated} <- MyApp.Validator.run(parsed_data),
         # AI action integrated into the workflow
         {:ok, enriched} <- Jido.AI.Actions.Instructor.ChatResponse.run(%{
           model: {:anthropic, [model: "claude-3-haiku-20240307"]},
           prompt: build_enrichment_prompt(validated)
         }, %{}),
         {:ok, result} <- MyApp.DataProcessor.run(enriched) do
      {:ok, result}
    else
      {:error, reason} -> {:error, reason}
    end
  end
  
  # Helper functions...
end
```

This ability to seamlessly mix AI and non-AI actions creates powerful possibilities for complex application workflows.

## Conclusion

Jido AI Actions provide a powerful, flexible foundation for building AI-enabled applications. By building on the core Jido SDK action framework, these components offer a consistent approach to implementing AI capabilities that can be composed with the broader Jido ecosystem.

By leveraging the included actions and creating your own custom ones, you can quickly implement complex AI capabilities while maintaining code that is modular, testable, and maintainable.

The examples included in this guide demonstrate the fundamentals, but there's much more you can do by exploring the full API and creating actions tailored to your specific use cases.