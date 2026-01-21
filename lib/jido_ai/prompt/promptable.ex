defprotocol Jido.AI.Promptable do
  @moduledoc """
  Protocol for data structures that can be converted into prompts for LLMs.

  Implementing this protocol allows any struct to be convertible
  to a string prompt via `Jido.AI.Promptable.to_prompt/1`.

  ## Examples

      defimpl Jido.AI.Promptable, for: MyApp.User do
        def to_prompt(user) do
          "User \#{user.name} is \#{user.age} years old"
        end
      end

      user = %MyApp.User{name: "Alice", age: 30}
      Jido.AI.Promptable.to_prompt(user) #=> "User Alice is 30 years old"
  """

  @doc """
  Converts the given data structure into a prompt string suitable for an LLM.
  """
  @spec to_prompt(t) :: String.t()
  def to_prompt(data)
end
