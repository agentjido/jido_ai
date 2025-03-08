defmodule Jido.AI.Actions.Langchain.ChatCompletion do
  @moduledoc """
  A low-level thunk that provides direct access to Langchain's chat completion functionality.
  Supports most Langchain options and integrates with Jido's Model and Prompt structures.
  """
  use Jido.Action,
    name: "langchain_chat_completion",
    description: "Chat completion action using Langchain",
    schema: [
      model: [
        type: {:custom, Jido.AI.Model, :validate_model_opts, []},
        required: true,
        doc:
          "The AI model to use (e.g., {:anthropic, [model_id: \"claude-3-sonnet-20240229\"]} or %Jido.AI.Model{})"
      ],
      prompt: [
        type: {:custom, Jido.AI.Prompt, :validate_prompt_opts, []},
        required: true,
        doc: "The prompt to use for the response"
      ],
      tools: [
        type: {:list, :atom},
        required: false,
        doc: "List of Jido.Action modules for function calling"
      ],
      max_retries: [
        type: :integer,
        default: 0,
        doc: "Number of retries for validation failures"
      ],
      temperature: [type: :float, default: 0.7, doc: "Temperature for response randomness"],
      max_tokens: [type: :integer, default: 1000, doc: "Maximum tokens in response"],
      top_p: [type: :float, doc: "Top p sampling parameter"],
      stop: [type: {:list, :string}, doc: "Stop sequences"],
      timeout: [type: :integer, default: 60_000, doc: "Request timeout in milliseconds"]
    ]

  require Logger
  alias Jido.AI.Model
  alias Jido.AI.Prompt
  alias LangChain.ChatModels.{ChatOpenAI, ChatAnthropic}
  alias LangChain.Message
  alias LangChain.Chains.LLMChain
  alias LangChain.Function

  @valid_providers [:openai, :anthropic]

  @impl true
  def on_before_validate_params(params) do
    with {:ok, model} <- validate_model(params.model),
         {:ok, prompt} <- Prompt.validate_prompt_opts(params.prompt) do
      {:ok, %{params | model: model, prompt: prompt}}
    else
      {:error, reason} ->
        Logger.error("ChatCompletion validation failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def run(params, _context) do
    Logger.info("Running Langchain chat completion with params: #{inspect(params)}")

    with {:ok, model} <- validate_model(params.model),
         {:ok, chat_model} <- create_chat_model(model),
         {:ok, messages} <- convert_messages(params.prompt),
         {:ok, chain} <- create_and_run_chain(chat_model, messages, params) do
      {:ok, %{content: chain.last_message.content, tool_results: []}}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # Private functions

  defp validate_model(%Model{} = model), do: {:ok, model}
  defp validate_model(spec) when is_tuple(spec), do: Model.from(spec)

  defp validate_model(other) do
    Logger.error("Invalid model specification: #{inspect(other)}")
    {:error, "Invalid model specification: #{inspect(other)}"}
  end

  defp create_chat_model(%Model{provider: :openai} = model) do
    {:ok,
     ChatOpenAI.new!(%{
       api_key: model.api_key,
       model: model.model_id,
       temperature: model.temperature || 0.7,
       max_tokens: model.max_tokens || 1000
     })}
  end

  defp create_chat_model(%Model{provider: :anthropic} = model) do
    {:ok,
     ChatAnthropic.new!(%{
       api_key: model.api_key,
       model: model.model_id,
       temperature: model.temperature || 0.7,
       max_tokens: model.max_tokens || 1000
     })}
  end

  defp create_chat_model(%Model{provider: provider}) do
    {:error,
     "Unsupported provider: #{inspect(provider)}. Must be one of: #{inspect(@valid_providers)}"}
  end

  defp convert_messages(prompt) do
    messages =
      Prompt.render(prompt)
      |> Enum.map(fn msg ->
        case msg.role do
          :system -> Message.new_system!(msg.content)
          :user -> Message.new_user!(msg.content)
          :assistant -> Message.new_assistant!(msg.content)
          _ -> Message.new_user!(msg.content)
        end
      end)

    {:ok, messages}
  end

  defp create_and_run_chain(chat_model, messages, params) do
    chain =
      %{llm: chat_model, verbose: true}
      |> LLMChain.new!()
      |> LLMChain.add_messages(messages)

    # Add tools if provided
    chain =
      case params do
        %{tools: tools} when is_list(tools) ->
          functions = Enum.map(tools, &Function.new!(&1.to_tool()))
          LLMChain.add_tools(chain, functions)

        _ ->
          chain
      end

    # Run the chain with appropriate mode based on tools
    mode = if params[:tools], do: :while_needs_response, else: :single
    LLMChain.run(chain, mode: mode)
  end
end
