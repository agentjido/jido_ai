defmodule Jido.AI.Skill do
  @moduledoc """
  General purpose AI skill powered by Jido
  """
  use Jido.Skill,
    name: "jido_ai_skill",
    description: "General purpose AI skill powered by Jido",
    vsn: "0.1.0",
    opts_key: :ai,
    opts_schema: [
      model: [
        type: {:custom, Jido.AI.Model, :validate_model_opts, []},
        required: true,
        doc: "The AI model to use"
      ],
      prompt: [
        type: {:custom, Jido.AI.Prompt, :validate_prompt_opts, []},
        default: "You are a helpful assistant",
        doc: "The default instructions to follow (string or Prompt struct)"
      ],
      response_schema: [
        type: :keyword_list,
        default: [],
        doc: "A NimbleOptions schema to validate the AI response"
      ],
      chat_action: [
        type: {:custom, Jido.Util, :validate_actions, []},
        default: Jido.AI.Actions.OpenaiEx.ChatCompletion,
        doc: "The chat action to use"
      ],
      tool_action: [
        type: {:custom, Jido.Util, :validate_actions, []},
        default: Jido.AI.Actions.Langchain.GenerateToolResponse,
        doc: "The default tool action to use"
      ],
      tools: [
        type: {:custom, Jido.Util, :validate_actions, []},
        default: [],
        doc: "The tools to use"
      ]
    ],
    signals: %{
      input: [
        "arithmetic.add",
        "arithmetic.subtract",
        "arithmetic.multiply",
        "arithmetic.divide",
        "arithmetic.square",
        "arithmetic.eval"
      ],
      output: [
        "arithmetic.result",
        "arithmetic.error"
      ]
    }

  @doc """
  Validates and converts the prompt option.

  Accepts either:
  - A string, which is converted to a system message in a Prompt struct
  - An existing Prompt struct, which is returned as-is

  ## Examples

      iex> Jido.AI.Skill.validate_prompt_opts("You are a helpful assistant")
      {:ok, %Jido.AI.Prompt{messages: [%Jido.AI.Prompt.MessageItem{role: :system, content: "You are a helpful assistant", engine: :none}]}}

      iex> prompt = Jido.AI.Prompt.new(:system, "Custom prompt")
      iex> Jido.AI.Skill.validate_prompt_opts(prompt)
      {:ok, prompt}
  """
  @spec validate_prompt_opts(String.t() | Jido.AI.Prompt.t()) :: {:ok, Jido.AI.Prompt.t()} | {:error, String.t()}
  def validate_prompt_opts(prompt) when is_binary(prompt) do
    # Convert the string to a Prompt struct with a system message
    {:ok, Jido.AI.Prompt.new(:system, prompt)}
  end

  def validate_prompt_opts(%Jido.AI.Prompt{} = prompt) do
    # If it's already a Prompt struct, return it as-is
    {:ok, prompt}
  end

  def validate_prompt_opts(other) do
    {:error, "Expected a string or a Jido.AI.Prompt struct, got: #{inspect(other)}"}
  end

  def mount(agent, opts) do
    chat_action =
      Keyword.get(opts, :chat_action, Jido.AI.Actions.OpenaiEx.ChatCompletion)

    tool_action =
      Keyword.get(opts, :tool_action, Jido.AI.Actions.Langchain.GenerateToolResponse)

    # Register the actions with the agent
    Jido.AI.Agent.register_action(agent, [chat_action, tool_action])
  end

  @spec validate_opts(keyword()) :: {:ok, keyword()} | {:error, String.t()}
  def validate_opts(opts) do
    # Get AI opts if they exist under the ai key, otherwise use full opts
    ai_opts =
      if Keyword.has_key?(opts, @ai_opts_key) do
        Keyword.get(opts, @ai_opts_key)
      else
        opts
      end

    case NimbleOptions.validate(ai_opts, @ai_opts_schema) do
      {:ok, validated_opts} ->
        {:ok, validated_opts}

      {:error, errors} ->
        {:error, errors}
    end
  end

  def router do
    [
      # High priority weather alerts
      %{
        path: "weather_monitor.alert.**",
        instruction: %{
          action: Actions.GenerateWeatherAlert
        },
        priority: 100
      }
    ]
  end

  def chat_response(agent, message, opts \\ []) do
    prompt = Keyword.get(opts, :prompt, Jido.AI.Prompt.new(:system, "You are a helpful assistant"))

    # Ensure prompt is a Prompt struct
    prompt = case prompt do
      %Jido.AI.Prompt{} -> prompt
      string when is_binary(string) -> Jido.AI.Prompt.new(:system, string)
      _ -> Jido.AI.Prompt.new(:system, "You are a helpful assistant")
    end

    # Add the user message to the prompt
    prompt = Jido.AI.Prompt.add_message(prompt, :user, message)

    {:ok, signal} =
      Jido.Signal.new(%{
        type: "jido.ai.chat.response",
        data: %{
          prompt: prompt,
          history: [],
          message: message
        }
      })

    Jido.Agent.call(agent, signal)
  end

  def tool_response(agent, message, opts \\ []) do
    prompt = Keyword.get(opts, :prompt, Jido.AI.Prompt.new(:system, "You are a helpful assistant"))

    # Ensure prompt is a Prompt struct
    prompt = case prompt do
      %Jido.AI.Prompt{} -> prompt
      string when is_binary(string) -> Jido.AI.Prompt.new(:system, string)
      _ -> Jido.AI.Prompt.new(:system, "You are a helpful assistant")
    end

    # Add the user message to the prompt
    prompt = Jido.AI.Prompt.add_message(prompt, :user, message)

    {:ok, signal} =
      Jido.Signal.new(%{
        type: "jido.ai.tool.response",
        data: %{
          prompt: prompt,
          history: [],
          message: message
        }
      })

    Jido.Agent.call(agent, signal)
  end
end
