defmodule ReqLLM.Coverage.Anthropic.CoreNewTest do
  @moduledoc """
  First consolidated Anthropics test.
  Uses the LiveFixture helper so it works in both offline (fixture) and
  LIVE=true modes.
  """

  use ExUnit.Case, async: false

  alias ReqLLM.Test.LiveFixture, as: ReqFixture
  import ReqFixture

  @moduletag :coverage
  @moduletag :anthropic

  @model "anthropic:claude-3-haiku-20240307"

  test "basic completion without system prompt" do
    result =
      use_fixture(:anthropic, "basic_completion", fn ->
        ctx = ReqLLM.Context.new([ReqLLM.Context.user("Hello!")])
        ReqLLM.generate_text(@model, ctx, max_tokens: 5)
      end)

    {:ok, resp} = result
    text = ReqLLM.Response.text(resp)

    assert is_binary(text)
    assert text != ""
    assert resp.id != nil
  end

  test "completion with system prompt" do
    result =
      use_fixture(:anthropic, "system_prompt_completion", fn ->
        ctx =
          ReqLLM.Context.new([
            ReqLLM.Context.system("You are terse. Reply with ONE word."),
            ReqLLM.Context.user("Greet me")
          ])

        ReqLLM.generate_text(@model, ctx, max_tokens: 5)
      end)

    {:ok, resp} = result
    text = ReqLLM.Response.text(resp)
    assert is_binary(text)
    assert text != ""
    assert resp.id != nil
  end

  test "temperature and sampling parameters" do
    result =
      use_fixture(:anthropic, "sampling_params", fn ->
        ReqLLM.generate_text(
          @model,
          "Count to 3",
          temperature: 0.0,
          top_p: 0.9,
          max_tokens: 10
        )
      end)

    {:ok, resp} = result
    text = ReqLLM.Response.text(resp)
    assert is_binary(text)
    assert text != ""
    assert resp.id != nil
  end

  test "stop sequences" do
    result =
      use_fixture(:anthropic, "stop_sequences", fn ->
        ReqLLM.generate_text(
          @model,
          "Count from 1 to 10, then say STOP",
          stop_sequences: ["STOP"],
          max_tokens: 50
        )
      end)

    {:ok, resp} = result
    text = ReqLLM.Response.text(resp)
    assert is_binary(text)
    assert text != ""
    assert resp.id != nil
    refute String.contains?(text, "STOP")
  end
end
