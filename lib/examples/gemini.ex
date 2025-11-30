defmodule JidoAi.Examples.Gemini do
  @moduledoc """
  Example demonstrating how to use Google's Gemini models with Jido AI.

  This example shows how to use ReqLLM directly to generate text with Gemini.

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

  def run do
    # Call ReqLLM directly with the Gemini model
    messages = [
      %{role: :user, content: "Explain the concept of functional programming in Elixir"}
    ]

    case ReqLLM.generate_text("google:gemini-2.0-flash", messages, temperature: 0.7, max_tokens: 500) do
      {:ok, result} ->
        # Print the result
        IO.puts("\n\nGemini Response:\n")
        IO.puts(result.content)
        IO.puts("\n")

      {:error, error} ->
        IO.puts("\n\nError: #{inspect(error)}\n")
    end
  end
end
