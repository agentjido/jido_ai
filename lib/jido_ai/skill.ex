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
    boolean_action: [
      type: {:custom, Jido.Util, :validate_actions, []},
      default: Jido.AI.Actions.Instructor.BooleanResponse,
      doc: "The default boolean action to use"
    ],
    tools: [
      type: {:custom, Jido.Util, :validate_actions, []},
      default: [],
      doc: "The tools to use"
    ],
    verbose: [
      type: :boolean,
      default: false,
      doc: "Whether to enable verbose logging"
    ]
  ]

  alias Jido.AI.Prompt
  alias Jido.AI.Prompt.MessageItem

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

    boolean_action =
      Keyword.get(opts, :boolean_action, Jido.AI.Actions.Instructor.BooleanResponse)

    tools = Keyword.get(opts, :tools, [])

    # Register all actions with the agent
    actions = [chat_action, tool_action, boolean_action] ++ tools

    # Register the actions with the agent
    Jido.AI.Agent.register_action(agent, actions)
  end

  @spec validate_opts(keyword()) :: {:ok, keyword()} | {:error, String.t()}
  def validate_opts(opts) do
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

  def router(_opts \\ []) do
    [
      {"jido.ai.chat.response", %Instruction{action: Jido.AI.Actions.Instructor.ChatResponse}},
      {"jido.ai.tool.response", %Instruction{action: Jido.AI.Actions.Langchain.ToolResponse}},
      {"jido.ai.boolean.response",
       %Instruction{action: Jido.AI.Actions.Instructor.BooleanResponse}}
    ]
  end

  def handle_signal(%Signal{type: "jido.ai.tool.response"} = signal, skill_opts) do
    base_prompt = Keyword.get(skill_opts, :prompt)
    rendered_prompt = render_prompt(base_prompt, signal.data)
    tools = Keyword.get(skill_opts, :tools, [])
    model = Keyword.get(skill_opts, :model)
    verbose = Keyword.get(skill_opts, :verbose, false)

    tool_response_params = %{
      model: model,
      prompt: rendered_prompt,
      tools: tools,
      verbose: verbose
    }

    updated_signal = %{signal | data: tool_response_params}

    {:ok, updated_signal}
  end

  def handle_signal(%Signal{type: "jido.ai.chat.response"} = signal, skill_opts) do
    base_prompt = Keyword.get(skill_opts, :prompt)
    rendered_prompt = render_prompt(base_prompt, signal.data)
    model = Keyword.get(skill_opts, :model)

    chat_response_params = %{
      model: model,
      prompt: rendered_prompt
    }

    {:ok, %{signal | data: chat_response_params}}
  end

  def handle_signal(%Signal{type: "jido.ai.boolean.response"} = signal, skill_opts) do
    base_prompt = Keyword.get(skill_opts, :prompt)
    rendered_prompt = render_prompt(base_prompt, signal.data)
    model = Keyword.get(skill_opts, :model)

    boolean_response_params = %{
      model: model,
      prompt: rendered_prompt
    }

    {:ok, %{signal | data: boolean_response_params}}
  end

  defp render_prompt(base_prompt, signal_data) when is_binary(base_prompt) do
    prompt_struct = %Prompt{
      messages: [
        %MessageItem{
          role: :user,
          content: base_prompt,
          engine: :eex
        }
      ]
    }

    render_prompt(prompt_struct, signal_data)
  end

  defp render_prompt(%Prompt{} = base_prompt, signal_data) do
    # Convert system message to user message and render with signal data
    updated_messages =
      Enum.map(base_prompt.messages, fn msg ->
        %{msg | role: :user, engine: :eex}
      end)

    base_prompt = %{base_prompt | messages: updated_messages}
    rendered_prompt = Prompt.render(base_prompt, signal_data)

    # Create a new prompt with the rendered content
    %{base_prompt | messages: rendered_prompt}
  end
end
