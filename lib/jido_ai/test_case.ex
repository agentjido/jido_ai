defmodule Jido.AI.TestCase do
  @moduledoc """
  ExUnit case template for public Jido.AI test helpers.

      defmodule MyApp.AgentTest do
        use Jido.AI.TestCase, async: true

        test "agent answers deterministically" do
          expect_react do
            user "hello"
            answer "hi"
          end

          result = Jido.AI.Reasoning.ReAct.run("hello", %{tools: []})
          assert_final_answer(result, "hi")
        end
      end
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Jido.AI.Test
    end
  end

  setup _tags do
    Jido.AI.Test.reset_react_scripts()

    on_exit(fn ->
      Jido.AI.Test.reset_react_scripts()
    end)

    :ok
  end
end
