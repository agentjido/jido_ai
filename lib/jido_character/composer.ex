defprotocol Jido.Character.Composer do
  @moduledoc """
  Protocol for composing character data into string format for LLM prompts.
  Each schema module implements its own composition logic while maintaining
  a consistent interface.
  """

  @doc """
  Composes the module's data into a string format suitable for LLM prompts.
  Options can include formatting preferences or composition constraints.

  Returns `{:ok, string}` or `{:error, reason}`
  """
  @spec compose(t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def compose(data, opts \\ [])
end
