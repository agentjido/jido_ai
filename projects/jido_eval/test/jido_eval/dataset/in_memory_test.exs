defmodule Jido.Eval.Dataset.InMemoryTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Jido.Eval.Dataset
  alias Jido.Eval.Dataset.InMemory
  alias Jido.Eval.Sample.{SingleTurn, MultiTurn}
  alias Jido.AI.Message

  doctest InMemory

  describe "new/1" do
    test "creates dataset from single-turn samples" do
      samples = [
        %SingleTurn{user_input: "Hello", response: "Hi!"},
        %SingleTurn{user_input: "Goodbye", response: "Bye!"}
      ]

      assert {:ok, dataset} = InMemory.new(samples)
      assert dataset.sample_type == :single_turn
      assert length(dataset.samples) == 2
    end

    test "creates dataset from multi-turn samples" do
      samples = [
        %MultiTurn{conversation: [%Message{role: :user, content: "Hello"}]},
        %MultiTurn{conversation: [%Message{role: :assistant, content: "Hi!"}]}
      ]

      assert {:ok, dataset} = InMemory.new(samples)
      assert dataset.sample_type == :multi_turn
      assert length(dataset.samples) == 2
    end

    test "rejects mixed sample types" do
      samples = [
        %SingleTurn{user_input: "Hello"},
        %MultiTurn{conversation: [%Message{role: :user, content: "Hi"}]}
      ]

      assert {:error, reason} = InMemory.new(samples)
      assert reason == "All samples must be of the same type"
    end

    test "rejects empty sample list" do
      assert {:error, reason} = InMemory.new([])
      assert reason == "Cannot detect sample type from empty list"
    end

    test "rejects invalid sample types" do
      assert {:error, reason} = InMemory.new(["invalid"])
      assert String.contains?(reason, "Unknown sample type")
    end
  end

  describe "empty/1" do
    test "creates empty single-turn dataset" do
      assert {:ok, dataset} = InMemory.empty(:single_turn)
      assert dataset.sample_type == :single_turn
      assert dataset.samples == []
    end

    test "creates empty multi-turn dataset" do
      assert {:ok, dataset} = InMemory.empty(:multi_turn)
      assert dataset.sample_type == :multi_turn
      assert dataset.samples == []
    end
  end

  describe "add_sample/2" do
    test "adds sample to empty dataset" do
      {:ok, dataset} = InMemory.empty(:single_turn)
      sample = %SingleTurn{user_input: "Hello"}

      assert {:ok, updated} = InMemory.add_sample(dataset, sample)
      assert length(updated.samples) == 1
      assert hd(updated.samples) == sample
    end

    test "adds sample to existing dataset" do
      samples = [%SingleTurn{user_input: "First"}]
      {:ok, dataset} = InMemory.new(samples)
      new_sample = %SingleTurn{user_input: "Second"}

      assert {:ok, updated} = InMemory.add_sample(dataset, new_sample)
      assert length(updated.samples) == 2
      assert List.last(updated.samples) == new_sample
    end

    test "rejects sample with wrong type" do
      {:ok, dataset} = InMemory.empty(:single_turn)
      wrong_sample = %MultiTurn{conversation: [%Message{role: :user, content: "Hello"}]}

      assert {:error, reason} = InMemory.add_sample(dataset, wrong_sample)
      assert reason == "Sample type does not match dataset type"
    end
  end

  describe "get_sample/2" do
    test "retrieves sample by index" do
      samples = [
        %SingleTurn{id: "first", user_input: "Hello"},
        %SingleTurn{id: "second", user_input: "Hi"}
      ]

      {:ok, dataset} = InMemory.new(samples)

      assert {:ok, sample} = InMemory.get_sample(dataset, 0)
      assert sample.id == "first"

      assert {:ok, sample} = InMemory.get_sample(dataset, 1)
      assert sample.id == "second"
    end

    test "returns error for out of bounds index" do
      samples = [%SingleTurn{user_input: "Hello"}]
      {:ok, dataset} = InMemory.new(samples)

      assert {:error, reason} = InMemory.get_sample(dataset, 5)
      assert reason == "Index out of bounds"

      assert {:error, reason} = InMemory.get_sample(dataset, -1)
      assert reason == "Index out of bounds"
    end
  end

  describe "Dataset protocol implementation" do
    test "to_stream/1 produces correct samples" do
      samples = [
        %SingleTurn{id: "1", user_input: "First"},
        %SingleTurn{id: "2", user_input: "Second"}
      ]

      {:ok, dataset} = InMemory.new(samples)

      streamed_samples = Dataset.to_stream(dataset) |> Enum.to_list()

      assert length(streamed_samples) == 2
      assert Enum.at(streamed_samples, 0).id == "1"
      assert Enum.at(streamed_samples, 1).id == "2"
    end

    test "sample_type/1 returns correct type" do
      single_samples = [%SingleTurn{user_input: "Hello"}]
      {:ok, single_dataset} = InMemory.new(single_samples)
      assert Dataset.sample_type(single_dataset) == :single_turn

      multi_samples = [%MultiTurn{conversation: [%Message{role: :user, content: "Hello"}]}]
      {:ok, multi_dataset} = InMemory.new(multi_samples)
      assert Dataset.sample_type(multi_dataset) == :multi_turn
    end

    test "count/1 returns accurate count" do
      samples =
        Enum.map(1..100, fn i ->
          %SingleTurn{id: "sample_#{i}", user_input: "Input #{i}"}
        end)

      {:ok, dataset} = InMemory.new(samples)

      assert Dataset.count(dataset) == 100
    end

    test "empty dataset has zero count" do
      {:ok, dataset} = InMemory.empty(:single_turn)
      assert Dataset.count(dataset) == 0
    end
  end

  describe "performance tests" do
    test "handles large datasets efficiently" do
      # Create dataset with 10k samples
      samples =
        Enum.map(1..10_000, fn i ->
          %SingleTurn{id: "sample_#{i}", user_input: "Input #{i}"}
        end)

      # Should create quickly
      start_time = :os.system_time(:millisecond)
      {:ok, dataset} = InMemory.new(samples)
      creation_time = :os.system_time(:millisecond) - start_time

      # Should take less than 1 second
      assert creation_time < 1000
      assert Dataset.count(dataset) == 10_000

      # Streaming should be efficient
      stream_start = :os.system_time(:millisecond)
      first_100 = Dataset.to_stream(dataset) |> Enum.take(100)
      stream_time = :os.system_time(:millisecond) - stream_start

      assert length(first_100) == 100
      # Should take less than 100ms
      assert stream_time < 100
    end

    test "memory usage remains reasonable for streaming" do
      # This test ensures streaming doesn't load everything into memory
      samples =
        Enum.map(1..1000, fn i ->
          %SingleTurn{id: "sample_#{i}", user_input: String.duplicate("x", 1000)}
        end)

      {:ok, dataset} = InMemory.new(samples)

      # Process stream in chunks to verify lazy evaluation
      stream = Dataset.to_stream(dataset)

      chunk1 = stream |> Enum.take(10)
      chunk2 = stream |> Stream.drop(10) |> Enum.take(10)

      assert length(chunk1) == 10
      assert length(chunk2) == 10
      assert hd(chunk1).id != hd(chunk2).id
    end
  end

  describe "property tests" do
    property "dataset preserves sample order and content" do
      check all(
              sample_count <- integer(1..100),
              max_runs: 20
            ) do
        samples =
          Enum.map(1..sample_count, fn i ->
            %SingleTurn{id: "sample_#{i}", user_input: "Input #{i}"}
          end)

        {:ok, dataset} = InMemory.new(samples)
        streamed = Dataset.to_stream(dataset) |> Enum.to_list()

        assert length(streamed) == sample_count
        assert Dataset.count(dataset) == sample_count

        # Verify order preservation
        Enum.with_index(streamed, fn sample, index ->
          expected_id = "sample_#{index + 1}"
          assert sample.id == expected_id
        end)
      end
    end

    property "add_sample preserves existing samples and adds new one" do
      check all(
              initial_count <- integer(0..10),
              max_runs: 20
            ) do
        # Create initial samples
        initial_samples =
          if initial_count > 0 do
            Enum.map(1..initial_count, fn i ->
              %SingleTurn{id: "initial_#{i}", user_input: "Initial #{i}"}
            end)
          else
            []
          end

        {:ok, dataset} =
          if initial_count == 0 do
            InMemory.empty(:single_turn)
          else
            InMemory.new(initial_samples)
          end

        new_sample = %SingleTurn{id: "new", user_input: "New sample"}
        {:ok, updated} = InMemory.add_sample(dataset, new_sample)

        assert Dataset.count(updated) == initial_count + 1

        all_samples = Dataset.to_stream(updated) |> Enum.to_list()
        assert List.last(all_samples) == new_sample
      end
    end
  end

  describe "edge cases" do
    test "handles samples with complex nested data" do
      complex_sample = %SingleTurn{
        id: "complex",
        user_input: "Input with unicode: 世界 🌍",
        retrieved_contexts: Enum.map(1..100, &"context_#{&1}"),
        reference_contexts: Enum.map(1..50, &"ref_#{&1}"),
        multi_responses: Enum.map(1..10, &"response_#{&1}"),
        rubrics:
          Enum.reduce(1..20, %{}, fn i, acc ->
            Map.put(acc, "rubric_#{i}", "value_#{i}")
          end),
        tags: %{"category" => "complex", "difficulty" => "high"}
      }

      {:ok, dataset} = InMemory.new([complex_sample])
      [retrieved] = Dataset.to_stream(dataset) |> Enum.to_list()

      assert retrieved == complex_sample
      assert length(retrieved.retrieved_contexts) == 100
      assert map_size(retrieved.rubrics) == 20
    end

    test "handles datasets with duplicate samples" do
      duplicate_sample = %SingleTurn{id: "duplicate", user_input: "Same"}
      samples = [duplicate_sample, duplicate_sample, duplicate_sample]

      {:ok, dataset} = InMemory.new(samples)
      assert Dataset.count(dataset) == 3

      streamed = Dataset.to_stream(dataset) |> Enum.to_list()
      assert length(streamed) == 3
      assert Enum.all?(streamed, &(&1 == duplicate_sample))
    end
  end
end
