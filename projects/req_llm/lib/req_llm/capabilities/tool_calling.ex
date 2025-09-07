defmodule ReqLLM.Capabilities.ToolCalling do
  @moduledoc """
  Tool calling capability verification for AI models.

  Verifies that a model can perform tool calling by providing a simple
  tool definition and validating the response contains tool calls.
  """

  @behaviour ReqLLM.Capability

  @impl true
  def id, do: :tool_calling

  @impl true
  def advertised?(model) do
    # Check if model has tool_call capability set to true
    case model.capabilities do
      %{tool_call?: true} -> true
      _ -> false
    end
  end

  @impl true
  def verify(model, opts) do
    model_spec = "#{model.provider}:#{model.model}"
    timeout = Keyword.get(opts, :timeout, 10_000)

    # Define a simple test tool
    tools = [
      %{
        name: "get_current_weather",
        description: "Get the current weather for a specific location",
        parameters_schema: %{
          type: "object",
          properties: %{
            location: %{
              type: "string",
              description: "The city and state, e.g. San Francisco, CA"
            }
          },
          required: ["location"]
        }
      }
    ]

    # Use provider_options to pass timeout to the HTTP client
    req_llm_opts = [
      tools: tools,
      tool_choice: "auto",
      provider_options: %{
        receive_timeout: timeout,
        timeout: timeout
      }
    ]

    case ReqLLM.generate_text(
           model_spec,
           "What's the weather like in San Francisco?",
           req_llm_opts
         ) do
      {:ok, %Req.Response{body: %{tool_calls: tool_calls}}}
      when is_list(tool_calls) and tool_calls != [] ->
        # Successfully got tool calls - verify they make sense
        first_tool_call = List.first(tool_calls)

        if Map.has_key?(first_tool_call, :name) and Map.has_key?(first_tool_call, :arguments) do
          {:ok,
           %{
             model_id: model_spec,
             tool_calls_count: length(tool_calls),
             first_tool_name: first_tool_call[:name],
             first_tool_args: first_tool_call[:arguments]
           }}
        else
          {:error, "Tool call format invalid: #{inspect(first_tool_call)}"}
        end

      {:ok, %Req.Response{body: response}} ->
        {:error, "No tool calls received, got text response: #{inspect(response)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
