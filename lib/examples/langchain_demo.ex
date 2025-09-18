defmodule LangchainDemo do
  alias LangChain.ChatModels.ChatOpenAI
  alias LangChain.ChatModels.ChatAnthropic
  alias LangChain.Message
  alias LangChain.Chains.LLMChain
  alias Jido.AI.Keyring
  alias LangChain.Function
  alias Jido.Tools.Arithmetic.{Add, Subtract}

  def chat do
    # Create a chat model
    chat_model =
      ChatOpenAI.new!(%{
        api_key: Keyring.get(:openai_api_key),
        model: "gpt-4",
        temperature: 0.7
      })

    # Create messages for the conversation
    messages = [
      Message.new_system!("You are a helpful assistant."),
      Message.new_user!("Tell me about Elixir programming language.")
    ]

    # Create and run a simple chain
    {:ok, chain} =
      %{llm: chat_model, verbose: true}
      |> LLMChain.new!()
      |> LLMChain.add_messages(messages)
      |> LLMChain.run()

    IO.puts("Response: #{chain.last_message.content}")
  end

  def tool do
    add_function = Function.new!(Add.to_tool())
    subtract_function = Function.new!(Subtract.to_tool())

    messages = [
      Message.new_system!("""
        You are a helpful math assistant that can perform arithmetic operations.
        When asked about addition or subtraction, use the appropriate function to calculate the result.
      """),
      Message.new_user!("What is (527 + 313) - 248?")
    ]

    # Create chat model
    chat_model =
      ChatAnthropic.new!(%{
        api_key: Keyring.get(:anthropic_api_key),
        model: "claude-3-5-haiku-latest",
        temperature: 0.7
      })

    # Create and run chain with variables
    {:ok, chain} =
      %{llm: chat_model, verbose: true}
      |> LLMChain.new!()
      |> LLMChain.add_messages(messages)
      |> LLMChain.add_tools([add_function, subtract_function])
      |> LLMChain.run(mode: :while_needs_response)

    IO.puts("Response: #{chain.last_message.content}")
  end
end
