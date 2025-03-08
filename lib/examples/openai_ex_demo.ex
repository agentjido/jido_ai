defmodule OpenAIExDemo do
  alias OpenaiEx.Chat
  alias OpenaiEx.ChatMessage
  alias Jido.AI.Model
  # alias Jido.AI.Prompt

  def openai do
    {:ok, model} = Model.from({:openai, [model_id: "google/gemini-2.0-pro-exp-02-05:free"]})

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

  def openrouter do
    {:ok, model} = Model.from({:openrouter, [model_id: "anthropic/claude-3-opus-20240229"]})

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
