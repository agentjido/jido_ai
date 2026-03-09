defmodule Jido.AI.Actions.ToolCalling.CallWithTools do
  @moduledoc """
  A Jido.Action for LLM calls with tool/function calling support.

  This action sends a prompt to an LLM with available tools, handles tool calls
  in the response, and optionally executes tools automatically for multi-turn
  conversations.

  ## Parameters

  * `model` (optional) - Model alias (e.g., `:capable`) or direct spec
  * `prompt` (required) - The user prompt to send to the LLM
  * `system_prompt` (optional) - System prompt to guide behavior
  * `tools` (optional) - List of tool names to include (default: all registered)
  * `max_tokens` (optional) - Maximum tokens to generate (default: `4096`)
  * `temperature` (optional) - Sampling temperature (default: `0.7`)
  * `timeout` (optional) - Request timeout in milliseconds
  * `auto_execute` (optional) - Auto-execute tool calls (default: `false`)
  * `max_turns` (optional) - Max conversation turns with tools (default: `10`)

  ## Examples

      # Basic tool call
      {:ok, result} = Jido.Exec.run(Jido.AI.Actions.ToolCalling.CallWithTools, %{
        prompt: "What's 5 + 3?",
        tools: ["calculator"]
      })

      # With auto-execution
      {:ok, result} = Jido.Exec.run(Jido.AI.Actions.ToolCalling.CallWithTools, %{
        prompt: "Calculate 15 * 7",
        auto_execute: true
      })
  """
  use Jido.Action,
    # Dialyzer has incomplete PLT information about req_llm dependencies
    name: "tool_calling_call_with_tools",
    description: "Send an LLM request with tool calling support",
    category: "ai",
    tags: ["tool-calling", "llm", "function-calling"],
    vsn: "1.0.0",
    schema:
      Zoi.object(%{
        model:
          Zoi.any(description: "Model alias (e.g., :capable) or direct spec string")
          |> Zoi.optional(),
        prompt: Zoi.string(description: "The user prompt to send to the LLM"),
        system_prompt:
          Zoi.string(description: "Optional system prompt to guide the LLM's behavior")
          |> Zoi.optional(),
        tools:
          Zoi.list(Zoi.string(), description: "List of tool names to include (default: all registered)")
          |> Zoi.optional(),
        max_tokens: Zoi.integer(description: "Maximum tokens to generate") |> Zoi.default(4096),
        temperature: Zoi.float(description: "Sampling temperature (0.0-2.0)") |> Zoi.default(0.7),
        timeout: Zoi.integer(description: "Request timeout in milliseconds") |> Zoi.optional(),
        auto_execute:
          Zoi.boolean(description: "Automatically execute tool calls in multi-turn conversation")
          |> Zoi.default(false),
        max_turns:
          Zoi.integer(description: "Maximum conversation turns when auto_execute is true")
          |> Zoi.default(10)
      })

  alias Jido.AI.{ToolAdapter, Turn, Validation}
  alias ReqLLM.Context

  @doc """
  Executes the call with tools action.
  """
  @impl Jido.Action
  def run(params, context) do
    params = apply_context_defaults(params, context)

    with {:ok, validated_params} <- validate_and_sanitize_params(params),
         {:ok, model} <- resolve_model(validated_params[:model]),
         {:ok, llm_context} <- build_messages(validated_params[:prompt], validated_params[:system_prompt]),
         tools = get_tools(validated_params[:tools], context),
         execution_tools = resolve_execution_tools(validated_params[:tools], context),
         opts = build_opts(validated_params),
         {:ok, response} <-
           ReqLLM.Generation.generate_text(model, llm_context.messages, Keyword.put(opts, :tools, tools)) do
      turn = classify_and_format_response(response, model)

      if validated_params[:auto_execute] && Turn.needs_tools?(turn) do
        execute_tool_turns(
          turn,
          llm_context.messages,
          model,
          validated_params,
          context,
          opts,
          1,
          turn.usage,
          tools,
          execution_tools
        )
      else
        {:ok, public_result(turn)}
      end
    end
  end

  # Private Functions

  defp resolve_model(nil), do: {:ok, Jido.AI.resolve_model(:capable)}
  defp resolve_model(model) when is_atom(model), do: {:ok, Jido.AI.resolve_model(model)}
  defp resolve_model(model) when is_binary(model), do: {:ok, model}
  defp resolve_model(_), do: {:error, :invalid_model_format}

  defp build_messages(prompt, nil) do
    Context.normalize(prompt, [])
  end

  defp build_messages(prompt, system_prompt) when is_binary(system_prompt) do
    Context.normalize(prompt, system_prompt: system_prompt)
  end

  defp get_tools(nil, context) do
    tools_input = resolve_tools_input(context)
    convert_to_reqllm_tools(tools_input)
  end

  defp get_tools(tool_names, context) when is_list(tool_names) do
    all_tools = get_tools(nil, context)

    Enum.filter(all_tools, fn tool ->
      get_tool_name(tool) in tool_names
    end)
  end

  defp resolve_execution_tools(tool_names, context) do
    all_tools =
      context
      |> resolve_tools_input()
      |> ToolAdapter.to_action_map()

    case tool_names do
      names when is_list(names) -> Map.take(all_tools, names)
      _ -> all_tools
    end
  end

  defp convert_to_reqllm_tools(tools) when is_list(tools) do
    Enum.map(tools, &ToolAdapter.from_action/1)
  end

  defp convert_to_reqllm_tools(tools) when is_map(tools) do
    tools |> Map.values() |> convert_to_reqllm_tools()
  end

  defp convert_to_reqllm_tools(_), do: []

  defp get_tool_name(%{name: name}), do: name
  defp get_tool_name(_), do: nil

  defp build_opts(params) do
    opts = [
      max_tokens: params[:max_tokens],
      temperature: params[:temperature]
    ]

    opts =
      if params[:timeout] do
        Keyword.put(opts, :receive_timeout, params[:timeout])
      else
        opts
      end

    opts
  end

  defp classify_and_format_response(response, model), do: Turn.from_response(response, model: model)

  # Multi-turn execution for auto_execute
  defp execute_tool_turns(
         turn,
         messages,
         model,
         params,
         context,
         opts,
         turn_count,
         usage_acc,
         llm_tools,
         execution_tools
       ) do
    # Use validated max_turns from params (already sanitized with hard limit)
    max_turns = params[:max_turns]

    if turn_count > max_turns do
      {:ok,
       turn
       |> public_result()
       |> Map.put(:reason, :max_turns_reached)
       |> Map.put(:turns, max_turns)
       |> Map.put(:usage, usage_acc)}
    else
      messages_with_assistant = append_assistant_message(messages, turn)

      case execute_tools_and_continue(
             turn,
             messages_with_assistant,
             model,
             params,
             context,
             opts,
             llm_tools,
             execution_tools
           ) do
        {:final_answer, final_turn, next_messages} ->
          {:ok,
           final_turn
           |> public_result()
           |> Map.put(:turns, turn_count)
           |> Map.put(:messages, next_messages)
           |> Map.put(:usage, merge_usage(usage_acc, final_turn.usage))}

        {:more_tools, next_turn, next_messages} ->
          execute_tool_turns(
            next_turn,
            next_messages,
            model,
            params,
            context,
            opts,
            turn_count + 1,
            merge_usage(usage_acc, next_turn.usage),
            llm_tools,
            execution_tools
          )

        {:error, reason} ->
          {:ok, %{type: :error, reason: reason, turns: turn_count, model: model, usage: usage_acc}}
      end
    end
  end

  # Validates and sanitizes input parameters to prevent security issues
  defp validate_and_sanitize_params(params) do
    with {:ok, _prompt} <-
           Validation.validate_string(params[:prompt], max_length: Validation.max_input_length()),
         {:ok, _validated} <- validate_system_prompt_if_needed(params),
         {:ok, max_turns} <- Validation.validate_max_turns(params[:max_turns] || 10) do
      {:ok, Map.put(params, :max_turns, max_turns)}
    else
      {:error, :empty_string} -> {:error, :prompt_required}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_system_prompt_if_needed(%{system_prompt: system_prompt}) when is_binary(system_prompt) do
    Validation.validate_string(system_prompt, max_length: Validation.max_prompt_length())
  end

  defp validate_system_prompt_if_needed(_params), do: {:ok, nil}

  defp execute_tools_and_continue(turn, messages, model, params, context, opts, llm_tools, execution_tools) do
    with {:ok, turn_with_results} <-
           Turn.run_tools(turn, context, timeout: params[:timeout], tools: execution_tools) do
      updated_messages = messages ++ Turn.tool_messages(turn_with_results)

      # Preserve generation options across all turns
      turn_opts = opts |> Keyword.put(:tools, llm_tools)

      # Call LLM again with tool results
      case ReqLLM.Generation.generate_text(model, updated_messages, turn_opts) do
        {:ok, response} ->
          next_turn = classify_and_format_response(response, model)
          next_messages = append_assistant_message(updated_messages, next_turn)

          if Turn.needs_tools?(next_turn) do
            {:more_tools, next_turn, next_messages}
          else
            {:final_answer, next_turn, next_messages}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp append_assistant_message(messages, %Turn{} = turn), do: messages ++ [Turn.assistant_message(turn)]

  defp public_result(%Turn{} = turn), do: Turn.to_result_map(turn)

  defp merge_usage(first, second) do
    first_usage = normalize_usage(first)
    second_usage = normalize_usage(second)

    input_tokens = first_usage.input_tokens + second_usage.input_tokens
    output_tokens = first_usage.output_tokens + second_usage.output_tokens

    %{
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      total_tokens: input_tokens + output_tokens
    }
  end

  defp normalize_usage(nil), do: %{input_tokens: 0, output_tokens: 0, total_tokens: 0}

  defp normalize_usage(%{} = usage) do
    input_tokens = Map.get(usage, :input_tokens, 0)
    output_tokens = Map.get(usage, :output_tokens, 0)
    total_tokens = Map.get(usage, :total_tokens, input_tokens + output_tokens)

    %{input_tokens: input_tokens, output_tokens: output_tokens, total_tokens: total_tokens}
  end

  defp apply_context_defaults(params, context) when is_map(params) do
    context = normalize_context(context)
    provided = provided_params(context)

    model_default =
      first_present([
        context[:default_model],
        context[:model],
        plugin_default(context, :default_model)
      ])

    system_prompt_default =
      first_present([
        context[:default_system_prompt],
        plugin_default(context, :default_system_prompt),
        plugin_default(context, :system_prompt)
      ])

    max_tokens_default =
      first_present([
        context[:default_max_tokens],
        plugin_default(context, :default_max_tokens)
      ])

    temperature_default =
      first_present([
        context[:default_temperature],
        plugin_default(context, :default_temperature)
      ])

    auto_execute_default =
      first_present([
        context[:auto_execute],
        plugin_default(context, :auto_execute)
      ])

    max_turns_default =
      first_present([
        context[:max_turns],
        plugin_default(context, :max_turns)
      ])

    params
    |> put_default_param(:model, model_default, provided)
    |> put_default_param(:system_prompt, system_prompt_default, provided)
    |> put_default_param(:max_tokens, max_tokens_default, provided)
    |> put_default_param(:temperature, temperature_default, provided)
    |> put_default_param(:auto_execute, auto_execute_default, provided)
    |> put_default_param(:max_turns, max_turns_default, provided)
  end

  defp apply_context_defaults(params, _context), do: params

  defp put_default_param(params, _key, nil, _provided), do: params

  defp put_default_param(params, key, default, :unknown) do
    if Map.get(params, key) in [nil, ""] do
      Map.put(params, key, default)
    else
      params
    end
  end

  defp put_default_param(params, key, default, provided) do
    if provided_param?(provided, key) do
      params
    else
      Map.put(params, key, default)
    end
  end

  defp provided_params(%{provided_params: provided}) when is_list(provided), do: provided
  defp provided_params(_), do: :unknown

  defp provided_param?(provided, key) when is_list(provided) do
    key_str = Atom.to_string(key)
    Enum.any?(provided, fn k -> k == key or k == key_str end)
  end

  defp resolve_tools_input(context) do
    first_present([
      context[:tools],
      get_in(context, [:tool_calling, :tools]),
      get_in(context, [:chat, :tools]),
      get_in(context, [:state, :tool_calling, :tools]),
      get_in(context, [:state, :chat, :tools]),
      get_in(context, [:agent, :state, :tool_calling, :tools]),
      get_in(context, [:agent, :state, :chat, :tools]),
      get_in(context, [:plugin_state, :tool_calling, :tools]),
      get_in(context, [:plugin_state, :chat, :tools]),
      []
    ])
  end

  defp plugin_default(context, key) do
    first_present([
      get_in(context, [:plugin_state, :chat, key]),
      get_in(context, [:plugin_state, :tool_calling, key]),
      get_in(context, [:state, :chat, key]),
      get_in(context, [:state, :tool_calling, key]),
      get_in(context, [:agent, :state, :chat, key]),
      get_in(context, [:agent, :state, :tool_calling, key])
    ])
  end

  defp first_present(values), do: Enum.find(values, &(not is_nil(&1)))
  defp normalize_context(context) when is_map(context), do: context
  defp normalize_context(_), do: %{}
end
