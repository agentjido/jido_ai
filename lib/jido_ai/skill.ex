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
      default: Jido.AI.Actions.Internal.ChatResponse,
      doc:
        "The chat action to use (now uses internal implementation for broader provider support)"
    ],
    tool_action: [
      type: {:custom, Jido.Util, :validate_actions, []},
      default: Jido.AI.Actions.ReqLlm.ToolResponse,
      doc: "The default tool action to use (now uses ReqLLM for 57+ provider support)"
    ],
    boolean_action: [
      type: {:custom, Jido.Util, :validate_actions, []},
      default: Jido.AI.Actions.Internal.BooleanResponse,
      doc: "The default boolean action to use (now uses internal implementation)"
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
      Keyword.get(opts, :chat_action, Jido.AI.Actions.Internal.ChatResponse)

    tool_action =
      Keyword.get(opts, :tool_action, Jido.AI.Actions.ReqLlm.ToolResponse)

    boolean_action =
      Keyword.get(opts, :boolean_action, Jido.AI.Actions.Internal.BooleanResponse)

    tools = Keyword.get(opts, :tools, [])

    # Add deprecation warning if using LangChain
    if tool_action == Jido.AI.Actions.Langchain.ToolResponse do
      Logger.warning("""
      LangChain actions are deprecated and will be removed in v0.6.0.
      Please migrate to Jido.AI.Actions.ReqLlm.ToolResponse for:
      - Support for 57+ providers (vs 3-4 with LangChain)
      - Better error handling
      - Lighter dependencies

      To migrate, update your Skill configuration:
        tool_action: Jido.AI.Actions.ReqLlm.ToolResponse

      Or remove the tool_action option to use the new default.
      """)
    end

    # Add deprecation warning if using Instructor
    if chat_action in [
         Jido.AI.Actions.Instructor.ChatResponse,
         Jido.AI.Actions.Instructor.BooleanResponse,
         Jido.AI.Actions.Instructor.ChoiceResponse
       ] or
         boolean_action in [
           Jido.AI.Actions.Instructor.ChatResponse,
           Jido.AI.Actions.Instructor.BooleanResponse,
           Jido.AI.Actions.Instructor.ChoiceResponse
         ] do
      Logger.warning("""
      Instructor actions are deprecated and will be removed in v0.7.0.
      Please migrate to Jido.AI.Actions.Internal.* for:
      - No external Instructor dependency
      - Support for 57+ providers via ReqLLM
      - Better error handling and retry logic
      - Lighter installation footprint

      To migrate, update your Skill configuration:
        chat_action: Jido.AI.Actions.Internal.ChatResponse
        boolean_action: Jido.AI.Actions.Internal.BooleanResponse

      Or remove these options to use the new defaults.
      """)
    end

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
      {"jido.ai.chat.response", %Instruction{action: Jido.AI.Actions.Internal.ChatResponse}},
      {"jido.ai.tool.response", %Instruction{action: Jido.AI.Actions.ReqLlm.ToolResponse}},
      {"jido.ai.boolean.response", %Instruction{action: Jido.AI.Actions.Internal.BooleanResponse}}
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

  def handle_signal(%Signal{type: type} = signal, skill_opts)
      when type in ["jido.ai.chat.response", "jido.ai.boolean.response"] do
    base_prompt = Keyword.get(skill_opts, :prompt)
    rendered_prompt = render_prompt(base_prompt, signal.data)
    model = Keyword.get(skill_opts, :model)

    chat_response_params = %{
      model: model,
      prompt: rendered_prompt
    }

    {:ok, %{signal | data: chat_response_params}}
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
