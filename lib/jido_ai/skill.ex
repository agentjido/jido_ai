defmodule Jido.AI.Skill do
  @moduledoc """
  General purpose AI skill powered by Jido
  """
  require Logger
  @ai_opts_key :ai
  @ai_opts_schema [
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
      default: Jido.AI.Actions.Instructor.ChatResponse,
      doc: "The chat action to use"
    ],
    tool_action: [
      type: {:custom, Jido.Util, :validate_actions, []},
      default: Jido.AI.Actions.Langchain.ToolResponse,
      doc: "The default tool action to use"
    ],
    tools: [
      type: {:custom, Jido.Util, :validate_actions, []},
      default: [],
      doc: "The tools to use"
    ]
  ]

  use Jido.Skill,
    name: "jido_ai_skill",
    description: "General purpose AI skill powered by Jido",
    vsn: "0.1.0",
    opts_key: @ai_opts_key,
    opts_schema: @ai_opts_schema,
    signal_patterns: [
      "jido.ai.**"
    ]

  def mount(agent, opts) do
    chat_action =
      Keyword.get(opts, :chat_action, Jido.AI.Actions.Instructor.ChatResponse)

    tool_action =
      Keyword.get(opts, :tool_action, Jido.AI.Actions.Langchain.ToolResponse)

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

  def router(opts \\ []) do
    model = Keyword.get(opts, :model)

    [
      {"jido.ai.chat.response",
       %Instruction{
         action: Jido.AI.Actions.Instructor.ChatResponse,
         params: %{model: model}
       }},
      {"jido.ai.tool.response",
       %Instruction{
         action: Jido.AI.Actions.Langchain.ToolResponse,
         params: %{model: model}
       }}
    ]
  end

  def handle_signal(signal, skill_opts) do
    with {:ok, base_prompt} <-
           Jido.AI.Prompt.validate_prompt_opts(Keyword.get(skill_opts, :prompt)) do
      # Convert system message to user message and render with signal data
      updated_messages =
        Enum.map(base_prompt.messages, fn msg ->
          %{msg | role: :user, engine: :eex}
        end)

      base_prompt = %{base_prompt | messages: updated_messages}
      rendered_prompt = Jido.AI.Prompt.render(base_prompt, signal.data)
      # IO.inspect(rendered_prompt, label: "Rendered prompt")

      # Create a new prompt with the rendered content
      updated_prompt = %{base_prompt | messages: rendered_prompt}
      # IO.inspect(updated_prompt, label: "Updated prompt")

      # Update the signal data with the new prompt
      updated_signal = %{signal | data: Map.put(signal.data, :prompt, updated_prompt)}

      {:ok, updated_signal}
    else
      {:error, reason} ->
        Logger.error("Failed to validate prompt: #{inspect(reason)}")
        {:ok, signal}
    end
  end

  def transform_result(_signal, result, _skill_opts) do
    # Logger.debug("SKILL TRANSFORM RESULT: >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>")
    # Logger.debug("Transforming result: #{inspect(result, pretty: true)}")
    # Logger.debug("Skill opts: #{inspect(skill_opts, pretty: true)}")
    {:ok, result}
  end
end
