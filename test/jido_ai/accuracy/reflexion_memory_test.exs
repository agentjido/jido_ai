defmodule Jido.AI.Accuracy.ReflexionMemoryTest do
  use ExUnit.Case, async: false

  alias Jido.AI.Accuracy.ReflexionMemory

  describe "new/1" do
    test "creates memory with ETS storage by default" do
      assert {:ok, memory} = ReflexionMemory.new([])

      assert memory.storage == :ets
      assert is_atom(memory.table_name)
      assert memory.max_entries == 1000
      assert memory.similarity_threshold == 0.7

      ReflexionMemory.stop(memory)
    end

    test "creates memory with custom options" do
      assert {:ok, memory} =
               ReflexionMemory.new(%{
                 storage: :ets,
                 max_entries: 500,
                 similarity_threshold: 0.5
               })

      assert memory.max_entries == 500
      assert memory.similarity_threshold == 0.5

      ReflexionMemory.stop(memory)
    end

    test "creates memory with custom table name" do
      assert {:ok, memory} =
               ReflexionMemory.new(%{
                 storage: :ets,
                 table_name: :my_custom_table
               })

      assert memory.table_name == :my_custom_table

      ReflexionMemory.stop(memory)
    end

    test "creates memory with memory storage" do
      assert {:ok, memory} = ReflexionMemory.new(%{storage: :memory})

      assert memory.storage == :memory
    end

    test "returns error for invalid storage" do
      assert {:error, :invalid_storage} = ReflexionMemory.new(%{storage: :invalid})
    end

    test "returns error for invalid max_entries" do
      assert {:error, :invalid_max_entries} = ReflexionMemory.new(%{max_entries: 0})
    end

    test "returns error for invalid similarity_threshold" do
      assert {:error, :invalid_similarity_threshold} =
               ReflexionMemory.new(%{similarity_threshold: 1.5})
    end
  end

  describe "new!/1" do
    test "returns memory when valid" do
      memory = ReflexionMemory.new!([storage: :ets])

      assert %ReflexionMemory{} = memory

      ReflexionMemory.stop(memory)
    end

    test "raises when invalid" do
      assert_raise ArgumentError, ~r/Invalid ReflexionMemory/, fn ->
        ReflexionMemory.new!([storage: :invalid])
      end
    end
  end

  describe "store/2" do
    test "stores entry with all fields" do
      memory = ReflexionMemory.new!([storage: :ets])

      :ok =
        ReflexionMemory.store(memory, %{
          prompt: "What is 2+2?",
          mistake: "Wrong calculation",
          correction: "2+2 = 4",
          severity: 0.8
        })

      assert ReflexionMemory.count(memory) == 1

      ReflexionMemory.stop(memory)
    end

    test "auto-generates timestamp if not provided" do
      memory = ReflexionMemory.new!([storage: :ets])

      :ok =
        ReflexionMemory.store(memory, %{
          prompt: "Test",
          mistake: "Error",
          correction: "Fix"
        })

      {:ok, entries} = ReflexionMemory.list_entries(memory)

      # ETS returns {key, value} tuples, extract entry
      assert [{_key, %{timestamp: %DateTime{}}}] = entries

      ReflexionMemory.stop(memory)
    end

    test "returns error for entry without prompt" do
      memory = ReflexionMemory.new!([storage: :ets])

      assert {:error, :prompt_required} =
               ReflexionMemory.store(memory, %{
                 mistake: "Error",
                 correction: "Fix"
               })

      ReflexionMemory.stop(memory)
    end

    test "respects max_entries limit" do
      memory = ReflexionMemory.new!([storage: :ets, max_entries: 3])

      # Store 5 entries
      Enum.each(1..5, fn i ->
        :ok =
          ReflexionMemory.store(memory, %{
            prompt: "Question #{i}",
            mistake: "Mistake #{i}",
            correction: "Correction #{i}"
          })
      end)

      # Should only keep 3 (max_entries)
      count = ReflexionMemory.count(memory)
      assert count <= 3

      ReflexionMemory.stop(memory)
    end

    test "extracts keywords from prompt" do
      memory = ReflexionMemory.new!([storage: :ets])

      :ok =
        ReflexionMemory.store(memory, %{
          prompt: "Calculate 15 * 23",
          mistake: "Math error",
          correction: "15 * 23 = 345"
        })

      {:ok, [ets_entry | _]} = ReflexionMemory.list_entries(memory)
      {_key, entry} = ets_entry
      # Symbols are removed during keyword extraction
      assert entry.keywords == ["calculate", "15", "23"]

      ReflexionMemory.stop(memory)
    end
  end

  describe "retrieve_similar/3" do
    test "retrieves entries with similar keywords" do
      memory = ReflexionMemory.new!([storage: :ets, similarity_threshold: 0.5])

      :ok =
        ReflexionMemory.store(memory, %{
          prompt: "Calculate 15 multiplication 23",
          mistake: "Wrong multiplication",
          correction: "15 * 23 = 345"
        })

      # Similar prompt
      {:ok, results} =
        ReflexionMemory.retrieve_similar(memory, "How do I calculate 15 times 23?")

      assert length(results) > 0
      # retrieve_similar returns entry values directly
      assert hd(results).prompt == "Calculate 15 multiplication 23"

      ReflexionMemory.stop(memory)
    end

    test "returns empty list when no similar entries" do
      memory = ReflexionMemory.new!([storage: :ets])

      :ok =
        ReflexionMemory.store(memory, %{
          prompt: "Python programming",
          mistake: "Syntax error",
          correction: "Add colon after def"
        })

      # Dissimilar prompt
      {:ok, results} =
        ReflexionMemory.retrieve_similar(memory, "What is the capital of France?")

      assert results == []

      ReflexionMemory.stop(memory)
    end

    test "respects max_results option" do
      memory = ReflexionMemory.new!([storage: :ets])

      # Store multiple similar entries
      Enum.each(1..5, fn i ->
        :ok =
          ReflexionMemory.store(memory, %{
            prompt: "Calculate 15 * #{i}",
            mistake: "Error #{i}",
            correction: "Fix #{i}"
          })
      end)

      {:ok, results} =
        ReflexionMemory.retrieve_similar(memory, "Calculate 15 * 10", max_results: 2)

      assert length(results) <= 2

      ReflexionMemory.stop(memory)
    end

    test "filters by similarity_threshold" do
      memory = ReflexionMemory.new!([storage: :ets, similarity_threshold: 0.8])

      :ok =
        ReflexionMemory.store(memory, %{
          prompt: "Math problem",
          mistake: "Error",
          correction: "Fix"
        })

      # Dissimilar prompt should not match with high threshold
      {:ok, results} =
        ReflexionMemory.retrieve_similar(memory, "Python programming tutorial")

      assert results == []

      ReflexionMemory.stop(memory)
    end

    test "returns most similar results first" do
      memory = ReflexionMemory.new!([storage: :ets, similarity_threshold: 0.5])

      :ok =
        ReflexionMemory.store(memory, %{
          prompt: "Calculate 15 multiplication 23 math",
          mistake: "Error",
          correction: "Fix"
        })

      {:ok, results} =
        ReflexionMemory.retrieve_similar(memory, "Calculate 15 times 23")

      # Should find the similar entry
      assert length(results) > 0

      ReflexionMemory.stop(memory)
    end
  end

  describe "format_for_prompt/1" do
    test "formats single entry for prompt" do
      entry = %{
        prompt: "What is 2+2?",
        mistake: "Wrong calculation",
        correction: "2+2 = 4"
      }

      formatted = ReflexionMemory.format_for_prompt([entry])

      assert formatted =~ "Past mistakes to learn from"
      assert formatted =~ "Question: What is 2+2?"
      assert formatted =~ "Mistake: Wrong calculation"
      assert formatted =~ "Correction: 2+2 = 4"
    end

    test "formats multiple entries for prompt" do
      entries = [
        %{prompt: "Q1", mistake: "M1", correction: "C1"},
        %{prompt: "Q2", mistake: "M2", correction: "C2"}
      ]

      formatted = ReflexionMemory.format_for_prompt(entries)

      assert formatted =~ "Question: Q1"
      assert formatted =~ "Question: Q2"
      assert formatted =~ "Mistake: M1"
      assert formatted =~ "Mistake: M2"
    end

    test "returns empty string for empty list" do
      formatted = ReflexionMemory.format_for_prompt([])

      assert formatted == ""
    end
  end

  describe "clear/1" do
    test "clears all entries from ETS memory" do
      memory = ReflexionMemory.new!([storage: :ets])

      # Store some entries
      Enum.each(1..3, fn i ->
        :ok =
          ReflexionMemory.store(memory, %{
            prompt: "Q#{i}",
            mistake: "M#{i}",
            correction: "C#{i}"
          })
      end)

      assert ReflexionMemory.count(memory) > 0

      # Clear
      {:ok, cleared_memory} = ReflexionMemory.clear(memory)

      assert ReflexionMemory.count(memory) == 0

      ReflexionMemory.stop(cleared_memory)
    end
  end

  describe "count/1" do
    test "returns zero for empty memory" do
      memory = ReflexionMemory.new!([storage: :ets])

      assert ReflexionMemory.count(memory) == 0

      ReflexionMemory.stop(memory)
    end

    test "returns entry count" do
      memory = ReflexionMemory.new!([storage: :ets])

      :ok =
        ReflexionMemory.store(memory, %{
          prompt: "Q1",
          mistake: "M1",
          correction: "C1"
        })

      :ok =
        ReflexionMemory.store(memory, %{
          prompt: "Q2",
          mistake: "M2",
          correction: "C2"
        })

      assert ReflexionMemory.count(memory) == 2

      ReflexionMemory.stop(memory)
    end
  end

  describe "list_entries/1" do
    test "returns all stored entries" do
      memory = ReflexionMemory.new!([storage: :ets])

      :ok =
        ReflexionMemory.store(memory, %{
          prompt: "Q1",
          mistake: "M1",
          correction: "C1"
        })

      {:ok, entries} = ReflexionMemory.list_entries(memory)

      # ETS returns {key, value} tuples
      assert length(entries) == 1
      {_key, entry} = hd(entries)
      assert entry.prompt == "Q1"

      ReflexionMemory.stop(memory)
    end

    test "returns empty list for empty memory" do
      memory = ReflexionMemory.new!([storage: :ets])

      {:ok, entries} = ReflexionMemory.list_entries(memory)

      assert entries == []

      ReflexionMemory.stop(memory)
    end
  end

  describe "stop/1" do
    test "deletes ETS table" do
      memory = ReflexionMemory.new!([storage: :ets])

      table_name = memory.table_name

      # Table should exist
      assert :ets.whereis(table_name) != :undefined

      :ok = ReflexionMemory.stop(memory)

      # Table should be deleted
      assert :ets.whereis(table_name) == :undefined
    end

    test "is safe to call multiple times" do
      memory = ReflexionMemory.new!([storage: :ets])

      :ok = ReflexionMemory.stop(memory)
      :ok = ReflexionMemory.stop(memory)
    end
  end

  describe "keyword extraction" do
    test "removes stop words from prompts" do
      memory = ReflexionMemory.new!([storage: :ets])

      :ok =
        ReflexionMemory.store(memory, %{
          prompt: "What is the capital of France?",
          mistake: "Error",
          correction: "Paris"
        })

      {:ok, [ets_entry]} = ReflexionMemory.list_entries(memory)
      {_key, entry} = ets_entry

      # Should filter out "what", "is", "the", "of"
      refute "what" in entry.keywords
      refute "is" in entry.keywords
      refute "the" in entry.keywords
      refute "of" in entry.keywords

      # Should keep meaningful words
      assert "capital" in entry.keywords
      assert "france" in entry.keywords

      ReflexionMemory.stop(memory)
    end

    test "handles numbers and symbols" do
      memory = ReflexionMemory.new!([storage: :ets])

      :ok =
        ReflexionMemory.store(memory, %{
          prompt: "Calculate 15 * 23 + 7",
          mistake: "Error",
          correction: "Fix"
        })

      {:ok, [ets_entry]} = ReflexionMemory.list_entries(memory)
      {_key, entry} = ets_entry

      # Symbols are removed during keyword extraction, but numbers are kept
      assert "calculate" in entry.keywords
      assert "15" in entry.keywords
      assert "23" in entry.keywords
      assert "7" in entry.keywords

      ReflexionMemory.stop(memory)
    end
  end

  describe "Jaccard similarity" do
    test "calculates similarity for overlapping keywords" do
      memory = ReflexionMemory.new!([storage: :ets, similarity_threshold: 0.3])

      :ok =
        ReflexionMemory.store(memory, %{
          prompt: "calculate multiplication math",
          mistake: "Error",
          correction: "Fix"
        })

      # Query with some overlap (2 out of 4 keywords = 0.5 similarity)
      {:ok, results} =
        ReflexionMemory.retrieve_similar(memory, "multiplication math problem")

      # Should find the similar entry
      assert length(results) > 0

      ReflexionMemory.stop(memory)
    end

    test "returns empty for no keyword overlap" do
      memory = ReflexionMemory.new!([storage: :ets])

      :ok =
        ReflexionMemory.store(memory, %{
          prompt: "Python code syntax",
          mistake: "Error",
          correction: "Fix"
        })

      {:ok, results} =
        ReflexionMemory.retrieve_similar(memory, "math calculation problem")

      assert results == []

      ReflexionMemory.stop(memory)
    end
  end
end
