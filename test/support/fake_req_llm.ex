defmodule Jido.AI.TestSupport.FakeReqLLM do
  @moduledoc false

  def setup_stubs(_context) do
    Mimic.stub(ReqLLM.Generation, :generate_text, &generate_text/3)
    Mimic.stub(ReqLLM.Generation, :generate_object, &generate_object/4)
    Mimic.stub(ReqLLM.Generation, :stream_text, &stream_generation_text/3)
    Mimic.stub(ReqLLM, :stream_text, &stream_text/3)
    Mimic.stub(ReqLLM.StreamResponse, :usage, &stream_usage/1)
    Mimic.stub(ReqLLM.StreamResponse, :process_stream, &process_stream/2)
    :ok
  end

  def generate_text(model, messages, opts) do
    tools = Keyword.get(opts, :tools, [])
    prompt = extract_latest_user_prompt(messages)
    has_tool_result? = Enum.any?(messages, &tool_message?/1)

    result =
      cond do
        Regex.match?(~r/\AGoal:\s*(?:\n|$)/, prompt) ->
          {:error, :invalid_prompt}

        Regex.match?(~r/\AGoal to decompose:\s*(?:\n|$)/, prompt) ->
          {:error, :invalid_prompt}

        tools != [] and String.contains?(prompt, "loop tool") ->
          {:ok, tool_call_response(model)}

        tools != [] and has_tool_result? ->
          max_tokens = Keyword.get(opts, :max_tokens)
          temperature = Keyword.get(opts, :temperature)

          {:ok,
           final_answer_response(
             model,
             "Tool execution complete: 8 (max_tokens=#{max_tokens}, temperature=#{temperature})"
           )}

        tools != [] and String.contains?(prompt, "Calculate") ->
          {:ok, tool_call_response(model)}

        String.starts_with?(prompt, "Goal:") ->
          {:ok, plan_response(model)}

        String.starts_with?(prompt, "Goal to decompose:") ->
          {:ok, decompose_response(model)}

        String.starts_with?(prompt, "Tasks to prioritize:") ->
          {:ok, prioritize_response(model)}

        true ->
          {:ok, final_answer_response(model, "Stubbed response for: #{prompt}")}
      end

    result
  end

  def stream_text(model, messages, _opts) do
    prompt = extract_latest_user_prompt(messages)
    chunks = ["Stubbed ", "stream ", "for ", prompt]
    content = Enum.join(chunks, "")

    {:ok,
     %{
       chunks: chunks,
       final: final_answer_response(model, content)
     }}
  end

  def process_stream(%{chunks: chunks, final: final}, opts) when is_list(chunks) do
    on_result = Keyword.get(opts, :on_result, fn _chunk -> :ok end)

    Enum.each(chunks, fn chunk ->
      _ = on_result.(chunk)
    end)

    {:ok, final}
  end

  def process_stream(%{stream: stream} = stream_response, opts) do
    callbacks = extract_callbacks(opts)

    chunks =
      Enum.map(stream, fn chunk ->
        invoke_chunk_callback(chunk, callbacks)
        chunk
      end)

    {:ok, build_stream_response(stream_response, chunks)}
  end

  def process_stream(_other, _opts), do: {:error, :invalid_stream_response}

  def stream_generation_text(model, messages, _opts) do
    prompt = extract_latest_user_prompt(messages)

    {:ok,
     %{
       stream: [ReqLLM.StreamChunk.text("Stubbed stream for: #{prompt}")],
       model: model
     }}
  end

  def stream_usage(_stream_response) do
    %{input_tokens: 8, output_tokens: 13, total_tokens: 21}
  end

  def generate_object(model, _messages, _schema, _opts) do
    {:ok,
     %{
       object: %{
         name: "stubbed",
         model: model
       },
       usage: %{input_tokens: 9, output_tokens: 11, total_tokens: 20},
       model: model
     }}
  end

  defp extract_latest_user_prompt(messages) when is_list(messages) do
    messages
    |> Enum.reverse()
    |> Enum.find_value("", fn
      %{role: role, content: content} when role in [:user, "user"] ->
        normalize_content(content)

      _ ->
        nil
    end)
  end

  defp extract_latest_user_prompt(_), do: ""

  defp normalize_content(content) when is_binary(content), do: content
  defp normalize_content(content) when is_list(content), do: Jido.AI.Turn.extract_from_content(content)
  defp normalize_content(_), do: ""

  defp tool_message?(%{role: role}) when role in [:tool, "tool"], do: true
  defp tool_message?(_), do: false

  defp extract_callbacks(opts) do
    %{
      on_result: Keyword.get(opts, :on_result),
      on_thinking: Keyword.get(opts, :on_thinking),
      on_tool_call: Keyword.get(opts, :on_tool_call)
    }
  end

  defp invoke_chunk_callback(%ReqLLM.StreamChunk{type: :content, text: text}, %{on_result: callback})
       when is_function(callback, 1) and is_binary(text),
       do: callback.(text)

  defp invoke_chunk_callback(%ReqLLM.StreamChunk{type: :thinking, text: text}, %{on_thinking: callback})
       when is_function(callback, 1) and is_binary(text),
       do: callback.(text)

  defp invoke_chunk_callback(%ReqLLM.StreamChunk{type: :tool_call} = chunk, %{on_tool_call: callback})
       when is_function(callback, 1),
       do: callback.(chunk)

  defp invoke_chunk_callback(_chunk, _callbacks), do: :ok

  defp build_stream_response(stream_response, chunks) do
    summary = ReqLLM.Response.Stream.summarize(chunks)
    reasoning_details = Map.get(stream_response, :reasoning_details)

    %{
      message: %{
        content: build_stream_content(summary.text, summary.thinking),
        tool_calls: summary.tool_calls,
        reasoning_details: reasoning_details
      },
      finish_reason: stream_finish_reason(summary.tool_calls, Map.get(stream_response, :finish_reason)),
      usage: Map.get(stream_response, :usage, summary.usage),
      model: Map.get(stream_response, :model)
    }
  end

  defp build_stream_content(text, nil), do: text
  defp build_stream_content(text, ""), do: text

  defp build_stream_content(text, thinking) do
    [
      %{type: :thinking, thinking: thinking},
      %{type: :text, text: text || ""}
    ]
  end

  defp stream_finish_reason(tool_calls, _finish_reason) when is_list(tool_calls) and tool_calls != [], do: :tool_calls
  defp stream_finish_reason(_tool_calls, finish_reason) when not is_nil(finish_reason), do: finish_reason
  defp stream_finish_reason(_tool_calls, _finish_reason), do: :stop

  defp final_answer_response(model, content) do
    %{
      message: %{content: content, tool_calls: nil},
      finish_reason: :stop,
      usage: %{input_tokens: 12, output_tokens: 24},
      model: model
    }
  end

  defp tool_call_response(model) do
    %{
      message: %{
        content: nil,
        tool_calls: [
          %{
            id: "tc_1",
            name: "calculator",
            arguments: %{"operation" => "add", "a" => 5, "b" => 3}
          }
        ]
      },
      finish_reason: :tool_calls,
      usage: %{input_tokens: 10, output_tokens: 8},
      model: model
    }
  end

  defp plan_response(model) do
    text =
      """
      ## Plan Overview
      Build and ship incrementally.

      ## Steps
      1. **Define Scope**
         - Description: Capture MVP requirements.
      2. **Implement Core Features**
         - Description: Build and test major flows.
      3. **Deploy**
         - Description: Ship and monitor.
      """
      |> String.replace(~r/^\s+/m, "")
      |> String.trim()

    final_answer_response(model, text)
  end

  defp decompose_response(model) do
    text =
      """
      ## Level 1: Main Goal Areas
      1. Product
      - 1.1. Define requirements
      - 1.2. Build MVP
      2. Delivery
      - 2.1. Set milestones
      - 2.2. Release plan
      """
      |> String.replace(~r/^\s+/m, "")
      |> String.trim()

    final_answer_response(model, text)
  end

  defp prioritize_response(model) do
    text =
      """
      ## Priority Analysis
      1. **Fix critical bug** - Score: 9
      2. **Add new feature** - Score: (7)
      3. **Update documentation** - Score: [5-7]

      ## Recommended Execution Order
      1. **Fix critical bug**
      2. **Add new feature**
      3. **Update documentation**
      """
      |> String.replace(~r/^\s+/m, "")
      |> String.trim()

    final_answer_response(model, text)
  end
end
