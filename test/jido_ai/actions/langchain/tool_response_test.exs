defmodule JidoTest.AI.Actions.Langchain.ToolResponseTest do
  use ExUnit.Case, async: false
  use Mimic

  # Add module tag to skip when running in integration mode
  @moduletag :unit
  @moduletag :capture_log

  alias Jido.AI.Actions.Langchain.ToolResponse
  alias Jido.AI.Actions.Langchain, as: LangchainAction
  alias Jido.AI.Prompt
  alias Jido.Actions.Arithmetic.{Add, Subtract}

  setup :set_mimic_global

  describe "schema" do
    test "all required fields are present" do
      schema = ToolResponse.schema()

      assert Keyword.get(schema[:prompt], :required)

      assert Keyword.get(schema[:prompt], :type) ==
               {:custom, Jido.AI.Prompt, :validate_prompt_opts, []}
    end

    test "default values are set correctly" do
      schema = ToolResponse.schema()

      assert Keyword.get(schema[:model], :default) ==
               {:anthropic, [model: "claude-3-5-haiku-latest"]}

      assert Keyword.get(schema[:temperature], :default) == 0.7
      assert Keyword.get(schema[:timeout], :default) == 30_000
    end
  end

  describe "run/2" do
    test "successfully processes a request with tools" do
      # Create test data
      prompt =
        Prompt.new(%{
          messages: [
            %{role: :system, content: "You are a helpful assistant."},
            %{role: :user, content: "Calculate 2+2 and then subtract 1"}
          ]
        })

      tools = [Add, Subtract]

      # Mock BaseCompletion.run
      expect(LangchainAction, :run, fn params, _context ->
        assert params.tools == tools
        assert params.prompt == prompt
        assert params.temperature == 0.7

        {:ok,
         %{
           content: "The result is 3",
           tool_results: [
             %{name: "add", arguments: %{"a" => 2, "b" => 2}, result: 4},
             %{name: "subtract", arguments: %{"a" => 4, "b" => 1}, result: 3}
           ]
         }}
      end)

      # Execute the action
      result =
        ToolResponse.run(
          %{
            prompt: prompt,
            tools: tools
          },
          %{}
        )

      # Verify the result
      assert result ==
               {:ok,
                %{
                  result: "The result is 3",
                  tool_results: [
                    %{name: "add", arguments: %{"a" => 2, "b" => 2}, result: 4},
                    %{name: "subtract", arguments: %{"a" => 4, "b" => 1}, result: 3}
                  ]
                }}
    end

    test "handles errors from BaseCompletion" do
      # Create test data
      prompt =
        Prompt.new(%{
          messages: [
            %{role: :user, content: "Test message"}
          ]
        })

      error_message = "Test error message"

      # Mock BaseCompletion.run to return an error
      expect(LangchainAction, :run, fn _params, _context ->
        {:error, error_message}
      end)

      # Execute the action
      result =
        ToolResponse.run(
          %{
            prompt: prompt
          },
          %{}
        )

      # Verify the result
      assert result == {:error, error_message}
    end
  end
end
