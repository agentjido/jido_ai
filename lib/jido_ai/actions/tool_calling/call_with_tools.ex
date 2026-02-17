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

  alias Jido.AI.{Security, ToolAdapter, Turn}
  alias ReqLLM.Context

  @doc """
  Executes the call with tools action.
  """
  @impl Jido.Action
  def run(params, context) do
    with {:ok, validated_params} <- validate_and_sanitize_params(params),
         {:ok, model} <- resolve_model(validated_params[:model]),
         {:ok, llm_context} <- build_messages(validated_params[:prompt], validated_params[:system_prompt]),
         tools = get_tools(validated_params[:tools], context),
         opts = build_opts(validated_params),
         {:ok, response} <-
           ReqLLM.Generation.generate_text(model, llm_context.messages, Keyword.put(opts, :tools, tools)) do
      turn = classify_and_format_response(response, model)

      if validated_params[:auto_execute] && Turn.needs_tools?(turn) do
        execute_tool_turns(turn, llm_context.messages, model, validated_params, context, opts, 1, turn.usage)
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
    tools_input = context[:tools] || []
    convert_to_reqllm_tools(tools_input)
  end

  defp get_tools(tool_names, context) when is_list(tool_names) do
    all_tools = get_tools(nil, context)

    Enum.filter(all_tools, fn tool ->
      get_tool_name(tool) in tool_names
    end)
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
  defp execute_tool_turns(turn, messages, model, params, context, opts, turn_count, usage_acc) do
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

      case execute_tools_and_continue(turn, messages_with_assistant, model, params, context, opts) do
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
            merge_usage(usage_acc, next_turn.usage)
          )

        {:error, reason} ->
          {:ok, %{type: :error, reason: reason, turns: turn_count, model: model, usage: usage_acc}}
      end
    end
  end

  # Validates and sanitizes input parameters to prevent security issues
  defp validate_and_sanitize_params(params) do
    with {:ok, _prompt} <-
           Security.validate_string(params[:prompt], max_length: Security.max_input_length()),
         {:ok, _validated} <- validate_system_prompt_if_needed(params),
         {:ok, max_turns} <- Security.validate_max_turns(params[:max_turns] || 10) do
      {:ok, Map.put(params, :max_turns, max_turns)}
    else
      {:error, :empty_string} -> {:error, :prompt_required}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_system_prompt_if_needed(%{system_prompt: system_prompt}) when is_binary(system_prompt) do
    Security.validate_string(system_prompt, max_length: Security.max_prompt_length())
  end

  defp validate_system_prompt_if_needed(_params), do: {:ok, nil}

  defp execute_tools_and_continue(turn, messages, model, params, context, opts) do
    with {:ok, turn_with_results} <- Turn.run_tools(turn, context, timeout: params[:timeout]) do
      updated_messages = messages ++ Turn.tool_messages(turn_with_results)

      # Preserve generation options across all turns
      tools = get_tools(params[:tools], context)
      turn_opts = opts |> Keyword.put(:tools, tools)

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
end
