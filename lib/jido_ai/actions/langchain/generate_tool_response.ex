defmodule Jido.AI.Actions.Langchain.GenerateToolResponse do
  require Logger

  use Jido.Action,
    name: "generate_tool_response",
    description: "Generate a response using LangChain to coordinate with arithmetic actions",
    schema: [
      prompt: [type: :string, required: true, doc: "The prompt to use for the response"],
      message: [type: :string, required: true, doc: "The user's message"],
      personality: [type: :string, required: true, doc: "The personality of the assistant"]
    ]

  alias LangChain.Chains.LLMChain
  alias LangChain.ChatModels.ChatAnthropic
  alias LangChain.Message
  alias LangChain.Function
  alias Jido.Actions.Arithmetic.{Add, Subtract}

  def test do
    prompt = "What is (25 + 17) - 13?"
    message = "What is (25 + 17) - 13?"

    personality =
      "You are a helpful math assistant that can perform arithmetic operations. Please show your work step by step."

    run(%{prompt: prompt, message: message, personality: personality}, %{})
  end

  def run(params, _context) do
    Logger.debug("Starting tool response generation, params: #{inspect(params)}")

    add_function = Function.new!(Add.to_tool())
    subtract_function = Function.new!(Subtract.to_tool())

    # Create messages for the LLM
    messages = [
      Message.new_system!("""
        You are a helpful math assistant that can perform arithmetic operations.
        When asked about addition or subtraction, use the appropriate function to calculate the result.
        #{params.personality}
      """),
      Message.new_user!(params.message)
    ]

    # Setup the LLM chain
    chat_model =
      ChatAnthropic.new!(%{
        model: "claude-3-5-haiku-latest",
        temperature: 0.7
      })

    task =
      Task.Supervisor.async_nolink(JidoWorkbench.TaskSupervisor, fn ->
        {:ok, chain} =
          %{llm: chat_model, verbose: true}
          |> LLMChain.new!()
          |> LLMChain.add_messages(messages)
          |> LLMChain.add_tools([add_function, subtract_function])
          |> LLMChain.run(mode: :while_needs_response)

        chain.last_message.content
      end)

    try do
      case Task.yield(task, 29_000) || Task.shutdown(task, :brutal_kill) do
        {:ok, response} ->
          {:ok, %{result: response}}

        nil ->
          Logger.warning("Tool response generation timed out")
          {:error, :timeout}
      end
    catch
      kind, reason ->
        Logger.warning(
          "Unexpected error in tool response generation, kind: #{kind}, error: #{inspect(reason)}, stacktrace: #{inspect(__STACKTRACE__)}"
        )

        {:error, reason}
    end
  end
end
