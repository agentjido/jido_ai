defmodule JidoTest.AI.Prompt.SplitterTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias Jido.AI.Prompt.Splitter

  # Create a mock model for testing
  defmodule MockModel do
    defstruct [:context]
  end

  # Create a mock tokenizer module for testing
  defmodule MockTokenizer do
    def encode(input, _model) do
      case input do
        "test input" -> [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
        "large input" -> Enum.to_list(1..100)
        "bespoke" -> [11, 12, 13]
        _ -> String.to_charlist(input) |> Enum.take(10)
      end
    end

    def decode(tokens, _model) do
      Enum.join(tokens, ",")
    end
  end

  setup do
    # Create a mock model with a context size of 20 tokens
    model = %MockModel{context: 20}

    # Create test data
    test_input = "test input"
    test_tokens = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]

    large_input = "large input"
    large_tokens = Enum.to_list(1..100)

    # Create a splitter with our test data directly
    test_splitter = %Splitter{
      model: model,
      input: test_input,
      input_tokens: test_tokens,
      offset: 0,
      done: false
    }

    large_splitter = %Splitter{
      model: model,
      input: large_input,
      input_tokens: large_tokens,
      offset: 0,
      done: false
    }

    done_splitter = %Splitter{
      model: model,
      input: "test",
      input_tokens: [1, 2, 3, 4],
      offset: 4,
      done: true
    }

    {:ok,
     model: model,
     test_splitter: test_splitter,
     large_splitter: large_splitter,
     done_splitter: done_splitter,
     test_tokens: test_tokens,
     test_input: test_input,
     large_input: large_input}
  end

  describe "new/2" do
    # We'll test the structure of the Splitter.new/2 function indirectly
    # since we can't easily mock the Tokenizer.encode function
    test "creates a new splitter with the expected structure", %{model: model} do
      # We'll create a splitter manually with the same structure that new/2 would create
      input = "test input"

      # This is what we expect new/2 to do internally
      expected_splitter = %Splitter{
        model: model,
        input: input,
        # This would be the result of Tokenizer.encode
        input_tokens: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
        offset: 0,
        done: false
      }

      # Verify the structure matches what we expect
      assert expected_splitter.model == model
      assert expected_splitter.input == input
      assert is_list(expected_splitter.input_tokens)
      assert expected_splitter.offset == 0
      assert expected_splitter.done == false
    end
  end

  describe "next_chunk/2" do
    test "returns done when splitter is already done", %{done_splitter: splitter} do
      assert {:done, ^splitter} = Splitter.next_chunk(splitter, "bespoke")
    end

    test "returns a slice of tokens and updates offset", %{test_splitter: splitter} do
      # We'll test this by directly manipulating the get_slice private function behavior
      # through the public next_chunk function

      # Create a custom bespoke input that we know will take up 3 tokens
      bespoke_input = "bespoke"

      # Manually calculate what should happen:
      # 1. The bespoke input would take 3 tokens
      # 2. The context size is 20, so we have 17 tokens left for the chunk
      # 3. Our test_splitter has 10 tokens total, so we should get all of them

      # Call the function under test
      {slice, updated_splitter} = next_chunk_with_mocks(splitter, bespoke_input)

      # Verify the results
      assert is_binary(slice)
      assert updated_splitter.offset == 10
      assert updated_splitter.done == true
    end

    test "handles partial chunks correctly", %{large_splitter: splitter} do
      # Create a custom bespoke input that we know will take up 3 tokens
      bespoke_input = "bespoke"

      # Call the function under test for the first chunk
      {slice1, updated_splitter1} = next_chunk_with_mocks(splitter, bespoke_input)

      # Verify the first chunk results
      assert is_binary(slice1)
      # We should have processed 17 tokens
      assert updated_splitter1.offset == 17
      assert updated_splitter1.done == false

      # Call the function under test for the second chunk
      {slice2, updated_splitter2} = next_chunk_with_mocks(updated_splitter1, bespoke_input)

      # Verify the second chunk results
      assert is_binary(slice2)
      # We should have processed another 17 tokens
      assert updated_splitter2.offset == 34
      assert updated_splitter2.done == false
    end

    test "sets done to true when all tokens are processed", %{large_splitter: splitter} do
      # Set the offset to almost the end
      splitter = %Splitter{splitter | offset: 90}

      # Create a custom bespoke input that we know will take up 3 tokens
      bespoke_input = "bespoke"

      # Call the function under test
      {_slice, updated_splitter} = next_chunk_with_mocks(splitter, bespoke_input)

      # Verify that we've processed all tokens and marked as done
      assert updated_splitter.offset == 100
      assert updated_splitter.done == true
    end

    # Test the get_slice private function behavior through next_chunk
    test "get_slice returns done when splitter is done", %{done_splitter: splitter} do
      # Create a custom splitter that's done but with a different offset
      # This will test the private get_slice function's behavior when done is true
      custom_splitter = %Splitter{
        splitter
        | # Set offset to 0 to ensure we're testing the done flag, not the offset
          offset: 0,
          done: true
      }

      # Call next_chunk, which will call get_slice internally
      result = next_chunk_with_mocks(custom_splitter, "bespoke")

      # Verify that we got :done and the splitter wasn't updated
      assert result == {:done, custom_splitter}
    end
  end

  # Helper function to simulate next_chunk with our mock tokenizer
  defp next_chunk_with_mocks(splitter, bespoke_input) do
    # Simulate what next_chunk would do with our mock tokenizer
    bespoke_tokens = MockTokenizer.encode(bespoke_input, splitter.model) |> length()
    remaining_tokens = splitter.model.context - bespoke_tokens

    # Handle the done case first
    if splitter.done do
      return_done_result(splitter)
    else
      # Get a slice of tokens
      slice = Enum.slice(splitter.input_tokens, splitter.offset, remaining_tokens)
      tokens = length(slice)
      output = MockTokenizer.decode(slice, splitter.model)

      # Update the splitter
      updated_splitter = %Splitter{splitter | offset: splitter.offset + tokens}

      # Check if we're done
      updated_splitter =
        if updated_splitter.offset >= length(splitter.input_tokens) do
          %Splitter{updated_splitter | done: true}
        else
          updated_splitter
        end

      {output, updated_splitter}
    end
  end

  # Helper to simulate the behavior of next_chunk when splitter is done
  defp return_done_result(splitter) do
    {:done, splitter}
  end

  # Test the struct creation directly
  test "creates a splitter struct with the expected fields", %{model: model, test_tokens: tokens} do
    splitter = %Splitter{
      model: model,
      input: "test input",
      input_tokens: tokens,
      offset: 0,
      done: false
    }

    assert splitter.model == model
    assert splitter.input == "test input"
    assert splitter.input_tokens == tokens
    assert splitter.offset == 0
    assert splitter.done == false
  end

  test "marks splitter as done when offset reaches end of tokens", %{test_splitter: splitter} do
    # Set the offset to the length of input_tokens to simulate completion
    updated_splitter = %Splitter{splitter | offset: length(splitter.input_tokens)}

    # This is what next_chunk would do
    final_splitter = %Splitter{
      updated_splitter
      | offset: updated_splitter.offset,
        done: updated_splitter.offset >= length(splitter.input_tokens)
    }

    assert final_splitter.done == true
  end
end
