defmodule Jido.Eval.DatasetTest do
  use ExUnit.Case, async: true

  alias Jido.Eval.Dataset
  alias Jido.Eval.Dataset.InMemory
  alias Jido.Eval.Sample.{SingleTurn, MultiTurn}
  alias Jido.AI.Message

  doctest Dataset

  describe "protocol implementation verification" do
    test "InMemory implements all protocol functions" do
      samples = [%SingleTurn{user_input: "Hello", response: "Hi!"}]
      {:ok, dataset} = InMemory.new(samples)

      # Verify protocol functions work
      assert :single_turn = Dataset.sample_type(dataset)
      assert 1 = Dataset.count(dataset)

      stream = Dataset.to_stream(dataset)
      assert match?(%Stream{}, stream)

      samples_from_stream = Enum.to_list(stream)
      assert length(samples_from_stream) == 1
      assert hd(samples_from_stream).user_input == "Hello"
    end

    test "protocol functions return expected types" do
      samples = [
        %MultiTurn{conversation: [%Message{role: :user, content: "Hello"}]}
      ]

      {:ok, dataset} = InMemory.new(samples)

      # Check return types
      assert Dataset.sample_type(dataset) in [:single_turn, :multi_turn]

      count = Dataset.count(dataset)
      assert is_integer(count) or count == :unknown

      stream = Dataset.to_stream(dataset)
      assert Enumerable.impl_for(stream) != nil
    end
  end

  describe "stream behavior" do
    test "streams preserve sample order" do
      samples = [
        %SingleTurn{id: "1", user_input: "First"},
        %SingleTurn{id: "2", user_input: "Second"},
        %SingleTurn{id: "3", user_input: "Third"}
      ]

      {:ok, dataset} = InMemory.new(samples)

      streamed = Dataset.to_stream(dataset) |> Enum.to_list()

      assert length(streamed) == 3
      assert Enum.at(streamed, 0).id == "1"
      assert Enum.at(streamed, 1).id == "2"
      assert Enum.at(streamed, 2).id == "3"
    end

    test "streams are lazy and memory efficient" do
      # Create a large dataset
      samples =
        Enum.map(1..1000, fn i ->
          %SingleTurn{id: "sample_#{i}", user_input: "Input #{i}"}
        end)

      {:ok, dataset} = InMemory.new(samples)

      stream = Dataset.to_stream(dataset)

      # Take only first 10 items - this should not load entire dataset
      first_ten = stream |> Enum.take(10)

      assert length(first_ten) == 10
      assert hd(first_ten).id == "sample_1"
      assert List.last(first_ten).id == "sample_10"
    end

    test "streams can be processed multiple times" do
      samples = [%SingleTurn{user_input: "Hello"}]
      {:ok, dataset} = InMemory.new(samples)

      stream = Dataset.to_stream(dataset)

      # Process stream multiple times
      first_pass = Enum.to_list(stream)
      second_pass = Enum.to_list(stream)

      assert first_pass == second_pass
      assert length(first_pass) == 1
    end
  end

  describe "sample type validation" do
    test "correctly identifies single-turn datasets" do
      samples = [
        %SingleTurn{user_input: "Hello"},
        %SingleTurn{response: "Hi"}
      ]

      {:ok, dataset} = InMemory.new(samples)

      assert :single_turn = Dataset.sample_type(dataset)
    end

    test "correctly identifies multi-turn datasets" do
      samples = [
        %MultiTurn{conversation: [%Message{role: :user, content: "Hello"}]},
        %MultiTurn{conversation: [%Message{role: :assistant, content: "Hi"}]}
      ]

      {:ok, dataset} = InMemory.new(samples)

      assert :multi_turn = Dataset.sample_type(dataset)
    end
  end

  describe "count accuracy" do
    test "returns accurate count for known-size datasets" do
      samples =
        Enum.map(1..42, fn i ->
          %SingleTurn{user_input: "Sample #{i}"}
        end)

      {:ok, dataset} = InMemory.new(samples)

      assert 42 = Dataset.count(dataset)
    end

    test "count matches stream length" do
      samples =
        Enum.map(1..17, fn i ->
          %SingleTurn{user_input: "Sample #{i}"}
        end)

      {:ok, dataset} = InMemory.new(samples)

      count = Dataset.count(dataset)
      stream_count = Dataset.to_stream(dataset) |> Enum.count()

      assert count == stream_count
      assert count == 17
    end
  end

  describe "empty datasets" do
    test "handles empty dataset correctly" do
      {:ok, dataset} = InMemory.empty(:single_turn)

      assert 0 = Dataset.count(dataset)
      assert :single_turn = Dataset.sample_type(dataset)

      samples = Dataset.to_stream(dataset) |> Enum.to_list()
      assert samples == []
    end
  end

  describe "error handling" do
    test "protocol gracefully handles malformed implementations" do
      # This would be tested with a custom malformed implementation
      # For now, we test that our implementations don't crash
      samples = [%SingleTurn{user_input: "Test"}]
      {:ok, dataset} = InMemory.new(samples)

      # These should not raise exceptions
      assert is_atom(Dataset.sample_type(dataset))
      assert is_integer(Dataset.count(dataset)) or Dataset.count(dataset) == :unknown
      assert match?(%Stream{}, Dataset.to_stream(dataset))
    end
  end
end
