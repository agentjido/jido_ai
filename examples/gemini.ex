defmodule JidoAi.Examples.Gemini do
  @moduledoc """
  Example demonstrating how to use Google's Gemini models with Jido AI.

  This example shows how to use the Model.from/1 function to create a Gemini model
  and use it with the OpenaiEx action to generate text.

  ## Usage

  ```
  $ mix run examples/gemini.ex
  ```

  Make sure to set your Google API key as an environment variable:

  ```
  $ GOOGLE_API_KEY=your_api_key mix run examples/gemini.ex
  ```

  Or add it to your .env file.
  """

  alias Jido.AI.Model
  alias Jido.AI.Actions.OpenaiEx

  def run do
    # Create a Gemini model
    {:ok, model} =
      Model.from(
        {:google,
         [
           model: "gemini-2.0-flash",
           api_key: Jido.AI.Keyring.get(:google_api_key)
         ]}
      )

    # Call the OpenaiEx action with the model
    {:ok, result} =
      OpenaiEx.run(
        %{
          model: model,
          messages: [
            %{role: :user, content: "Explain the concept of functional programming in Elixir"}
          ],
          temperature: 0.7,
          max_tokens: 500
        },
        %{}
      )

    # Print the result
    IO.puts("\n\nGemini Response:\n")
    IO.puts(result.content)
    IO.puts("\n")
  end
end
