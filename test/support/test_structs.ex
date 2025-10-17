defmodule JidoTest.AI.Examples.TestStructs do
  @moduledoc """
  Example structs demonstrating how to implement the Promptable protocol.
  These structs are used in tests and serve as reference implementations.
  """

  defmodule User do
    @moduledoc "Example struct for user data with Promptable implementation"
    defstruct [:name, :age, :email]
  end

  defmodule Task do
    @moduledoc "Example struct for task data with Promptable implementation"
    defstruct [:title, :status, :due_date]
  end

  defmodule Profile do
    @moduledoc "Example struct for profile data with Promptable implementation"
    defstruct [:bio, :skills]
  end
end

# Example implementation for User
defimpl Jido.AI.Promptable, for: JidoTest.AI.Examples.TestStructs.User do
  def to_prompt(%{name: name, age: age}) when is_binary(name) and is_integer(age) do
    "User #{name} is #{age} years old"
  end

  def to_prompt(%{name: name}) when is_binary(name) do
    "User #{name} (age unknown)"
  end

  def to_prompt(_) do
    "Unknown user"
  end
end

# Example implementation for Task
defimpl Jido.AI.Promptable, for: JidoTest.AI.Examples.TestStructs.Task do
  def to_prompt(%{title: title, status: status, due_date: due_date}) do
    "Task '#{title}' is #{status}, due on #{due_date}"
  end
end

# Example implementation for Profile with list handling
defimpl Jido.AI.Promptable, for: JidoTest.AI.Examples.TestStructs.Profile do
  def to_prompt(%{bio: bio, skills: skills}) when is_list(skills) do
    skills_text = Enum.join(skills, ", ")
    "Profile: #{bio}\nSkills: #{skills_text}"
  end
end
