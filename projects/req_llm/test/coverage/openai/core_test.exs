defmodule ReqLLM.Coverage.OpenAI.CoreTest do
  @moduledoc """
  Core OpenAI API feature coverage tests.

  Simple, direct tests for basic functionality without complex macros.

  Run with LIVE=true to test against live API and capture fixtures.
  Otherwise uses cached fixtures for fast, reliable testing.
  """
  use ExUnit.Case, async: false

  alias ReqLLM.Test.LiveFixture, as: ReqFixture
  import ReqFixture

  @moduletag :coverage
  @moduletag :openai

  @model "openai:gpt-4o-mini"

  test "basic completion without system prompt" do
    result =
      use_fixture(:openai, "basic_completion", fn ->
        ctx = ReqLLM.Context.new([ReqLLM.Context.user("Hello!")])
        ReqLLM.generate_text(@model, ctx, max_tokens: 5)
      end)

    {:ok, resp} = result
    assert is_binary(resp.body)
    assert resp.body != ""
    assert resp.status == 200
  end

  test "completion with system prompt" do
    result =
      use_fixture(:openai, "system_prompt_completion", fn ->
        ctx =
          ReqLLM.Context.new([
            ReqLLM.Context.system("You are terse. Reply with ONE word."),
            ReqLLM.Context.user("Greet me")
          ])

        ReqLLM.generate_text(@model, ctx, max_tokens: 5)
      end)

    {:ok, resp} = result
    assert is_binary(resp.body)
    assert resp.body != ""
    assert resp.status == 200
  end

  test "temperature parameter" do
    result =
      use_fixture(:openai, "temperature_test", fn ->
        ReqLLM.generate_text(
          @model,
          "Say exactly: TEMPERATURE_TEST",
          temperature: 0.0,
          max_tokens: 10
        )
      end)

    {:ok, resp} = result
    assert is_binary(resp.body)
    assert resp.body != ""
    assert resp.status == 200
  end

  test "max_tokens parameter" do
    result =
      use_fixture(:openai, "max_tokens_test", fn ->
        ReqLLM.generate_text(
          @model,
          "Write a story",
          max_tokens: 5
        )
      end)

    {:ok, resp} = result
    assert is_binary(resp.body)
    assert resp.body != ""
    assert resp.status == 200
    # Should be short due to max_tokens limit
    assert String.length(resp.body) < 100
  end

  test "string prompt (legacy format)" do
    result =
      use_fixture(:openai, "string_prompt", fn ->
        ReqLLM.generate_text(@model, "Hello world!", max_tokens: 5)
      end)

    {:ok, resp} = result
    assert is_binary(resp.body)
    assert resp.body != ""
    assert resp.status == 200
  end
end