defmodule ReqLLM.Coverage.Anthropic.StopSequencesTest do
  use ExUnit.Case, async: true
  alias ReqLLM.Test.LiveFixture

  @moduletag :coverage
  @moduletag :anthropic
  @moduletag :stop_sequences

  describe "stop sequences" do
    test "single stop sequence" do
      model = ReqLLM.Model.from("anthropic:claude-3-haiku-20240307")

      context =
        ReqLLM.Context.new([
          ReqLLM.Message.user("Count from 1 to 10. Use format: Number: X")
        ])

      {:ok, response} =
        LiveFixture.use_fixture("stop_sequences/single_stop", fn ->
          ReqLLM.generate_text(model,
            context: context,
            stop_sequences: ["Number: 5"],
            max_tokens: 200
          )
        end)

      text_content =
        response.chunks
        |> Enum.filter(&(&1.type == :text))
        |> Enum.map(& &1.text)
        |> Enum.join()

      # Should stop before reaching "Number: 5"
      assert text_content =~ "Number: 1"
      assert text_content =~ "Number: 4"
      refute text_content =~ "Number: 5"
      assert response.stop_reason == "stop_sequence"
      assert response.stop_sequence == "Number: 5"
    end

    test "multiple stop sequences" do
      model = ReqLLM.Model.from("anthropic:claude-3-haiku-20240307")

      context =
        ReqLLM.Context.new([
          ReqLLM.Message.user("Write a story. End with either 'THE END' or '--- FINISHED ---'")
        ])

      {:ok, response} =
        LiveFixture.use_fixture("stop_sequences/multiple_stops", fn ->
          ReqLLM.generate_text(model,
            context: context,
            stop_sequences: ["THE END", "--- FINISHED ---"],
            max_tokens: 200
          )
        end)

      text_content =
        response.chunks
        |> Enum.filter(&(&1.type == :text))
        |> Enum.map(& &1.text)
        |> Enum.join()

      # Should contain story content but stop at one of the sequences
      assert String.length(text_content) > 10
      assert response.stop_reason == "stop_sequence"
      assert response.stop_sequence in ["THE END", "--- FINISHED ---"]
    end

    test "maximum 4 stop sequences" do
      model = ReqLLM.Model.from("anthropic:claude-3-haiku-20240307")

      context =
        ReqLLM.Context.new([
          ReqLLM.Message.user("List programming languages, separated by commas")
        ])

      {:ok, response} =
        LiveFixture.use_fixture("stop_sequences/max_four_stops", fn ->
          ReqLLM.generate_text(model,
            context: context,
            # Exactly 4
            stop_sequences: ["Python", "Java", "JavaScript", "Ruby"],
            max_tokens: 100
          )
        end)

      text_content =
        response.chunks
        |> Enum.filter(&(&1.type == :text))
        |> Enum.map(& &1.text)
        |> Enum.join()

      # Should stop at one of the language names
      assert String.length(text_content) > 0

      if response.stop_reason == "stop_sequence" do
        assert response.stop_sequence in ["Python", "Java", "JavaScript", "Ruby"]
      end
    end

    test "stop sequence not reached uses length limit" do
      model = ReqLLM.Model.from("anthropic:claude-3-haiku-20240307")

      context =
        ReqLLM.Context.new([
          ReqLLM.Message.user("Write about programming")
        ])

      {:ok, response} =
        LiveFixture.use_fixture("stop_sequences/not_reached", fn ->
          ReqLLM.generate_text(model,
            context: context,
            stop_sequences: ["NEVER_MENTIONED_PHRASE"],
            max_tokens: 50
          )
        end)

      text_content =
        response.chunks
        |> Enum.filter(&(&1.type == :text))
        |> Enum.map(& &1.text)
        |> Enum.join()

      # Should hit max_tokens limit instead
      assert String.length(text_content) > 10
      assert response.stop_reason == "max_tokens"
      assert is_nil(response.stop_sequence)
    end

    test "empty stop sequences array is ignored" do
      model = ReqLLM.Model.from("anthropic:claude-3-haiku-20240307")

      context =
        ReqLLM.Context.new([
          ReqLLM.Message.user("Say hello")
        ])

      {:ok, response} =
        LiveFixture.use_fixture("stop_sequences/empty_array", fn ->
          ReqLLM.generate_text(model,
            context: context,
            stop_sequences: [],
            max_tokens: 20
          )
        end)

      # Should work normally without stop sequences
      text_content =
        response.chunks
        |> Enum.filter(&(&1.type == :text))
        |> Enum.map(& &1.text)
        |> Enum.join()

      assert text_content =~ ~r/hello/i
    end

    test "special characters in stop sequences" do
      model = ReqLLM.Model.from("anthropic:claude-3-haiku-20240307")

      context =
        ReqLLM.Context.new([
          ReqLLM.Message.user("Write JSON: {'name': 'test', 'value': 123}")
        ])

      {:ok, response} =
        LiveFixture.use_fixture("stop_sequences/special_chars", fn ->
          ReqLLM.generate_text(model,
            context: context,
            stop_sequences: ["}"],
            max_tokens: 100
          )
        end)

      text_content =
        response.chunks
        |> Enum.filter(&(&1.type == :text))
        |> Enum.map(& &1.text)
        |> Enum.join()

      # Should stop at first closing brace
      assert text_content =~ "{"

      if response.stop_reason == "stop_sequence" do
        assert response.stop_sequence == "}"
      end
    end
  end

  describe "stop sequences with streaming" do
    test "stop sequence detection in streaming mode" do
      model = ReqLLM.Model.from("anthropic:claude-3-haiku-20240307")

      context =
        ReqLLM.Context.new([
          ReqLLM.Message.user("Count: 1, 2, 3, 4, 5, 6, 7, 8, 9, 10")
        ])

      {:ok, response} =
        LiveFixture.use_fixture("stop_sequences/streaming_stop", fn ->
          ReqLLM.stream_text(model,
            context: context,
            stop_sequences: ["5"],
            max_tokens: 100
          )
        end)

      text_content =
        response.chunks
        |> Enum.filter(&(&1.type == :text))
        |> Enum.map(& &1.text)
        |> Enum.join()

      # Should stop before or at "5"
      assert text_content =~ "1"

      if response.stop_reason == "stop_sequence" do
        assert response.stop_sequence == "5"
      end
    end
  end
end
