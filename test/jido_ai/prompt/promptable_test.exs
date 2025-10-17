defmodule JidoTest.AI.Prompt.PromptableTest do
  use ExUnit.Case, async: true
  doctest Jido.AI.Promptable
  @moduletag :capture_log
  alias Jido.AI.TestStructs.{User, Task, Profile}

  # Implement protocol for User
  defimpl Jido.AI.Promptable, for: User do
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

  # Implement protocol for Task
  defimpl Jido.AI.Promptable, for: Task do
    def to_prompt(%{title: title, status: status, due_date: due_date}) do
      "Task '#{title}' is #{status}, due on #{due_date}"
    end
  end

  # Implement protocol for Profile with list handling
  defimpl Jido.AI.Promptable, for: Profile do
    def to_prompt(%{bio: bio, skills: skills}) when is_list(skills) do
      skills_text = Enum.join(skills, ", ")
      "Profile: #{bio}\nSkills: #{skills_text}"
    end
  end

  describe "User implementation" do
    test "formats user with full information" do
      user = %JidoTest.AI.Examples.TestStructs.User{
        name: "Alice",
        age: 30,
        email: "alice@example.com"
      }

      assert Jido.AI.Promptable.to_prompt(user) == "User Alice is 30 years old"
    end

    test "formats user with only name" do
      user = %JidoTest.AI.Examples.TestStructs.User{name: "Bob"}
      assert Jido.AI.Promptable.to_prompt(user) == "User Bob (age unknown)"
    end

    test "handles empty user" do
      user = %JidoTest.AI.Examples.TestStructs.User{}
      assert Jido.AI.Promptable.to_prompt(user) == "Unknown user"
    end

    test "handles nil values" do
      user = %JidoTest.AI.Examples.TestStructs.User{name: nil, age: nil}
      assert Jido.AI.Promptable.to_prompt(user) == "Unknown user"
    end
  end

  describe "Task implementation" do
    test "formats task with all fields" do
      task = %JidoTest.AI.Examples.TestStructs.Task{
        title: "Write tests",
        status: "in progress",
        due_date: "2024-03-20"
      }

      assert Jido.AI.Promptable.to_prompt(task) ==
               "Task 'Write tests' is in progress, due on 2024-03-20"
    end

    test "handles task with different status" do
      task = %JidoTest.AI.Examples.TestStructs.Task{
        title: "Review code",
        status: "completed",
        due_date: "2024-03-19"
      }

      assert Jido.AI.Promptable.to_prompt(task) ==
               "Task 'Review code' is completed, due on 2024-03-19"
    end
  end

  describe "Profile implementation" do
    test "formats profile with skills list" do
      profile = %JidoTest.AI.Examples.TestStructs.Profile{
        bio: "Software developer",
        skills: ["Elixir", "Phoenix", "PostgreSQL"]
      }

      assert Jido.AI.Promptable.to_prompt(profile) ==
               "Profile: Software developer\nSkills: Elixir, Phoenix, PostgreSQL"
    end

    test "handles empty skills list" do
      profile = %JidoTest.AI.Examples.TestStructs.Profile{
        bio: "New developer",
        skills: []
      }

      assert Jido.AI.Promptable.to_prompt(profile) ==
               "Profile: New developer\nSkills: "
    end
  end

  describe "Error handling" do
    test "raises Protocol.UndefinedError for unimplemented types" do
      assert_raise Protocol.UndefinedError, fn ->
        Jido.AI.Promptable.to_prompt(%{some: "map"})
      end
    end
  end
end
