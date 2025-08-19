defmodule Sparq.Integration.HelloWorldEvaluatorTest do
  use ExUnit.Case, async: true
  alias Sparq.{Parser, Core}

  @hello_world_script """
  character Greeter do
    // This is a friendly character
    /* They like to say hello */
  end

  scene HelloWorldScene do
    beat :start do
      say Greeter, "Hello, World!"
    end
  end
  """

  describe "hello world evaluation" do
    test "evaluates character and scene definitions" do
      {:ok, tokens} = Parser.parse(@hello_world_script)
      {:ok, _result, context} = Core.execute({:script, [], tokens})

      # Verify character was defined
      assert get_in(context.modules, [:Greeter]) == %{
               type: :module,
               name: :Greeter,
               functions: %{},
               state: %{}
             }

      # Verify scene was defined
      assert get_in(context.modules, [:HelloWorldScene]) == %{
               type: :module,
               name: :HelloWorldScene,
               functions: %{},
               state: %{
                 beats: %{
                   start: [{:say, :Greeter, "Hello, World!"}]
                 }
               }
             }

      # TODO: Verify say command was executed
      # This will require implementing the JITO handler
    end
  end
end
