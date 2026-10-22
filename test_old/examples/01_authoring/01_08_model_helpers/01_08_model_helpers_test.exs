defmodule JidoAI.Examples.ModelHelpersTest do
  use ExUnit.Case, async: false
  import JidoAI.Examples.Case
  alias Jido.AI.Models
  alias JidoAI.Examples.MockLLM
  @moduletag :example

  setup do
    saved = Application.fetch_env(:jido_ai, :model_aliases)

    on_exit(fn ->
      case saved do
        {:ok, value} -> Application.put_env(:jido_ai, :model_aliases, value)
        :error -> Application.delete_env(:jido_ai, :model_aliases)
      end
    end)

    Application.put_env(:jido_ai, :model_aliases, %{example: MockLLM.model()})
    :ok
  end

  test "aliases add application names without hiding ReqLLM model inputs" do
    model = MockLLM.model()

    assert Models.aliases().example == model
    assert Models.resolve(:example) == model
    assert Models.resolve(model) == model
    assert Models.resolve({:openai, "gpt-4.1", []}) == {:openai, "gpt-4.1", []}
    assert_raise ArgumentError, ~r/Unknown model alias/, fn -> Models.resolve(:missing) end

    assert_raise ArgumentError, ~r/Expected a valid ReqLLM model input/, fn ->
      apply(Models, :resolve, [42])
    end
  end

  @tag history_case: "HIST-01/stream-headers"
  test "text generation uses the resolved alias with the native ReqLLM API" do
    {mock, _context} = mock([%{reply: {:text, "Ready"}}])

    options =
      MockLLM.options(mock)
      |> Keyword.put(:temperature, 0.3)
      |> Keyword.put(:max_tokens, 48)
      |> Keyword.update!(:req_http_options, &Keyword.put(&1, :headers, [{"x-case", "helpers"}]))

    messages = [
      ReqLLM.Context.system("Use the case facts."),
      ReqLLM.Context.user("Help")
    ]

    assert {:ok, response} = ReqLLM.generate_text(Models.resolve(:example), messages, options)
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

  test "structured generation stays on the native ReqLLM contract" do
    {mock, _context} = mock([%{reply: {:object, %{answer: "Object"}}}])
    schema = Zoi.object(%{answer: Zoi.string()})

    assert {:ok, %ReqLLM.Response{} = response} =
             ReqLLM.generate_object(
               Models.resolve(:example),
               "Extract",
               schema,
               MockLLM.options(mock)
             )

    assert ReqLLM.Response.object(response) in [%{answer: "Object"}, %{"answer" => "Object"}]
    assert [request] = MockLLM.report(mock).requests
    assert request.body["response_format"]["type"] == "json_schema"
    assert_script_done(mock)
  end

  @tag history_case: "HIST-01/stream-headers"
  test "streaming stays on the native ReqLLM stream contract" do
    {mock, _context} = mock([%{reply: {:text, ["First", " second"]}}])

    options =
      MockLLM.options(mock)
      |> Keyword.update!(:req_http_options, &Keyword.put(&1, :headers, [{"x-case", "stream"}]))

    assert {:ok, stream} = ReqLLM.stream_text(Models.resolve(:example), "Stream", options)

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

  test "provider errors keep the native ReqLLM tagged result" do
    {mock, _context} = mock([%{reply: {:error, 400, "Bad request"}}])

    assert {:error, _error} =
             ReqLLM.generate_text(
               Models.resolve(:example),
               "Rejected",
               MockLLM.options(mock)
             )

    assert_script_done(mock)
  end
end
