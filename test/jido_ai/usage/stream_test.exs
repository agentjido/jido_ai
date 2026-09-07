defmodule Jido.AI.Usage.StreamTest do
  use ExUnit.Case, async: true
  alias Jido.AI.Usage.Stream, as: UsageStream
  alias ReqLLM.StreamChunk

  test "processed zero keeps priority over positive metadata and chunks" do
    zero = %{input_tokens: 0, output_tokens: 0, total_tokens: 0}
    assert UsageStream.select(zero, %{total_tokens: 50}, %{total_tokens: 90}) == zero
  end

  test "a sparse processed record wins without borrowing fields from other sources" do
    assert UsageStream.select(%{provider: "001"}, %{total_tokens: 50}, %{total_tokens: 90}) == %{
             provider: "001",
             input_tokens: 0,
             output_tokens: 0,
             total_tokens: 0
           }
  end

  test "metadata precedes chunks and derives a missing total from numeric strings" do
    result =
      UsageStream.select(:unavailable, %{"prompt_tokens" => "3", "completion_tokens" => "1"}, %{total_tokens: 90})

    assert Jido.AI.Usage.token_counts(result) == %{input_tokens: 3, output_tokens: 1, total_tokens: 4}
  end

  test "empty metadata permits chunk fallback" do
    assert UsageStream.select(nil, %{}, %{input_tokens: 3, output_tokens: 1}).total_tokens == 4
  end

  test "unavailable sources do not invent known zero usage" do
    assert UsageStream.select(nil, %{}, :invalid) == nil
  end

  test "chunk counters use independent maxima and other fields use the latest shallow map" do
    result =
      Enum.reduce(
        [
          %{input_tokens: "8", total_tokens: 99, provider: "001", cost: %{first: 1}},
          %{output_tokens: 7, total_tokens: 10, provider: "002", cost: %{second: 2}},
          %{input_tokens: 2, output_tokens: 1, total_tokens: 3}
        ],
        nil,
        &UsageStream.merge(&2, &1)
      )

    assert result == %{input_tokens: 8, output_tokens: 7, total_tokens: 99, provider: "002", cost: %{second: 2}}
    assert UsageStream.merge(result, %{}) == result
    assert UsageStream.merge(result, nil) == result
  end

  test "real materialization retains numeric-string chunks when metadata has no usage" do
    stream =
      stream([
        StreamChunk.text("Yo"),
        StreamChunk.meta(%{usage: %{"prompt_tokens" => "3", "completion_tokens" => "1"}})
      ])

    assert {:ok, response} = UsageStream.process(stream, [])
    assert ReqLLM.Response.text(response) == "Yo"
    assert Jido.AI.Usage.token_counts(response.usage) == %{input_tokens: 3, output_tokens: 1, total_tokens: 4}
    assert_clean()
  end

  test "materialized metadata zero remains authoritative over chunk fallback" do
    stream =
      stream([StreamChunk.meta(%{usage: %{input_tokens: 7, output_tokens: 3}})], %{
        usage: %{input_tokens: 0, output_tokens: 0, total_tokens: 0}
      })

    assert {:ok, %{usage: usage}} = UsageStream.process(stream, [])
    assert usage.input_tokens == 0 and usage.output_tokens == 0 and usage.total_tokens == 0
    assert_clean()
  end

  test "metadata errors remove captured chunks before the next call" do
    stream = stream([StreamChunk.meta(%{usage: %{input_tokens: 7}})], %{error: :failed_stream})
    assert {:error, :failed_stream} = UsageStream.process(stream, [])
    assert_clean()
    assert {:ok, %{usage: nil}} = UsageStream.process(stream([StreamChunk.text("Next")]), [])
    assert_clean()
  end

  test "callback exceptions remove captured usage" do
    stream = stream([StreamChunk.meta(%{usage: %{input_tokens: 7}})])

    assert {:error, %RuntimeError{message: "callback failed"}} =
             UsageStream.process(stream, on_chunk: fn _ -> raise "callback failed" end)

    assert_clean()
  end

  test "uncaught callback throws also remove captured usage" do
    stream = stream([StreamChunk.meta(%{usage: %{input_tokens: 7}})])
    assert catch_throw(UsageStream.process(stream, on_chunk: fn _ -> throw(:callback_stop) end)) == :callback_stop
    assert_clean()
  end

  test "successful consecutive streams do not share counters" do
    for n <- [9, 2] do
      assert {:ok, %{usage: %{total_tokens: ^n}}} =
               UsageStream.process(stream([StreamChunk.meta(%{usage: %{input_tokens: n, output_tokens: 0}})]), [])

      assert_clean()
    end
  end

  defp stream(chunks, metadata \\ %{}) do
    {:ok, model} = ReqLLM.model("openai:gpt-4o-mini")

    {:ok, handle} =
      ReqLLM.StreamResponse.MetadataHandle.start_link(fn -> Map.put_new(metadata, :finish_reason, :stop) end)

    response = %ReqLLM.StreamResponse{
      stream: chunks,
      metadata_handle: handle,
      model: model,
      context: ReqLLM.Context.new([]),
      cancel: fn -> :ok end
    }

    on_exit(fn -> ReqLLM.StreamResponse.close(response) end)
    response
  end

  defp assert_clean do
    refute Enum.any?(Process.get_keys(), &match?({UsageStream, _}, &1))
  end
end
