defmodule Jido.AI.Skills.ToolCalling.Actions.CallWithTools do
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
      {:ok, result} = Jido.Exec.run(Jido.AI.Skills.ToolCalling.Actions.CallWithTools, %{
        prompt: "What's 5 + 3?",
        tools: ["calculator"]
      })

      # With auto-execution
      {:ok, result} = Jido.Exec.run(Jido.AI.Skills.ToolCalling.Actions.CallWithTools, %{
        prompt: "Calculate 15 * 7",
        auto_execute: true
      })
  """

  use Jido.Action,
    name: "tool_calling_call_with_tools",
    description: "Send an LLM request with tool calling support",
    category: "ai",
    tags: ["tool-calling", "llm", "function-calling"],
    vsn: "1.0.0",
    schema: Zoi.object(%{
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
      max_tokens:
        Zoi.integer(description: "Maximum tokens to generate") |> Zoi.default(4096),
      temperature: Zoi.float(description: "Sampling temperature (0.0-2.0)") |> Zoi.default(0.7),
      timeout: Zoi.integer(description: "Request timeout in milliseconds") |> Zoi.optional(),
      auto_execute:
        Zoi.boolean(description: "Automatically execute tool calls in multi-turn conversation")
        |> Zoi.default(false),
      max_turns:
        Zoi.integer(description: "Maximum conversation turns when auto_execute is true")
        |> Zoi.default(10)
    })

  alias Jido.AI.{Config, Helpers, Security, Tools}

  @doc """
  Executes the call with tools action.
  """
  @impl Jido.Action
  def run(params, _context) do
    with {:ok, validated_params} <- validate_and_sanitize_params(params),
         {:ok, model} <- resolve_model(validated_params[:model]),
         {:ok, messages} <- build_messages(validated_params[:prompt], validated_params[:system_prompt]),
         tools <- get_tools(validated_params[:tools]),
         opts <- build_opts(validated_params),
         {:ok, response} <- ReqLLM.Generation.generate_text(model, messages, Keyword.put(opts, :tools, tools)) do
      result = classify_and_format_response(response, model)

      if validated_params[:auto_execute] && result.type == :tool_calls do
        execute_tool_turns(result, messages, model, validated_params, 1)
      else
        {:ok, result}
      end
    end
  end

  # Private Functions

  defp resolve_model(nil), do: {:ok, Config.resolve_model(:capable)}
  defp resolve_model(model) when is_atom(model), do: {:ok, Config.resolve_model(model)}
  defp resolve_model(model) when is_binary(model), do: {:ok, model}
  defp resolve_model(_), do: {:error, :invalid_model_format}

  defp build_messages(prompt, nil) do
    Helpers.build_messages(prompt, [])
  end

  defp build_messages(prompt, system_prompt) when is_binary(system_prompt) do
    Helpers.build_messages(prompt, system_prompt: system_prompt)
  end

  defp get_tools(nil) do
    Tools.Registry.ensure_started()
    Tools.Registry.to_reqllm_tools()
  end

  defp get_tools(tool_names) when is_list(tool_names) do
    Tools.Registry.ensure_started()
    all_tools = Tools.Registry.to_reqllm_tools()

    Enum.filter(all_tools, fn tool ->
      tool_name = get_tool_name(tool)
      tool_name in tool_names
    end)
  end

  defp get_tool_name(%{name: name}), do: name
  defp get_tool_name(%ReqLLM.Tool{} = tool), do: ReqLLM.Tool.name(tool)
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

  defp classify_and_format_response(response, model) do
    classification = Helpers.classify_llm_response(response)

    %{
      type: classification.type,
      text: Map.get(classification, :text, ""),
      tool_calls: Map.get(classification, :tool_calls, []),
      model: model,
      usage: extract_usage(response)
    }
  end

  defp extract_usage(%{usage: usage}) when is_map(usage) do
    %{
      input_tokens: Map.get(usage, :input_tokens, 0),
      output_tokens: Map.get(usage, :output_tokens, 0),
      total_tokens: Map.get(usage, :total_tokens, 0)
    }
  end

  defp extract_usage(_), do: %{input_tokens: 0, output_tokens: 0, total_tokens: 0}

  # Multi-turn execution for auto_execute
  defp execute_tool_turns(result, messages, model, params, turn) do
    # Use validated max_turns from params (already sanitized with hard limit)
    max_turns = params[:max_turns]

    if turn > max_turns do
      {:ok, Map.put(result, :reason, :max_turns_reached)}
    else
      case execute_tools_and_continue(result.tool_calls, messages, model, params) do
        {:final_answer, final_result} ->
          {:ok, Map.put(final_result, :turns, turn)}

        {:more_tools, new_result} ->
          execute_tool_turns(new_result, messages, model, params, turn + 1)

        {:error, reason} ->
          {:ok, %{type: :error, reason: reason, turns: turn}}
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

  defp execute_tools_and_continue(tool_calls, messages, model, params) do
    # Execute all tool calls
    tool_results = execute_all_tools(tool_calls)

    # Add tool result messages to conversation
    updated_messages = add_tool_results_to_messages(messages, tool_results)

    # Build opts for next call
    opts = build_opts(params)
    tools = get_tools(params[:tools])

    # Call LLM again with tool results
    case ReqLLM.Generation.generate_text(model, updated_messages, tools: tools) do
      {:ok, response} ->
        result = classify_and_format_response(response, model)

        if result.type == :tool_calls do
          {:more_tools, result}
        else
          {:final_answer, result}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_all_tools(tool_calls) do
    Enum.map(tool_calls, fn tool_call ->
      result = execute_single_tool(tool_call)

      %{
        id: Map.get(tool_call, :id, ""),
        name: Map.get(tool_call, :name, ""),
        result: format_tool_result(result)
      }
    end)
  end

  defp execute_single_tool(tool_call) do
    name = Map.get(tool_call, :name)
    arguments = Map.get(tool_call, :arguments, %{})

    Tools.Executor.execute(name, arguments, %{})
  end

  defp format_tool_result({:ok, result}) when is_binary(result), do: result
  defp format_tool_result({:ok, result}) when is_map(result) or is_list(result), do: Jason.encode!(result)
  defp format_tool_result({:ok, result}), do: inspect(result)
  defp format_tool_result({:error, error}) when is_map(error), do: Map.get(error, :error, "Execution failed")
  defp format_tool_result({:error, _reason}), do: "Execution failed"

  defp add_tool_results_to_messages(messages, tool_results) do
    tool_messages =
      Enum.map(tool_results, fn tool_result ->
        %{
          role: :tool,
          tool_call_id: tool_result.id,
          name: tool_result.name,
          content: tool_result.result
        }
      end)

    messages ++ tool_messages
  end
end
