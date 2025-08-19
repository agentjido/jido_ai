defmodule Jido.Dialogue.Demo do
  @moduledoc """
  Demonstrates a simple end-to-end flow using Jido.Dialogue.
  """

  alias Jido.Dialogue.Manager
  alias Jido.Dialogue.Conversation

  @doc """
  Runs a simple demo of creating a conversation, adding messages, and completing it.
  """
  def run do
    IO.puts("=== Jido.Dialogue Demo Start ===\n")

    # 1) Start a new conversation
    IO.puts("Starting a new conversation...")

    conversation =
      Manager.start_conversation("demo-convo-id", %{channel: "demo", user_id: "example-user"})

    # 2) Add user/human message
    IO.puts("User says: 'Hello, I'd like to order a pizza.'")

    conversation =
      Manager.add_message(
        conversation,
        :human,
        "Hello, I'd like to order a pizza.",
        %{intent: "order_request"}
      )

    # 3) Add agent message
    IO.puts("Agent replies: 'Sure! What toppings would you like?'")

    conversation =
      Manager.add_message(
        conversation,
        :agent,
        "Sure! What toppings would you like?",
        %{contextual: true}
      )

    # 4) Retrieve and display conversation history so far
    IO.puts("\nCurrent conversation history:")

    conversation
    |> Manager.get_history()
    |> Enum.each(fn turn ->
      IO.puts("[#{turn.speaker}] #{turn.content} (ID: #{turn.id})")
    end)

    # 5) Mark conversation completed
    IO.puts("\nCompleting the conversation...")
    completed = Conversation.complete(conversation)

    # 6) Print final state
    IO.puts("Conversation completed. Final state:")
    IO.inspect(completed, label: "Completed Conversation")

    IO.puts("\n=== End of Jido.Dialogue Demo ===")
    :ok
  end
end
