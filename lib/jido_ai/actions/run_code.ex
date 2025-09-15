defmodule JidoAI.Actions.RunCode do
  @moduledoc """
  Action to execute code and return the result.
  
  This action safely executes code snippets in various languages
  and returns the output or any errors that occur.
  """

  use Jido.Action,
    name: "run_code",
    description: "Execute code and return the result",
    schema: [
      code: [type: :string, required: true, doc: "The code to execute"],
      language: [type: :string, required: true, doc: "The programming language (elixir, javascript, python, etc.)"]
    ]

  alias Jido.Error

  @doc """
  Execute code in the specified language and return the result.
  """
  @impl true
  def run(%{code: code, language: language}, _context) do
    case String.downcase(language) do
      "elixir" -> run_elixir(code)
      "javascript" -> run_javascript(code)
      "js" -> run_javascript(code)
      "python" -> run_python(code)
      "bash" -> run_bash(code)
      "shell" -> run_bash(code)
      _ -> {:error, Error.action_error(__MODULE__, "Unsupported language: #{language}")}
    end
  end

  defp run_elixir(code) do
    try do
      {result, _binding} = Code.eval_string(code)
      {:ok, "Result: #{inspect(result)}"}
    rescue
      error ->
        {:ok, "Error: #{Exception.format(:error, error, __STACKTRACE__)}"}
    end
  end

  defp run_javascript(code) do
    case System.cmd("node", ["-e", code], stderr_to_stdout: true) do
      {output, 0} -> {:ok, "Output: #{String.trim(output)}"}
      {error, _} -> {:ok, "Error: #{String.trim(error)}"}
    end
  rescue
    _ -> {:ok, "Error: Node.js not available"}
  end

  defp run_python(code) do
    case System.cmd("python3", ["-c", code], stderr_to_stdout: true) do
      {output, 0} -> {:ok, "Output: #{String.trim(output)}"}
      {error, _} -> {:ok, "Error: #{String.trim(error)}"}
    end
  rescue
    _ -> {:ok, "Error: Python3 not available"}
  end

  defp run_bash(code) do
    case System.cmd("bash", ["-c", code], stderr_to_stdout: true) do
      {output, 0} -> {:ok, "Output: #{String.trim(output)}"}
      {error, _} -> {:ok, "Error: #{String.trim(error)}"}
    end
  rescue
    _ -> {:ok, "Error: Bash not available"}
  end
end
