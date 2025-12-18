defmodule Jido.AI.Actions.ReqLlm.ToolResponse do
  @moduledoc """
  Generate a response using ReqLLM to coordinate with tools/functions.

  This action provides tool-calling capabilities using the ReqLLM infrastructure,
  replacing the LangChain-based implementation with support for 57+ providers.

  ## Features

  - Tool/function calling coordination
  - Multi-provider support (57+ providers via ReqLLM)
  - Automatic tool result aggregation
  - Conversation context management
  - Error handling and recovery

  ## Usage

  ```elixir
  # Basic tool response
  {:ok, result} = Jido.AI.Actions.ReqLlm.ToolResponse.run(%{
    prompt: Jido.AI.Prompt.new(:user, "What is 2 + 2?"),
    tools: [Jido.Actions.Arithmetic.Add]
  })

  # With specific model
  {:ok, model} = Jido.AI.Model.from({:anthropic, [model: "claude-3-5-haiku-latest"]})
  {:ok, result} = Jido.AI.Actions.ReqLlm.ToolResponse.run(%{
    model: model,
    prompt: prompt,
    tools: [Jido.Actions.Arithmetic.Add, Jido.Actions.Arithmetic.Subtract],
    temperature: 0.2
  })
  ```

  ## Response Format

  Returns a map with:
  - `result`: The final text response from the LLM
  - `tool_results`: List of tool execution results

  ## Tool Execution

  Tools are executed automatically when the LLM requests them. The results
  are aggregated and presented in a user-friendly format.
  """
  require Logger

  use Jido.Action,
    name: "generate_tool_response",
    description: "Generate a response using ReqLLM to coordinate with tools/functions",
    schema: [
      model: [
        type: {:custom, Jido.AI.Model, :validate_model_opts, []},
        doc: "The AI model to use (defaults to Claude 3.5 Haiku)",
        default: {:anthropic, [model: "claude-3-5-haiku-latest"]}
      ],
      prompt: [
        type: {:custom, Jido.AI.Prompt, :validate_prompt_opts, []},
        required: true,
        doc: "The prompt to use for the response"
      ],
      tools: [
        type: {:list, :atom},
        default: [],
        doc: "List of Jido.Action modules to use as tools"
      ],
      temperature: [type: :float, default: 0.7, doc: "Temperature for response randomness"],
      timeout: [type: :integer, default: 30_000, doc: "Timeout in milliseconds"],
      verbose: [type: :boolean, default: false, doc: "Verbose output"]
    ]

  alias Jido.AI.Actions.ReqLlm.ChatCompletion
  alias Jido.AI.Model
  alias Jido.AI.Prompt

  @impl true
  def run(params, context) do
    Logger.debug("Starting tool response generation, params: #{inspect(params, pretty: true)}")

    # Set default tools if none provided
    tools = params[:tools] || []

    # Create a model - either use the one provided or create a default one
    model =
      case params[:model] do
        nil ->
          {:ok, model} = Model.from({:anthropic, [model: "claude-3-5-haiku-latest"]})
          model

        model ->
          model
      end

    # Check if we received a message directly instead of a prompt
    # If so, convert it to a proper prompt with the :engine field set
    prompt =
      case params do
        %{message: message, prompt: %Prompt{} = base_prompt} when is_binary(message) ->
          # Add message to the prompt with engine field
          user_message = %{role: :user, content: message, engine: :none}
          %{base_prompt | messages: base_prompt.messages ++ [user_message]}

        %{message: message} when is_binary(message) ->
          # Create a new prompt with the message
          Prompt.new(:user, message, engine: :none)

        %{prompt: prompt} ->
          prompt

        _ ->
          # No prompt or message provided
          {:error, "Missing required parameter: prompt or message"}
      end

    # Early return if prompt validation failed
    case prompt do
      {:error, _} = error ->
        Logger.error("ToolResponse parameter validation failed")
        error

      _ ->
        execute_with_prompt(model, prompt, tools, params, context)
    end
  end

  defp execute_with_prompt(model, prompt, tools, params, context) do
    # Prepare the parameters for ChatCompletion
    completion_params = %{
      model: model,
      prompt: prompt,
      tools: tools,
      temperature: params[:temperature] || 0.7,
      timeout: params[:timeout] || 30_000,
      verbose: params[:verbose] || false
    }

    case ChatCompletion.run(completion_params, context) do
      {:ok, %{content: content, tool_results: tool_results}} ->
        {:ok,
         %{
           result: content,
           tool_results: tool_results
         }}

      {:error, reason} ->
        Logger.warning("ChatCompletion execution failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
