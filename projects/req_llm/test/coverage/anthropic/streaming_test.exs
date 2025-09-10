defmodule ReqLLM.Coverage.Anthropic.StreamingTest do
  @moduledoc """
  Anthropic streaming API coverage tests.
  
  Simple tests for streaming functionality.
  
  Run with LIVE=true to test against live API and capture fixtures.
  """
  use ExUnit.Case, async: false
  
  alias ReqLLM.Test.LiveFixture
  
  @moduletag :coverage
  @moduletag :anthropic
  
  @model "anthropic:claude-3-haiku-20240307"

  test "basic streaming" do
    result = LiveFixture.use_fixture(:anthropic, "basic_streaming", fn ->
      ctx = ReqLLM.Context.new([ReqLLM.Context.user("Say hello")])
      ReqLLM.stream_text(@model, ctx, max_tokens: 10)
    end)

    {:ok, resp} = result
    assert is_function(resp.body) or is_list(resp.body) # Stream can be enumerable
    assert resp.status == 200
  end

  test "streaming with system prompt" do
    result = LiveFixture.use_fixture(:anthropic, "streaming_system_prompt", fn ->
      ctx = ReqLLM.Context.new([
        ReqLLM.Context.system("Reply briefly."),
        ReqLLM.Context.user("Greet me")
      ])
      ReqLLM.stream_text(@model, ctx, max_tokens: 10)
    end)

    {:ok, resp} = result
    assert is_function(resp.body) or is_list(resp.body)
    assert resp.status == 200
  end
end
