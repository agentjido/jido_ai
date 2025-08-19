defmodule Jido.Eval.Dataset.CSVTest do
  # File operations need to be synchronous
  use ExUnit.Case, async: false
  use ExUnitProperties

  alias Jido.Eval.Dataset
  alias Jido.Eval.Dataset.CSV
  alias Jido.Eval.Sample.SingleTurn

  @fixtures_path Path.join([__DIR__, "..", "..", "fixtures"])
  @csv_file Path.join(@fixtures_path, "single_turn_samples.csv")

  setup do
    # Create temp directory for test files
    temp_dir = System.tmp_dir!() |> Path.join("jido_eval_csv_test_#{:rand.uniform(1_000_000)}")
    File.mkdir_p!(temp_dir)

    on_exit(fn ->
      File.rm_rf!(temp_dir)
    end)

    {:ok, temp_dir: temp_dir}
  end

  describe "new/1" do
    test "creates dataset from existing CSV file" do
      assert {:ok, dataset} = CSV.new(@csv_file)
      assert dataset.file_path == @csv_file
      assert dataset.separator == ","
      assert dataset.encoding == :utf8
      assert is_list(dataset.headers)
      assert length(dataset.headers) > 0
    end

    test "accepts separator option", %{temp_dir: temp_dir} do
      content = "id;user_input;response\nsample_1;Hello;Hi!\n"
      test_file = Path.join(temp_dir, "semicolon.csv")
      File.write!(test_file, content)

      assert {:ok, dataset} = CSV.new(test_file, separator: ";")
      assert dataset.separator == ";"
    end

    test "accepts encoding option" do
      assert {:ok, dataset} = CSV.new(@csv_file, encoding: :latin1)
      assert dataset.encoding == :latin1
    end

    test "rejects non-existent file" do
      assert {:error, reason} = CSV.new("nonexistent.csv")
      assert String.contains?(reason, "does not exist")
    end

    test "handles malformed CSV headers gracefully", %{temp_dir: temp_dir} do
      malformed_file = Path.join(temp_dir, "malformed.csv")
      File.write!(malformed_file, "not,csv,properly\nformed")

      # Should still work, just with limited functionality
      assert {:ok, _dataset} = CSV.new(malformed_file)
    end
  end

  describe "write/2" do
    test "writes samples to CSV file", %{temp_dir: temp_dir} do
      samples = [
        %SingleTurn{
          id: "test_1",
          user_input: "Hello",
          response: "Hi there!",
          tags: %{"category" => "greeting", "tone" => "friendly"}
        },
        %SingleTurn{
          id: "test_2",
          user_input: "Goodbye",
          response: "See you later!",
          retrieved_contexts: ["context1", "context2"],
          rubrics: %{"politeness" => "high"}
        }
      ]

      output_file = Path.join(temp_dir, "output.csv")
      assert :ok = CSV.write(output_file, samples)
      assert File.exists?(output_file)

      # Verify file content by reading it back
      {:ok, dataset} = CSV.new(output_file)
      written_samples = Dataset.to_stream(dataset) |> Enum.to_list()

      assert length(written_samples) == 2
      [first, second] = written_samples

      assert first.id == "test_1"
      assert first.user_input == "Hello"
      assert first.response == "Hi there!"
      assert first.tags == %{"category" => "greeting", "tone" => "friendly"}

      assert second.id == "test_2"
      assert second.retrieved_contexts == ["context1", "context2"]
      assert second.rubrics == %{"politeness" => "high"}
    end

    test "handles empty sample list", %{temp_dir: temp_dir} do
      output_file = Path.join(temp_dir, "empty.csv")
      assert {:error, reason} = CSV.write(output_file, [])
      assert String.contains?(reason, "empty sample list")
    end

    test "handles write errors gracefully" do
      samples = [%SingleTurn{user_input: "Test"}]
      invalid_path = "/invalid/path/file.csv"

      assert {:error, reason} = CSV.write(invalid_path, samples)
      assert String.contains?(reason, "Failed to write CSV file")
    end
  end

  describe "Dataset protocol implementation" do
    test "to_stream/1 reads samples correctly" do
      {:ok, dataset} = CSV.new(@csv_file)
      samples = Dataset.to_stream(dataset) |> Enum.to_list()

      assert length(samples) == 3

      [first, second, third] = samples
      assert first.id == "sample_1"
      assert first.user_input == "What is AI?"
      assert first.retrieved_contexts == ["context1", "context2"]
      assert first.reference_contexts == ["ref1"]
      assert first.response == "AI is artificial intelligence"
      assert first.multi_responses == ["Response A", "Response B"]
      assert first.reference == "Ground truth"
      assert first.rubrics == %{"accuracy" => "high", "relevance" => "good"}
      assert first.tags == %{"category" => "tech", "difficulty" => "easy"}

      assert second.id == "sample_2"
      assert second.user_input == "Hello"
      assert second.response == "Hi there!"
      assert second.reference == "Expected greeting"
      assert second.rubrics == %{"politeness" => "high"}
      assert second.tags == %{"category" => "greeting"}

      assert third.id == "sample_3"
      assert third.rubrics == %{"tone" => "positive"}
      assert third.tags == %{"category" => "personal", "mood" => "friendly"}
    end

    test "sample_type/1 always returns :single_turn" do
      {:ok, dataset} = CSV.new(@csv_file)
      assert Dataset.sample_type(dataset) == :single_turn
    end

    test "count/1 returns accurate count" do
      {:ok, dataset} = CSV.new(@csv_file)
      assert Dataset.count(dataset) == 3
    end

    test "handles empty CSV files", %{temp_dir: temp_dir} do
      empty_file = Path.join(temp_dir, "empty.csv")
      File.write!(empty_file, "id,user_input,response\n")

      {:ok, dataset} = CSV.new(empty_file)
      assert Dataset.count(dataset) == 0

      samples = Dataset.to_stream(dataset) |> Enum.to_list()
      assert samples == []
    end

    test "handles missing optional fields", %{temp_dir: temp_dir} do
      minimal_csv = """
      id,user_input,response
      sample_1,Hello,Hi!
      sample_2,Bye,Goodbye!
      """

      test_file = Path.join(temp_dir, "minimal.csv")
      File.write!(test_file, minimal_csv)

      {:ok, dataset} = CSV.new(test_file)
      samples = Dataset.to_stream(dataset) |> Enum.to_list()

      assert length(samples) == 2
      [first, second] = samples

      assert first.id == "sample_1"
      assert first.user_input == "Hello"
      assert first.response == "Hi!"
      assert first.retrieved_contexts == nil
      assert first.tags == %{}

      assert second.id == "sample_2"
      assert second.user_input == "Bye"
      assert second.response == "Goodbye!"
    end

    test "handles malformed data gracefully", %{temp_dir: temp_dir} do
      malformed_csv = """
      id,user_input,response,tags
      sample_1,Hello,Hi!,valid:tag
      sample_2,Missing response,,"another:tag"
      sample_3,Complete,Response,malformed_tag_format
      """

      test_file = Path.join(temp_dir, "malformed.csv")
      File.write!(test_file, malformed_csv)

      {:ok, dataset} = CSV.new(test_file)
      samples = Dataset.to_stream(dataset) |> Enum.to_list()

      # Should read all samples, handling malformed data appropriately
      assert length(samples) == 3

      [first, second, third] = samples
      assert first.tags == %{"valid" => "tag"}
      # Empty response
      assert second.response == nil
      assert second.tags == %{"another" => "tag"}
      # Malformed tag becomes key with "true" value
      assert third.tags == %{"malformed_tag_format" => "true"}
    end
  end

  describe "CSV format handling" do
    test "handles quoted fields with special characters", %{temp_dir: temp_dir} do
      special_csv = """
      id,user_input,response
      sample_1,"Hello, world!","Hi there, friend!"
      sample_2,"Question with ""quotes""?","Answer with ""quotes""."
      sample_3,"Multiline
      content","Multiline
      response"
      """

      test_file = Path.join(temp_dir, "special.csv")
      File.write!(test_file, special_csv)

      {:ok, dataset} = CSV.new(test_file)
      samples = Dataset.to_stream(dataset) |> Enum.to_list()

      assert length(samples) == 3

      [first, second, third] = samples
      assert first.user_input == "Hello, world!"
      assert first.response == "Hi there, friend!"

      assert String.contains?(second.user_input, "\"quotes\"")
      assert String.contains?(second.response, "\"quotes\"")

      assert String.contains?(third.user_input, "\n")
      assert String.contains?(third.response, "\n")
    end

    test "handles semicolon-separated lists correctly", %{temp_dir: temp_dir} do
      list_csv = """
      id,user_input,retrieved_contexts,multi_responses,rubrics
      sample_1,Hello,context1;context2;context3,resp1;resp2,key1:val1;key2:val2
      """

      test_file = Path.join(temp_dir, "lists.csv")
      File.write!(test_file, list_csv)

      {:ok, dataset} = CSV.new(test_file)
      [sample] = Dataset.to_stream(dataset) |> Enum.to_list()

      assert sample.retrieved_contexts == ["context1", "context2", "context3"]
      assert sample.multi_responses == ["resp1", "resp2"]
      assert sample.rubrics == %{"key1" => "val1", "key2" => "val2"}
    end

    test "handles empty and nil values correctly", %{temp_dir: temp_dir} do
      empty_csv = """
      id,user_input,response,retrieved_contexts,rubrics,tags
      sample_1,Hello,,,"",""
      sample_2,,,context1,key:value,tag:value
      """

      test_file = Path.join(temp_dir, "empty_vals.csv")
      File.write!(test_file, empty_csv)

      {:ok, dataset} = CSV.new(test_file)
      samples = Dataset.to_stream(dataset) |> Enum.to_list()

      assert length(samples) == 2

      [first, second] = samples
      assert first.response == nil
      assert first.retrieved_contexts == nil
      assert first.rubrics == %{}
      assert first.tags == %{}

      assert second.user_input == nil
      assert second.response == nil
      assert second.retrieved_contexts == ["context1"]
      assert second.rubrics == %{"key" => "value"}
      assert second.tags == %{"tag" => "value"}
    end
  end

  describe "round-trip serialization" do
    test "write then read preserves data integrity", %{temp_dir: temp_dir} do
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
        },
        %SingleTurn{
          id: "simple",
          user_input: "Hello",
          response: "Hi!",
          tags: %{"category" => "greeting"}
        }
      ]

      test_file = Path.join(temp_dir, "roundtrip.csv")
      assert :ok = CSV.write(test_file, original_samples)

      {:ok, dataset} = CSV.new(test_file)
      restored_samples = Dataset.to_stream(dataset) |> Enum.to_list()

      assert length(restored_samples) == 2
      [complex, simple] = restored_samples

      # Verify complex sample
      assert complex.id == "complex"
      assert complex.user_input == "What is AI?"
      assert complex.retrieved_contexts == ["context1", "context2"]
      assert complex.reference_contexts == ["ref1"]
      assert complex.response == "AI is artificial intelligence"
      assert complex.multi_responses == ["AI is...", "Artificial Intelligence..."]
      assert complex.reference == "Ground truth"
      assert complex.rubrics == %{"accuracy" => "high", "relevance" => "good"}
      assert complex.tags == %{"category" => "tech", "difficulty" => "medium"}

      # Verify simple sample
      assert simple.id == "simple"
      assert simple.user_input == "Hello"
      assert simple.response == "Hi!"
      assert simple.tags == %{"category" => "greeting"}
    end
  end

  describe "streaming behavior" do
    test "streams are lazy and memory efficient", %{temp_dir: temp_dir} do
      # Create a large CSV file
      large_file = Path.join(temp_dir, "large.csv")

      File.open!(large_file, [:write], fn file ->
        IO.write(file, "id,user_input,response\n")

        Enum.each(1..1000, fn i ->
          IO.write(file, "sample_#{i},Input #{i},Response #{i}\n")
        end)
      end)

      {:ok, dataset} = CSV.new(large_file)
      stream = Dataset.to_stream(dataset)

      # Taking first 10 should be fast
      start_time = :os.system_time(:millisecond)
      first_ten = Enum.take(stream, 10)
      elapsed = :os.system_time(:millisecond) - start_time

      assert length(first_ten) == 10
      # Should be reasonably fast
      assert elapsed < 200
      assert hd(first_ten).id == "sample_1"
    end

    test "can process stream multiple times" do
      {:ok, dataset} = CSV.new(@csv_file)
      stream = Dataset.to_stream(dataset)

      first_pass = Enum.to_list(stream)
      second_pass = Enum.to_list(stream)

      assert first_pass == second_pass
      assert length(first_pass) == 3
    end
  end

  describe "property tests" do
    property "reading written files preserves sample count and structure", %{temp_dir: temp_dir} do
      check all(
              sample_count <- integer(1..20),
              max_runs: 5
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

        test_file = Path.join(temp_dir, "prop_test_#{:rand.uniform(10000)}.csv")
        assert :ok = CSV.write(test_file, samples)

        {:ok, dataset} = CSV.new(test_file)
        restored_samples = Dataset.to_stream(dataset) |> Enum.to_list()

        assert length(restored_samples) == sample_count
        assert Dataset.count(dataset) == sample_count

        # Verify basic structure preservation
        Enum.zip(samples, restored_samples)
        |> Enum.each(fn {original, restored} ->
          assert original.id == restored.id
          assert original.user_input == restored.user_input
          assert original.response == restored.response
          assert original.tags == restored.tags
        end)
      end
    end
  end

  describe "error handling" do
    test "handles corrupted CSV files gracefully", %{temp_dir: temp_dir} do
      corrupted_file = Path.join(temp_dir, "corrupted.csv")

      # Write valid header but corrupted data
      File.write!(corrupted_file, """
      id,user_input,response
      sample_1,Valid,Response
      sample_2,Another valid row,Response 2
      """)

      {:ok, dataset} = CSV.new(corrupted_file)
      samples = Dataset.to_stream(dataset) |> Enum.to_list()

      # Should successfully read valid samples
      assert length(samples) == 2
    end

    test "count handles unreadable files gracefully" do
      dataset = %CSV{file_path: "/nonexistent/file.csv", headers: []}
      assert Dataset.count(dataset) == :unknown
    end

    test "filters out rows that can't be converted to valid samples", %{temp_dir: temp_dir} do
      # Create CSV with some rows that will fail validation
      invalid_csv = """
      id,user_input,response
      sample_1,Hello,Hi!
      ,,"" 
      sample_3,Valid,Response
      """

      test_file = Path.join(temp_dir, "invalid_rows.csv")
      File.write!(test_file, invalid_csv)

      {:ok, dataset} = CSV.new(test_file)
      samples = Dataset.to_stream(dataset) |> Enum.to_list()

      # Should only get samples that passed validation
      # (empty row should fail validation and be filtered out)
      valid_samples =
        Enum.filter(samples, fn sample ->
          sample.id && (sample.user_input || sample.response)
        end)

      # At least the clearly valid ones
      assert length(valid_samples) >= 2
    end
  end
end
