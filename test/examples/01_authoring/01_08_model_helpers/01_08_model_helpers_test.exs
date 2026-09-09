defmodule JidoAI.Examples.ModelHelpersTest do
  use ExUnit.Case, async: false
  import JidoAI.Examples.Case
  alias Jido.AI.Models
  alias JidoAI.Examples.MockLLM
  @moduletag :example

  setup do
    saved =
      for key <- [:model_aliases, :llm_defaults], do: {key, Application.fetch_env(:jido_ai, key)}

    on_exit(fn ->
      Enum.each(saved, fn
        {key, {:ok, value}} -> Application.put_env(:jido_ai, key, value)
        {key, :error} -> Application.delete_env(:jido_ai, key)
      end)
    end)

    Application.put_env(:jido_ai, :model_aliases, %{example: MockLLM.model()})
    Application.delete_env(:jido_ai, :llm_defaults)
    :ok
  end

  test "defaults retain built-in values and merge each configured generation kind" do
    assert Models.llm_defaults(:text).model == :fast
    assert Models.llm_defaults(:object).model == :thinking
    assert Models.llm_defaults(:stream).timeout == 30_000

    Application.put_env(:jido_ai, :llm_defaults, %{
      text: %{temperature: 0.7},
      stream: %{max_tokens: 2_048}
    })

    assert Models.llm_defaults(:text).temperature == 0.7
    assert Models.llm_defaults(:text).timeout == 30_000
    assert Models.llm_defaults(:stream).max_tokens == 2_048
    assert Models.llm_defaults(:stream).model == :fast

    assert_raise ArgumentError, ~r/Unknown LLM defaults kind/, fn ->
      Models.llm_defaults(:missing)
    end
  end

  @tag history_case: "HIST-01/stream-headers"
  test "text helpers retain option precedence, context, headers and raw response usage" do
    Application.put_env(:jido_ai, :llm_defaults, %{
      text: %{model: :example, temperature: 0.1, max_tokens: 32}
    })

    {mock, _} = mock([%{reply: {:text, "Ready"}}])

    options =
      MockLLM.options(mock)
      |> Keyword.put(:system_prompt, "Use the case facts.")
      |> Keyword.put(:temperature, 0.2)
      |> Keyword.put(:max_tokens, 48)
      |> Keyword.put(:opts, temperature: 0.3)
      |> Keyword.update!(:req_http_options, &Keyword.put(&1, :headers, [{"x-case", "helpers"}]))

    assert {:ok, response} = Models.generate_text("Help", options)
    assert ReqLLM.Response.text(response) == "Ready"
    assert response.usage.total_tokens == 15
    assert [request] = MockLLM.report(mock).requests
    assert request.body["temperature"] == 0.3
    assert (request.body["max_tokens"] || request.body["max_completion_tokens"]) == 48
    assert request.headers["x-case"] == "helpers"

    assert request.body["messages"] == [
             %{"role" => "system", "content" => "Use the case facts."},
             %{"role" => "user", "content" => "Help"}
           ]

    assert_script_done(mock)
  end

  test "object helpers keep their schema and raw ReqLLM response contract" do
    Application.put_env(:jido_ai, :llm_defaults, %{object: %{model: :example}})
    {mock, _} = mock([%{reply: {:object, %{answer: "Object"}}}])
    schema = Zoi.object(%{answer: Zoi.string()})

    assert {:ok, %ReqLLM.Response{} = response} =
             Models.generate_object("Extract", schema, MockLLM.options(mock))

    assert ReqLLM.Response.object(response) in [%{answer: "Object"}, %{"answer" => "Object"}]
    assert [request] = MockLLM.report(mock).requests
    assert request.body["response_format"]["type"] == "json_schema"
    assert_script_done(mock)
  end

  @tag history_case: "HIST-01/stream-headers"
  test "stream helpers keep SSE, request headers and usage" do
    Application.put_env(:jido_ai, :llm_defaults, %{stream: %{model: :example}})
    {mock, _} = mock([%{reply: {:text, ["First", " second"]}}])

    options =
      MockLLM.options(mock)
      |> Keyword.update!(:req_http_options, &Keyword.put(&1, :headers, [{"x-case", "stream"}]))

    assert {:ok, stream} = Models.stream_text("Stream", options)

    try do
      assert ReqLLM.StreamResponse.text(stream) == "First second"
      assert ReqLLM.StreamResponse.usage(stream).total_tokens == 15
      assert [request] = MockLLM.report(mock).requests
      assert request.headers["x-case"] == "stream"
      assert_script_done(mock)
    after
      ReqLLM.StreamResponse.close(stream)
    end
  end

  test "rich aliases share resolution, labels and fingerprints with direct model records" do
    model = MockLLM.model()
    assert Models.resolve_model(:example) == model
    assert Models.resolve_model(model) == model
    assert Models.model_label(:example) == Models.model_label(model)
    assert Models.model_fingerprint_segment(:example) == Models.model_fingerprint_segment(model)
    assert is_map(Models.provider_opt_keys(:example))
    assert_raise ArgumentError, ~r/Unknown model alias/, fn -> Models.resolve_model(:missing) end
    assert_raise ArgumentError, ~r/invalid model input/, fn -> Models.resolve_model(42) end
  end

  test "invalid input and provider errors retain tagged failures" do
    {mock, _} = mock([%{reply: {:error, 400, "Bad request"}}])
    options = Keyword.put(MockLLM.options(mock), :model, :example)
    assert {:error, _} = Models.generate_text(42, options)
    assert MockLLM.report(mock).requests == []
    assert {:error, _} = Models.generate_text("Rejected", options)
    assert_script_done(mock)
  end
end
