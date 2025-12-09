defmodule Jido.AI.Actions.TextCompletion do
  @moduledoc """
  Simple text completion action using ReqLLM for provider-agnostic LLM calls.

  This action provides basic chat completion functionality without structured output validation.
  It's suitable for use cases where you just need text responses from LLMs.

  ## Features

  - Multi-provider support through ReqLLM (Anthropic, OpenAI, etc.)
  - Simple API for text-only responses
  - Configurable temperature and max_tokens
  - Works with Jido.AI.Model and Jido.AI.Prompt structures

  ## Usage

      # Basic usage
      {:ok, result, _} = Jido.AI.Actions.TextCompletion.run(%{
        model: %Jido.AI.Model{provider: :anthropic, model: "claude-3-5-sonnet-20241022"},
        prompt: Jido.AI.Prompt.new(:user, "What is the capital of France?")
      })

      result.content #=> "The capital of France is Paris."

      # With options
      {:ok, result, _} = Jido.AI.Actions.TextCompletion.run(%{
        model: %Jido.AI.Model{provider: :openai, model: "gpt-4o"},
        prompt: Jido.AI.Prompt.new(:user, "Tell me a joke"),
        temperature: 0.9,
        max_tokens: 500
      })
  """

  use Jido.Action,
    name: "text_completion",
    description: "Generate text completion using ReqLLM",
    schema: [
      model: [
        type: {:custom, Jido.AI.Model, :type, []},
        required: true,
        doc: "The model configuration (Jido.AI.Model struct)"
      ],
      prompt: [
        type: {:custom, Jido.AI.Prompt, :type, []},
        required: true,
        doc: "The prompt with messages (Jido.AI.Prompt struct)"
      ],
      temperature: [
        type: :float,
        default: 0.7,
        doc: "Sampling temperature (0.0-1.0)"
      ],
      max_tokens: [
        type: :pos_integer,
        default: 2000,
        doc: "Maximum tokens in completion"
      ]
    ]

  require Logger

  alias Jido.AI.{Model, Prompt}

  @impl true
  def run(params, _context) do
    with {:ok, reqllm_model} <- build_reqllm_model(params.model, params),
         {:ok, messages} <- convert_messages(params.prompt),
         {:ok, response} <- generate_completion(reqllm_model, messages),
         {:ok, content} <- extract_content(response) do
      {:ok, %{content: content}, %{}}
    else
      {:error, reason} = error ->
        Logger.error("Text completion failed: #{inspect(reason)}")
        error
    end
  end

  @doc false
  @spec build_reqllm_model(Model.t() | ReqLLM.Model.t(), map()) :: {:ok, tuple()} | {:error, term()}
  defp build_reqllm_model(%ReqLLM.Model{} = model, params) do
    # Already a ReqLLM.Model, build tuple directly
    reqllm_tuple =
      {model.provider, model.model,
       [
         temperature: params.temperature,
         max_tokens: params.max_tokens
       ]}

    {:ok, reqllm_tuple}
  end

  defp build_reqllm_model(%Model{} = model, params) do
    # Convert Jido.AI.Model to ReqLLM.Model
    case Jido.AI.Model.from(model) do
      {:ok, reqllm_model} ->
        build_reqllm_model(reqllm_model, params)

      {:error, reason} ->
        {:error, "Failed to build ReqLLM model: #{inspect(reason)}"}
    end
  rescue
    error ->
      {:error, "Failed to build ReqLLM model: #{inspect(error)}"}
  end

  @doc false
  @spec convert_messages(Prompt.t()) :: {:ok, list()} | {:error, term()}
  defp convert_messages(%Prompt{messages: messages}) when is_list(messages) do
    converted =
      Enum.map(messages, fn message ->
        case message.role do
          :system -> ReqLLM.Context.system(message.content)
          :user -> ReqLLM.Context.user(message.content)
          :assistant -> ReqLLM.Context.assistant(message.content)
          other -> raise "Unsupported message role: #{inspect(other)}"
        end
      end)

    {:ok, converted}
  rescue
    error ->
      {:error, "Failed to convert messages: #{inspect(error)}"}
  end

  @doc false
  @spec generate_completion(tuple(), list()) :: {:ok, term()} | {:error, term()}
  defp generate_completion(model, messages) do
    case ReqLLM.generate_text(model, messages) do
      {:ok, response} ->
        {:ok, response}

      {:error, reason} ->
        Logger.debug("ReqLLM generation failed: #{inspect(reason)}")
        {:error, reason}

      other ->
        {:error, "Unexpected response from ReqLLM: #{inspect(other)}"}
    end
  rescue
    error ->
      {:error, "Exception during LLM call: #{inspect(error)}"}
  end

  @doc false
  @spec extract_content(term()) :: {:ok, String.t()} | {:error, term()}
  defp extract_content(response) do
    case ReqLLM.Response.text(response) do
      text when is_binary(text) ->
        {:ok, text}

      nil ->
        {:error, "No text content in response"}

      other ->
        {:error, "Unexpected text format: #{inspect(other)}"}
    end
  rescue
    error ->
      {:error, "Failed to extract content: #{inspect(error)}"}
  end
end
