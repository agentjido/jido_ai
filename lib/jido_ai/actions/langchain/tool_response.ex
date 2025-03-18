defmodule Jido.AI.Actions.Langchain.ToolResponse do
  require Logger

  use Jido.Action,
    name: "generate_tool_response",
    description: "Generate a response using LangChain to coordinate with tools/functions",
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
      timeout: [type: :integer, default: 30_000, doc: "Timeout in milliseconds"]
    ]

  alias Jido.AI.Actions.Langchain, as: LangchainAction
  alias Jido.AI.Model
  alias Jido.AI.Prompt

  def test do
    {:ok, model} = Model.from({:anthropic, [model: "claude-3-5-haiku-latest"]})
    prompt = Prompt.new(:user, "What is (527 + 313) - 248?")
    tools = [Jido.Actions.Arithmetic.Add, Jido.Actions.Arithmetic.Subtract]

    {:ok, result} = LangchainAction.run(%{model: model, prompt: prompt, tools: tools}, %{})
    IO.inspect(result, label: "Result")
  end

  def run(params, _context) do
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

        _ ->
          params.prompt
      end

    # Prepare the parameters for BaseCompletion
    completion_params = %{
      model: model,
      prompt: prompt,
      tools: tools,
      temperature: params[:temperature] || 0.7
    }

    case LangchainAction.run(completion_params, %{}) do
      {:ok, %{content: content, tool_results: tool_results}} ->
        {:ok,
         %{
           result: content,
           tool_results: tool_results
         }}

      {:error, reason} ->
        Logger.warning("BaseCompletion execution failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
