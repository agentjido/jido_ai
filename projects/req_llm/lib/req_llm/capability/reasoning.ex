defmodule ReqLLM.Capability.Reasoning do
  @moduledoc """
  Reasoning capability verification for AI models.

  Verifies that a model can perform reasoning tasks and returns reasoning
  tokens in the response when requested.
  """

  @behaviour ReqLLM.Capability.Adapter

  @impl true
  def id, do: :reasoning

  @impl true
  def advertised?(model) do
    # Check if the model metadata indicates reasoning support
    get_in(model.capabilities, [:reasoning?]) == true
  end

  @impl true
  def verify(model, opts) do
    model_spec = "#{model.provider}:#{model.model}"
    timeout = Keyword.get(opts, :timeout, 30_000)

    # Use provider_options to pass timeout to the HTTP client
    # Include reasoning: true to request reasoning tokens
    req_llm_opts = [
      reasoning: true,
      provider_options: %{
        receive_timeout: timeout,
        timeout: timeout
      }
    ]

    # Use a prompt that requires some reasoning
    reasoning_prompt = """
    I have a 3-gallon jug and a 5-gallon jug. I want to measure exactly 4 gallons of water.
    How can I do this? Please think through this step by step.
    """

    case ReqLLM.generate_text(model_spec, reasoning_prompt, req_llm_opts) do
      {:ok, %Req.Response{body: content, private: private}} when is_binary(content) ->
        # Handle ReqLLM processed response (text body with usage info in private)
        content_trimmed = String.trim(content)

        # Check for reasoning tokens in the preserved usage information
        reasoning_tokens = get_in(private, [:req_llm, :usage, :tokens, :reasoning]) || 0

        cond do
          content_trimmed == "" ->
            {:error, "Empty content response"}

          # Models with reasoning tokens (like o1 models)
          reasoning_tokens > 0 ->
            # Extract reasoning snippet from content (o1 models embed reasoning in content)
            reasoning_snippet = extract_reasoning_snippet(content)

            {:ok,
             %{
               model_id: model_spec,
               content_length: String.length(content),
               reasoning_length: reasoning_tokens,
               content_preview: String.slice(content, 0, 100),
               reasoning_preview: reasoning_snippet,
               has_reasoning_tokens: true
             }}

          true ->
            {:ok,
             %{
               model_id: model_spec,
               content_length: String.length(content),
               reasoning_length: 0,
               content_preview: String.slice(content, 0, 100),
               reasoning_preview: nil,
               has_reasoning_tokens: false,
               warning: "No reasoning tokens detected (reasoning_tokens: #{reasoning_tokens})"
             }}
        end

      {:ok, %Req.Response{body: response}} when is_binary(response) ->
        # Fallback for models that return plain text instead of structured response
        trimmed = String.trim(response)

        if trimmed != "" do
          {:ok,
           %{
             model_id: model_spec,
             content_length: String.length(response),
             reasoning_length: 0,
             content_preview: String.slice(response, 0, 100),
             reasoning_preview: nil,
             has_reasoning_tokens: false,
             warning:
               "Model returned plain text instead of structured response with reasoning tokens"
           }}
        else
          {:error, "Empty response"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private helper to extract reasoning snippet from o1 model content
  defp extract_reasoning_snippet(content) do
    # O1 models often structure their reasoning in the beginning or with clear markers
    # Look for common reasoning patterns and extract the first meaningful reasoning snippet

    cond do
      # Look for step-by-step reasoning (common pattern)
      reasoning_part = extract_steps_section(content) ->
        String.slice(reasoning_part, 0, 100)

      # Look for explanation sections
      reasoning_part = extract_explanation_section(content) ->
        String.slice(reasoning_part, 0, 100)

      # Fallback: take first portion of content (often contains reasoning)
      true ->
        content
        |> String.slice(0, 150)
        |> String.replace(~r/\n+/, " ")
        |> String.trim()
    end
  end

  # Extract step-by-step reasoning sections
  defp extract_steps_section(content) do
    cond do
      # Match numbered steps like "1.", "2.", etc.
      match =
          Regex.run(~r/(?:step|Step)\s*[:\-]?\s*\n?(.{50,200})/s, content,
            capture: :all_but_first
          ) ->
        List.first(match)

      # Match bullet points or dashes
      match = Regex.run(~r/(?:\*|-|\•)\s*(.{50,200})/s, content, capture: :all_but_first) ->
        List.first(match)

      # Match numbered lists
      match = Regex.run(~r/\d+\.\s*(.{50,200})/s, content, capture: :all_but_first) ->
        List.first(match)

      true ->
        nil
    end
  end

  # Extract explanation or reasoning sections
  defp extract_explanation_section(content) do
    cond do
      # Match explicit reasoning sections
      match =
          Regex.run(
            ~r/(?:reasoning|explanation|thinking|approach|solution)[:\-]?\s*\n?(.{50,200})/is,
            content,
            capture: :all_but_first
          ) ->
        List.first(match)

      # Match "Here's how" or "Here's why" patterns
      match =
          Regex.run(~r/(?:here'?s (?:how|why|the))[:\-]?\s*(.{50,200})/is, content,
            capture: :all_but_first
          ) ->
        List.first(match)

      # Match "First," or "To start," patterns
      match =
          Regex.run(~r/(?:first|to start|initially)[,:\-]\s*(.{50,200})/is, content,
            capture: :all_but_first
          ) ->
        List.first(match)

      true ->
        nil
    end
  end
end
