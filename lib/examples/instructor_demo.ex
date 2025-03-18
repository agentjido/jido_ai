defmodule Jido.Examples.InstructorDemo do
  @moduledoc """
  A demo module showcasing how to use Jido.AI with Instructor for structured prompting.
  """
  alias Jido.AI.Prompt
  alias Jido.AI.Actions.Instructor.{ChatCompletion, ChoiceResponse, BooleanResponse}
  alias Jido.AI.Model

  defmodule ResponseSchema do
    use Ecto.Schema
    use Instructor

    @llm_doc """
    A structured response from an AI assistant that includes:
    - response: The main text response
    - code_example: An optional code example
    - references: List of relevant references or links
    """
    @primary_key false
    embedded_schema do
      field(:response, :string)
      field(:code_example, :string)
      field(:references, {:array, :string})
    end
  end

  def model do
    {:ok, model} = Model.from({:anthropic, [model: "claude-3-haiku-20240307"]})
    model
  end

  def chat do
    # 1. Define a model using provider tuple format with model

    # 2. Create a sophisticated prompt with history and template substitution
    prompt =
      Prompt.new(%{
        messages: [
          %{
            role: :system,
            content:
              "You are a helpful AI assistant that provides clear, concise responses with code examples when relevant.",
            engine: :none
          },
          %{
            role: :user,
            content: "Explain the concept of pure functions in Elixir with an example.",
            engine: :none
          }
        ]
      })

    # 3. Make the chat completion call
    case Jido.Workflow.run(ChatCompletion, %{
           model: model(),
           prompt: prompt,
           response_model: ResponseSchema,
           temperature: 0.7,
           max_tokens: 1000
         }) do
      {:ok, %{result: %ResponseSchema{} = response}, _} ->
        IO.puts("\n=== Response ===")
        IO.puts(response.response)
        IO.puts("\n=== Code Example ===")
        IO.puts(response.code_example)
        IO.puts("\n=== References ===")
        Enum.each(response.references, &IO.puts/1)

      {:error, reason, _} ->
        IO.puts("\n=== Error ===")
        IO.puts(inspect(reason))

      unknown ->
        IO.puts("\n=== Unknown ===")
        IO.puts(inspect(unknown))
    end
  end

  @doc """
  Demonstrates using the ChatResponse action for simpler chat interactions
  """
  def choice do
    # Define available options for the multiple choice question
    available_options = [
      %{
        id: "with_statement",
        name: "With Statement",
        description: "Use a with statement for handling multiple operations that can fail"
      },
      %{
        id: "try_rescue",
        name: "Try/Rescue",
        description: "Use try/rescue blocks for handling exceptions"
      },
      %{
        id: "ok_error_tuples",
        name: "OK/Error Tuples",
        description: "Return tagged tuples like {:ok, result} or {:error, reason}"
      }
    ]

    # Create prompt for multiple choice question
    prompt =
      Prompt.new(%{
        messages: [
          %{
            role: :system,
            content:
              "You are a helpful AI assistant that helps users learn about Elixir programming.",
            engine: :none
          },
          %{
            role: :user,
            content:
              "What's the best way to handle errors when performing multiple operations that can fail in Elixir?",
            engine: :none
          }
        ]
      })

    # Make the choice response call
    case Jido.Workflow.run(ChoiceResponse, %{
           prompt: prompt,
           available_actions: available_options,
           model: model()
         }) do
      {:ok, %{result: %{selected_option: option, explanation: explanation}}} ->
        selected = Enum.find(available_options, &(&1.id == option))
        IO.puts("\n=== Selected Option ===")
        IO.puts("#{selected.name} (#{selected.id})")
        IO.puts("\n=== Explanation ===")
        IO.puts(explanation)

      {:error, reason} ->
        IO.puts("\n=== Error ===")
        IO.puts(inspect(reason))
        IO.puts("\nAvailable options:")

        Enum.each(available_options, fn opt ->
          IO.puts("- #{opt.id}: #{opt.name} (#{opt.description})")
        end)
    end
  end

  def boolean do
    prompt =
      Prompt.new(%{
        messages: [
          %{role: :user, content: "Is Elixir a functional programming language?", engine: :none}
        ]
      })

    case Jido.Workflow.run(BooleanResponse, %{prompt: prompt, model: model()}) do
      {:ok,
       %{
         result: response,
         explanation: explanation,
         confidence: confidence,
         is_ambiguous: is_ambiguous
       }} ->
        IO.puts("\n=== Boolean Response ===")
        IO.puts(response)
        IO.puts("\n=== Explanation ===")
        IO.puts(explanation)
        IO.puts("\n=== Confidence ===")
        IO.puts(confidence)
        IO.puts("\n=== Is Ambiguous ===")
        IO.puts(is_ambiguous)
    end
  end
end
