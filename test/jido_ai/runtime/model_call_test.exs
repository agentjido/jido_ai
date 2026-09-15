defmodule Jido.AI.Runtime.ModelCallTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Quota.Store
  alias Jido.AI.Runtime.ModelCall
  alias Jido.AI.Test.MockLLM

  @schema %{type: "object", properties: %{name: %{type: "string"}}, required: ["name"], additionalProperties: false}

  for kind <- [:text, :object, :stream, :stream_object] do
    test "the default #{kind} call uses ReqLLM and its HTTP transport" do
      kind = unquote(kind)
      object? = kind in [:object, :stream_object]
      reply = if object?, do: {:object, %{name: "Ada"}}, else: {:text, "Hello"}
      server = start_supervised!({MockLLM, script: [%{reply: reply}]})
      options = MockLLM.options(server)
      schema = if object?, do: @schema
      messages = [%{role: :user, content: "hello"}]

      assert ModelCall.bind_options(messages, options) == options
      assert {:ok, response} = ModelCall.request(kind, MockLLM.model(), messages, options, schema)

      response =
        if kind in [:stream, :stream_object] do
          try do
            assert {:ok, materialized} = Jido.AI.Usage.Stream.process(response, [])
            materialized
          after
            ReqLLM.StreamResponse.close(response)
          end
        else
          response
        end

      if object?,
        do: assert(response.object == %{"name" => "Ada"}),
        else: assert(ReqLLM.Response.text(response) == "Hello")

      assert %{remaining: [], unexpected: [], requests: [request]} = MockLLM.report(server)
      assert request.body["model"] == "gpt-4o-mini"
    end
  end

  test "the default embedding call uses ReqLLM and its HTTP transport" do
    server = start_supervised!({MockLLM, script: [%{reply: {:embeddings, [[0.1, 0.2]]}}]})

    assert {:ok, response} =
             ModelCall.request(
               :embedding,
               "openai:text-embedding-3-small",
               ["hello"],
               MockLLM.options(server, :embedding)
             )

    assert response == [[0.1, 0.2]]
    assert %{remaining: [], unexpected: [], requests: [request]} = MockLLM.report(server)
    assert request.body["input"] == ["hello"]
  end

  test "a bound callback receives the complete call and can use the default transport" do
    server = start_supervised!({MockLLM, script: [%{reply: {:object, %{name: "Ada"}}}]})
    model = MockLLM.model()
    messages = [%{role: :user, content: "hello"}]
    options = MockLLM.options(server)

    callback = fn call, next ->
      assert call == %{kind: :object, model: model, input: messages, options: options, schema: @schema}
      next.(call.kind, call.model, call.input, call.options, call.schema)
    end

    assert {:ok, %{object: %{"name" => "Ada"}}} =
             ModelCall.request(:object, model, messages, Keyword.put(options, :jido_ai_model_call, callback), @schema)

    assert %{remaining: [], unexpected: []} = MockLLM.report(server)
  end

  test "an explicit callback takes precedence over a caller binder" do
    ModelCall.put_option_binder(fn _, _ -> flunk("explicit options must take precedence") end)
    reason = %{type: :provider_error, message: "unchanged"}
    options = [jido_ai_model_call: fn _, _ -> {:error, reason} end]

    assert ModelCall.bind_options([], options) == options
    assert {:error, ^reason} = ModelCall.request(:text, "unused", [], options)
  end

  test "binding in a Task captures options that survive the binder owner" do
    {owner, captured} =
      Task.async(fn ->
        ModelCall.put_option_binder(fn input, options ->
          Keyword.put(options, :jido_ai_model_call, fn call, _ -> {:ok, {input, call.input}} end)
        end)

        {self(), Task.async(fn -> ModelCall.bind_options(["bound"], []) end) |> Task.await()}
      end)
      |> Task.await()

    refute Process.alive?(owner)
    parent = self()

    spawn(fn ->
      assert ModelCall.bind_options([], []) == []
      send(parent, {:bound_result, ModelCall.request(:text, "unused", ["current"], captured)})
    end)

    assert_receive {:bound_result, {:ok, {["bound"], ["current"]}}}
  end

  test "a callback stays inside quota accounting and admission" do
    store = start_supervised!({Store, name: nil})

    binding = %{
      store: store,
      scope: "model-call",
      window_ms: 60_000,
      enabled: true,
      max_requests: 1,
      max_total_tokens: 100,
      request_id: "request",
      signal_type: "test.query",
      error_message: "quota exceeded"
    }

    options = [jido_ai_model_call: fn _, _ -> {:ok, %{usage: %{total_tokens: 10}}} end]

    assert {:ok, %{usage: %{total_tokens: 10}}} =
             ModelCall.request(:text, "unused", [], options, nil, %{jido_ai_quota: binding})

    assert %{requests: 1, total_tokens: 10} = Store.get(binding.scope, store)
    blocked = [jido_ai_model_call: fn _, _ -> flunk("quota must reject before the call") end]
    assert {:error, _} = ModelCall.request(:text, "unused", [], blocked, nil, %{jido_ai_quota: binding})
    assert %{requests: 1, total_tokens: 10} = Store.get(binding.scope, store)
  end

  test "invalid callbacks return a tagged error" do
    assert {:error, %{type: :invalid_model_call}} =
             ModelCall.request(:text, "unused", [], jido_ai_model_call: :invalid)
  end
end
