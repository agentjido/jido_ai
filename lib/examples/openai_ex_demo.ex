defmodule OpenAIExDemo do
  alias OpenaiEx.Chat
  alias OpenaiEx.ChatMessage
  alias Jido.AI.Model
  # alias Jido.AI.Prompt

  def openai do
    {:ok, model} = Model.from({:openai, [model: "google/gemini-2.0-pro-exp-02-05:free"]})

    # prompt =
    #   Prompt.new(%{
    #     messages: [
    #       %{role: :user, content: "What is the capital of France?", engine: :none}
    #     ]
    #   })

    chat_req =
      Chat.Completions.new(
        model: "gpt-4o-mini",
        messages: [
          ChatMessage.user(
            "Give me some background on the elixir language. Why was it created? What is it used for? What distinguishes it from other languages? How popular is it?"
          )
        ]
      )

    # Call OpenAI Directly
    {:ok, response} =
      OpenaiEx.new(model.api_key)
      # |> OpenaiEx.with_base_url(Jido.AI.Provider.OpenRouter.base_url())
      # |> OpenaiEx.with_additional_headers(Jido.AI.Provider.OpenRouter.request_headers([]))
      |> OpenaiEx.Chat.Completions.create(chat_req)

    IO.inspect(response, label: "OpenAI Ex response")
  end

  def openai_stream do
    {:ok, model} = Model.from({:openai, [model: "google/gemini-2.0-pro-exp-02-05:free"]})

    chat_req =
      Chat.Completions.new(
        model: "gpt-4o-mini",
        messages: [
          ChatMessage.user(
            "Give me some background on the elixir language. Why was it created? What is it used for? What distinguishes it from other languages? How popular is it?"
          )
        ],
        # Optional: configure stream options if needed
        stream_options: %{include_usage: true}
      )

    # Initialize the OpenAI client
    client =
      OpenaiEx.new(model.api_key)
      # Set a stream timeout of 30 seconds (optional)
      |> OpenaiEx.with_stream_timeout(30_000)

    # Call OpenAI with streaming enabled
    IO.puts("Stream started. Processing response...")
    {:ok, chat_stream} = client |> Chat.Completions.create(chat_req, stream: true)

    # Process the stream chunks and output content as it arrives
    chat_stream.body_stream
    |> Stream.flat_map(& &1)
    |> Enum.each(fn chunk ->
      # Extract delta content from each chunk if available
      content = get_content_from_chunk(chunk)
      if content && content != "", do: IO.write(content)
    end)

    IO.puts("\n\nStream completed")
  end

  def openai_stream_with_error_handling do
    {:ok, model} = Model.from({:openai, [model: "google/gemini-2.0-pro-exp-02-05:free"]})

    chat_req =
      Chat.Completions.new(
        model: "gpt-4o-mini",
        messages: [
          ChatMessage.user(
            "Give me some background on the elixir language. Why was it created? What is it used for? What distinguishes it from other languages? How popular is it?"
          )
        ]
      )

    # Initialize the OpenAI client with timeout
    client =
      OpenaiEx.new(model.api_key)
      |> OpenaiEx.with_stream_timeout(30_000)

    # Use a try-rescue block to handle potential streaming errors
    try do
      # Use create! which raises exceptions on error
      chat_stream = client |> Chat.Completions.create!(chat_req, stream: true)

      IO.puts("Stream started with error handling. Processing response...")

      # Process the stream with error handling
      try do
        chat_stream.body_stream
        |> Stream.flat_map(& &1)
        |> Enum.each(fn chunk ->
          content = get_content_from_chunk(chunk)
          if content && content != "", do: IO.write(content)
        end)

        IO.puts("\n\nStream completed successfully")
        {:ok, :completed}
      rescue
        e in OpenaiEx.Error ->
          case e do
            %{kind: :sse_cancellation} ->
              IO.puts("\nStream was canceled")
              {:error, :canceled, e.message}

            %{kind: :sse_timeout_error} ->
              IO.puts("\nTimeout on SSE stream")
              {:error, :timeout, e.message}

            _ ->
              IO.puts("\nAPI error: #{e.message}")
              {:error, :api_error, e.message}
          end

        e ->
          IO.puts("\nUnexpected error: #{Exception.message(e)}")
          {:error, :unexpected, Exception.message(e)}
      end
    rescue
      # Handle errors during initial API call
      e in OpenaiEx.Error ->
        IO.puts("API error: #{e.message}")
        {:error, :api_error, e.message}

      e ->
        IO.puts("Unexpected error: #{Exception.message(e)}")
        {:error, :unexpected, Exception.message(e)}
    end
  end

  def openai_stream_with_cancellation do
    {:ok, model} = Model.from({:openai, [model: "google/gemini-2.0-pro-exp-02-05:free"]})

    chat_req =
      Chat.Completions.new(
        model: "gpt-4o-mini",
        messages: [
          ChatMessage.user(
            "Write me a very long explanation about functional programming and the BEAM virtual machine."
          )
        ]
      )

    # Initialize the OpenAI client with timeout
    client =
      OpenaiEx.new(model.api_key)
      |> OpenaiEx.with_stream_timeout(30_000)

    try do
      # Create the stream
      {:ok, chat_stream} = client |> Chat.Completions.create(chat_req, stream: true)

      IO.puts("Stream started. Will cancel after receiving a few chunks...")
      IO.puts("Stream task PID: #{inspect(chat_stream.task_pid)}")

      # Process only a few chunks and then cancel
      try do
        chunk_count =
          chat_stream.body_stream
          |> Stream.flat_map(& &1)
          |> Stream.with_index()
          |> Enum.reduce_while(0, fn {chunk, index}, acc ->
            content = get_content_from_chunk(chunk)
            if content && content != "", do: IO.write(content)

            # After receiving some chunks, cancel the stream
            if index >= 5 do
              IO.puts("\n\nCancelling stream after #{index + 1} chunks...")
              # Cancel the ongoing streaming request
              OpenaiEx.HttpSse.cancel_request(chat_stream.task_pid)
              {:halt, acc + 1}
            else
              {:cont, acc + 1}
            end
          end)

        IO.puts("\nStream processing completed after #{chunk_count} chunks")
        {:ok, :completed}
      rescue
        e in OpenaiEx.Error ->
          case e do
            %{kind: :sse_cancellation} ->
              IO.puts("\nStream was successfully canceled")
              {:ok, :canceled}

            _ ->
              IO.puts("\nAPI error during streaming: #{e.message}")
              {:error, :api_error, e.message}
          end

        e ->
          IO.puts("\nUnexpected error during streaming: #{Exception.message(e)}")
          {:error, :unexpected, Exception.message(e)}
      end
    rescue
      e ->
        IO.puts("Error initializing stream: #{Exception.message(e)}")
        {:error, :initialization_error, Exception.message(e)}
    end
  end

  # Helper function to extract content from stream chunks - fixed to handle the actual structure
  defp get_content_from_chunk(chunk) do
    case chunk do
      %{data: %{"choices" => [%{"delta" => %{"content" => content}} | _]}} -> content
      %{data: %{"choices" => [%{"delta" => delta} | _]}} -> Map.get(delta, "content", "")
      %{"choices" => [%{"delta" => %{"content" => content}} | _]} -> content
      %{"choices" => [%{"delta" => delta} | _]} -> Map.get(delta, "content", "")
      _ -> nil
    end
  end

  def openrouter do
    {:ok, model} = Model.from({:openrouter, [model: "anthropic/claude-3-opus-20240229"]})

    tool_spec =
      Jason.decode!("""
        {"type": "function",
         "function": {
            "name": "get_current_weather",
            "description": "Get the current weather in a given location",
            "parameters": {
              "type": "object",
              "properties": {
                "location": {
                  "type": "string",
                  "description": "The city and state, e.g. San Francisco, CA"
                },
                "unit": {
                  "type": "string",
                  "enum": ["celsius", "fahrenheit"]
                }
              },
              "required": ["location"]
            }
          }
        }
      """)

    # prompt =
    #   Prompt.new(%{
    #     messages: [
    #       %{role: :user, content: "What is the capital of France?", engine: :none}
    #     ]
    #   })

    chat_req =
      Chat.Completions.new(
        model: "anthropic/claude-3-haiku",
        messages: [
          ChatMessage.user(
            "Give me some background on the elixir language. Why was it created? What is it used for? What distinguishes it from other languages? How popular is it?"
          )
        ],
        tools: [tool_spec]
      )

    # OpenAI API compatible endpoint
    {:ok, response} =
      OpenaiEx.new(model.api_key)
      |> OpenaiEx.with_base_url(Jido.AI.Provider.OpenRouter.base_url())
      # |> OpenaiEx.with_additional_headers(Jido.AI.Provider.OpenRouter.request_headers([]))
      |> OpenaiEx.Chat.Completions.create(chat_req)

    IO.inspect(response, label: "OpenAI Ex response")
  end

  def tool do
    # tool_spec =
    #   Jason.decode!("""
    #     {"type": "function",
    #      "function": {
    #         "name": "get_current_weather",
    #         "description": "Get the current weather in a given location",
    #         "parameters": {
    #           "type": "object",
    #           "properties": {
    #             "location": {
    #               "type": "string",
    #               "description": "The city and state, e.g. San Francisco, CA"
    #             },
    #             "unit": {
    #               "type": "string",
    #               "enum": ["celsius", "fahrenheit"]
    #             }
    #           },
    #           "required": ["location"]
    #         }
    #       }
    #     }
    #   """)

    tool = Jido.Actions.Arithmetic.Add.to_tool()
    # Tool: %{
    #   function: #Function<3.116548139/2 in Jido.Action.Tool.to_tool/1>,
    #   name: "add",
    #   description: "Adds two numbers",
    #   parameters_schema: %{
    #     type: "object",
    #     required: ["value", "amount"],
    #     properties: %{
    #       "amount" => %{type: "string", description: "The second number to add"},
    #       "value" => %{type: "string", description: "The first number to add"}
    #     }
    #   }
    # }
    IO.inspect(tool, label: "Tool")
  end
end
