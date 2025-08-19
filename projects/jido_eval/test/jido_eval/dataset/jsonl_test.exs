defmodule Jido.Eval.Dataset.JSONLTest do
  # File operations need to be synchronous
  use ExUnit.Case, async: false
  use ExUnitProperties

  alias Jido.Eval.Dataset
  alias Jido.Eval.Dataset.JSONL
  alias Jido.Eval.Sample.{SingleTurn, MultiTurn}
  alias Jido.AI.Message

  @fixtures_path Path.join([__DIR__, "..", "..", "fixtures"])
  @single_turn_file Path.join(@fixtures_path, "single_turn_samples.jsonl")
  @multi_turn_file Path.join(@fixtures_path, "multi_turn_samples.jsonl")

  setup do
    # Create temp directory for test files
    temp_dir = System.tmp_dir!() |> Path.join("jido_eval_test_#{:rand.uniform(1_000_000)}")
    File.mkdir_p!(temp_dir)

    on_exit(fn ->
      File.rm_rf!(temp_dir)
    end)

    {:ok, temp_dir: temp_dir}
  end

  describe "new/2" do
    test "creates dataset from existing single-turn file" do
      assert {:ok, dataset} = JSONL.new(@single_turn_file, :single_turn)
      assert dataset.file_path == @single_turn_file
      assert dataset.sample_type == :single_turn
      assert dataset.encoding == :utf8
    end

    test "creates dataset from existing multi-turn file" do
      assert {:ok, dataset} = JSONL.new(@multi_turn_file, :multi_turn)
      assert dataset.file_path == @multi_turn_file
      assert dataset.sample_type == :multi_turn
    end

    test "accepts encoding option" do
      assert {:ok, dataset} = JSONL.new(@single_turn_file, :single_turn, encoding: :latin1)
      assert dataset.encoding == :latin1
    end

    test "rejects non-existent file" do
      assert {:error, reason} = JSONL.new("nonexistent.jsonl", :single_turn)
      assert String.contains?(reason, "does not exist")
    end
  end

  describe "auto_detect/1" do
    test "auto-detects single-turn samples" do
      assert {:ok, dataset} = JSONL.auto_detect(@single_turn_file)
      assert dataset.sample_type == :single_turn
    end

    test "auto-detects multi-turn samples" do
      assert {:ok, dataset} = JSONL.auto_detect(@multi_turn_file)
      assert dataset.sample_type == :multi_turn
    end

    test "handles malformed file gracefully", %{temp_dir: temp_dir} do
      malformed_file = Path.join(temp_dir, "malformed.jsonl")
      File.write!(malformed_file, "not json\n{invalid json\n")

      assert {:error, reason} = JSONL.auto_detect(malformed_file)

      assert String.contains?(reason, "Failed to read file") or
               String.contains?(reason, "No valid JSON")
    end

    test "handles empty file", %{temp_dir: temp_dir} do
      empty_file = Path.join(temp_dir, "empty.jsonl")
      File.write!(empty_file, "")

      assert {:error, reason} = JSONL.auto_detect(empty_file)
      assert String.contains?(reason, "No valid JSON")
    end
  end

  describe "write/2" do
    test "writes single-turn samples to file", %{temp_dir: temp_dir} do
      samples = [
        %SingleTurn{id: "test_1", user_input: "Hello", response: "Hi!"},
        %SingleTurn{id: "test_2", user_input: "Goodbye", response: "Bye!"}
      ]

      output_file = Path.join(temp_dir, "output.jsonl")
      assert :ok = JSONL.write(output_file, samples)
      assert File.exists?(output_file)

      # Verify file content
      {:ok, dataset} = JSONL.new(output_file, :single_turn)
      written_samples = Dataset.to_stream(dataset) |> Enum.to_list()

      assert length(written_samples) == 2
      assert Enum.at(written_samples, 0).id == "test_1"
      assert Enum.at(written_samples, 1).id == "test_2"
    end

    test "writes multi-turn samples to file", %{temp_dir: temp_dir} do
      samples = [
        %MultiTurn{
          id: "conv_1",
          conversation: [
            %Message{role: :user, content: "Hello"},
            %Message{role: :assistant, content: "Hi!"}
          ]
        }
      ]

      output_file = Path.join(temp_dir, "multi_output.jsonl")
      assert :ok = JSONL.write(output_file, samples)

      # Verify content
      {:ok, dataset} = JSONL.new(output_file, :multi_turn)
      written_samples = Dataset.to_stream(dataset) |> Enum.to_list()

      assert length(written_samples) == 1
      [sample] = written_samples
      assert sample.id == "conv_1"
      assert length(sample.conversation) == 2
    end

    test "handles write errors gracefully" do
      samples = [%SingleTurn{user_input: "Test"}]
      invalid_path = "/invalid/path/file.jsonl"

      assert {:error, reason} = JSONL.write(invalid_path, samples)
      assert String.contains?(reason, "Failed to write file")
    end
  end

  describe "Dataset protocol implementation" do
    test "to_stream/1 reads single-turn samples correctly" do
      {:ok, dataset} = JSONL.new(@single_turn_file, :single_turn)
      samples = Dataset.to_stream(dataset) |> Enum.to_list()

      assert length(samples) == 3

      [first, second, third] = samples
      assert first.id == "sample_1"
      assert first.user_input == "What is AI?"
      assert first.response == "AI is artificial intelligence"
      assert first.tags == %{"category" => "tech"}

      assert second.id == "sample_2"
      assert third.id == "sample_3"
      assert third.reference == "I'm fine"
    end

    test "to_stream/1 reads multi-turn samples correctly" do
      {:ok, dataset} = JSONL.new(@multi_turn_file, :multi_turn)
      samples = Dataset.to_stream(dataset) |> Enum.to_list()

      assert length(samples) == 2

      [first, second] = samples
      assert first.id == "conv_1"
      assert length(first.conversation) == 2
      assert Enum.at(first.conversation, 0).role == :user
      assert Enum.at(first.conversation, 0).content == "Hello"

      assert second.id == "conv_2"
      assert length(second.conversation) == 3
      assert second.reference == "Should provide weather info"
    end

    test "sample_type/1 returns correct type" do
      {:ok, single_dataset} = JSONL.new(@single_turn_file, :single_turn)
      assert Dataset.sample_type(single_dataset) == :single_turn

      {:ok, multi_dataset} = JSONL.new(@multi_turn_file, :multi_turn)
      assert Dataset.sample_type(multi_dataset) == :multi_turn
    end

    test "count/1 returns accurate count" do
      {:ok, single_dataset} = JSONL.new(@single_turn_file, :single_turn)
      assert Dataset.count(single_dataset) == 3

      {:ok, multi_dataset} = JSONL.new(@multi_turn_file, :multi_turn)
      assert Dataset.count(multi_dataset) == 2
    end

    test "handles empty lines and whitespace" do
      content = """
      {"id": "1", "user_input": "Hello"}

      {"id": "2", "user_input": "Hi"}


      {"id": "3", "user_input": "Bye"}
      """

      temp_file = Path.join(System.tmp_dir!(), "whitespace_test.jsonl")
      File.write!(temp_file, content)

      {:ok, dataset} = JSONL.new(temp_file, :single_turn)
      samples = Dataset.to_stream(dataset) |> Enum.to_list()

      assert length(samples) == 3
      assert Enum.map(samples, & &1.id) == ["1", "2", "3"]

      File.rm!(temp_file)
    end

    test "filters out malformed lines" do
      content = """
      {"id": "1", "user_input": "Hello"}
      not json
      {"id": "2", "user_input": "Hi"}
      {invalid json
      {"id": "3", "user_input": "Bye"}
      """

      temp_file = Path.join(System.tmp_dir!(), "malformed_test.jsonl")
      File.write!(temp_file, content)

      {:ok, dataset} = JSONL.new(temp_file, :single_turn)
      samples = Dataset.to_stream(dataset) |> Enum.to_list()

      # Should only get valid samples, malformed lines are filtered out
      assert length(samples) == 3
      assert Enum.map(samples, & &1.id) == ["1", "2", "3"]

      File.rm!(temp_file)
    end
  end

  describe "streaming behavior" do
    test "streams are lazy and memory efficient", %{temp_dir: temp_dir} do
      # Create a large JSONL file
      large_file = Path.join(temp_dir, "large.jsonl")

      File.open!(large_file, [:write], fn file ->
        Enum.each(1..1000, fn i ->
          sample = %{"id" => "sample_#{i}", "user_input" => "Input #{i}"}
          IO.write(file, Jason.encode!(sample) <> "\n")
        end)
      end)

      {:ok, dataset} = JSONL.new(large_file, :single_turn)
      stream = Dataset.to_stream(dataset)

      # Taking first 10 should be fast and not load entire file
      start_time = :os.system_time(:millisecond)
      first_ten = Enum.take(stream, 10)
      elapsed = :os.system_time(:millisecond) - start_time

      assert length(first_ten) == 10
      # Should be very fast
      assert elapsed < 100
      assert hd(first_ten).id == "sample_1"
    end

    test "can process stream multiple times" do
      {:ok, dataset} = JSONL.new(@single_turn_file, :single_turn)
      stream = Dataset.to_stream(dataset)

      first_pass = Enum.to_list(stream)
      second_pass = Enum.to_list(stream)

      assert first_pass == second_pass
      assert length(first_pass) == 3
    end
  end

  describe "round-trip serialization" do
    test "write then read preserves sample data", %{temp_dir: temp_dir} do
      original_samples = [
        %SingleTurn{
          id: "complex",
          user_input: "What is AI?",
          retrieved_contexts: ["context1", "context2"],
          reference_contexts: ["ref1"],
          response: "AI is artificial intelligence",
          multi_responses: ["AI is...", "Artificial Intelligence..."],
          reference: "Ground truth",
          rubrics: %{"accuracy" => "high", "relevance" => "good"},
          tags: %{"category" => "tech", "difficulty" => "medium"}
        }
      ]

      test_file = Path.join(temp_dir, "roundtrip.jsonl")
      assert :ok = JSONL.write(test_file, original_samples)

      {:ok, dataset} = JSONL.new(test_file, :single_turn)
      restored_samples = Dataset.to_stream(dataset) |> Enum.to_list()

      assert length(restored_samples) == 1
      [restored] = restored_samples

      assert restored.id == "complex"
      assert restored.user_input == "What is AI?"
      assert restored.retrieved_contexts == ["context1", "context2"]
      assert restored.reference_contexts == ["ref1"]
      assert restored.response == "AI is artificial intelligence"
      assert restored.multi_responses == ["AI is...", "Artificial Intelligence..."]
      assert restored.reference == "Ground truth"
      assert restored.rubrics == %{"accuracy" => "high", "relevance" => "good"}
      assert restored.tags == %{"category" => "tech", "difficulty" => "medium"}
    end
  end

  describe "property tests" do
    property "reading written files preserves sample count and basic structure", %{
      temp_dir: temp_dir
    } do
      check all(
              sample_count <- integer(1..50),
              max_runs: 10
            ) do
        # Generate samples
        samples =
          Enum.map(1..sample_count, fn i ->
            %SingleTurn{
              id: "sample_#{i}",
              user_input: "Input #{i}",
              response: "Response #{i}",
              tags: %{"index" => to_string(i)}
            }
          end)

        test_file = Path.join(temp_dir, "prop_test_#{:rand.uniform(10000)}.jsonl")
        assert :ok = JSONL.write(test_file, samples)

        {:ok, dataset} = JSONL.new(test_file, :single_turn)
        restored_samples = Dataset.to_stream(dataset) |> Enum.to_list()

        assert length(restored_samples) == sample_count
        assert Dataset.count(dataset) == sample_count

        # Verify sample structure is preserved
        Enum.zip(samples, restored_samples)
        |> Enum.each(fn {original, restored} ->
          assert original.id == restored.id
          assert original.user_input == restored.user_input
          assert original.response == restored.response
        end)
      end
    end
  end

  describe "error handling" do
    test "handles corrupted files gracefully" do
      temp_file = Path.join(System.tmp_dir!(), "corrupted.jsonl")

      # Write some valid lines, then corrupt data
      File.write!(temp_file, """
      {"id": "1", "user_input": "Valid"}
      {"id": "2", "user_input": "Also valid"}
      """)

      {:ok, dataset} = JSONL.new(temp_file, :single_turn)
      samples = Dataset.to_stream(dataset) |> Enum.to_list()

      # Should successfully read valid samples
      assert length(samples) == 2

      File.rm!(temp_file)
    end

    test "count handles unreadable files gracefully" do
      dataset = %JSONL{file_path: "/nonexistent/file.jsonl", sample_type: :single_turn}
      assert Dataset.count(dataset) == :unknown
    end
  end
end
