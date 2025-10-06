defmodule Jido.AI.Actions.OpenaiEx.TestHelpers do
  @moduledoc """
  Test helper functions for accessing OpenaiEx private functions during testing.
  This module should only be compiled in the test environment.
  """

  if Mix.env() == :test do
    alias OpenaiEx.ChatMessage
    alias ReqLLM.Provider.Generated.ValidProviders

    @doc """
    Test helper for convert_chat_messages_to_jido_format/1
    """
    def convert_chat_messages_to_jido_format(chat_messages) do
      Enum.map(chat_messages, fn
        %{role: role, content: content} ->
          %{role: role, content: content}

        # Handle OpenaiEx ChatMessage structs
        %module{} = msg when module in [ChatMessage] ->
          %{role: msg.role, content: msg.content}

        # Handle other message formats
        msg when is_map(msg) ->
          %{role: msg[:role] || msg["role"], content: msg[:content] || msg["content"]}
      end)
    end

    @doc """
    Test helper for extract_provider_from_reqllm_id/1
    """
    def extract_provider_from_reqllm_id(reqllm_id) do
      provider_str =
        reqllm_id
        |> String.split(":")
        |> hd()

      # Create a safe string-to-atom mapping from ReqLLM's valid providers
      # This avoids creating arbitrary atoms from user input
      valid_providers =
        ValidProviders.list()
        |> Map.new(fn atom -> {to_string(atom), atom} end)

      Map.get(valid_providers, provider_str)
    end

    @doc """
    Test helper for convert_to_openai_response_format/1
    """
    def convert_to_openai_response_format(%{content: content} = response) do
      # Convert ReqLLM response to OpenAI format expected by ToolHelper
      %{
        choices: [
          %{
            message: %{
              content: content,
              role: "assistant",
              tool_calls: Map.get(response, :tool_calls, [])
            },
            finish_reason: Map.get(response, :finish_reason, "stop"),
            index: 0
          }
        ],
        usage: Map.get(response, :usage, %{}),
        model: "unknown"
      }
    end

    def convert_to_openai_response_format(response) when is_map(response) do
      # Handle other ReqLLM response formats
      content = response[:content] || response["content"] || ""

      %{
        choices: [
          %{
            message: %{
              content: content,
              role: "assistant",
              tool_calls: Map.get(response, :tool_calls, [])
            },
            finish_reason: Map.get(response, :finish_reason, "stop"),
            index: 0
          }
        ],
        usage: Map.get(response, :usage, %{}),
        model: "unknown"
      }
    end

    @doc """
    Test helper for build_req_llm_options_from_chat_req/2
    """
    def build_req_llm_options_from_chat_req(chat_req, model) do
      opts = []

      # Set API key via JidoKeys if available
      if model.api_key do
        provider_atom = extract_provider_from_reqllm_id(model.reqllm_id)

        if provider_atom do
          env_var_name = ReqLLM.Keys.env_var_name(provider_atom)
          JidoKeys.put(env_var_name, model.api_key)
        end
      end

      # Add other parameters from chat_req
      opts =
        if Map.get(chat_req, :temperature),
          do: [{:temperature, Map.get(chat_req, :temperature)} | opts],
          else: opts

      opts =
        if Map.get(chat_req, :max_tokens),
          do: [{:max_tokens, Map.get(chat_req, :max_tokens)} | opts],
          else: opts

      opts =
        if Map.get(chat_req, :top_p), do: [{:top_p, Map.get(chat_req, :top_p)} | opts], else: opts

      opts =
        if Map.get(chat_req, :frequency_penalty),
          do: [{:frequency_penalty, Map.get(chat_req, :frequency_penalty)} | opts],
          else: opts

      opts =
        if Map.get(chat_req, :presence_penalty),
          do: [{:presence_penalty, Map.get(chat_req, :presence_penalty)} | opts],
          else: opts

      opts =
        if Map.get(chat_req, :stop), do: [{:stop, Map.get(chat_req, :stop)} | opts], else: opts

      opts =
        if Map.get(chat_req, :tools),
          do: [{:tools, convert_tools_for_reqllm(Map.get(chat_req, :tools))} | opts],
          else: opts

      opts =
        if Map.get(chat_req, :tool_choice),
          do: [{:tool_choice, Map.get(chat_req, :tool_choice)} | opts],
          else: opts

      opts
    end

    defp convert_tools_for_reqllm(tools) when is_list(tools) do
      # For now, pass tools through as-is since ReqLLM should handle the conversion
      # This handles the case where tools are already in OpenAI format maps
      tools
    end
  end
end
