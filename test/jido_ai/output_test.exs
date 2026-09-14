defmodule Jido.AI.OutputTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Output

  @schema Zoi.object(%{
            category: Zoi.enum([:billing, :technical, :account]),
            confidence: Zoi.float() |> Zoi.default(1.0),
            summary: Zoi.string()
          })

  defmodule StructuredOutputAgent do
    use Jido.AI.Agent, name: "structured_output_test_agent"

    agent do
      schema Zoi.object(%{last_result: Zoi.any() |> Zoi.default(nil)})

      ai :assistant do
        model(:fast)
        reasoning(:react)
        requests(mode: :session)

        result(
          Zoi.object(%{
            category: Zoi.enum([:billing, :technical, :account]),
            confidence: Zoi.float(),
            summary: Zoi.string()
          }),
          into: :last_result
        )
      end
    end

    routes do
      route("ai.react.query", ai: :assistant)
    end
  end

  defmodule RepairCallback do
    @moduledoc false

    def repair(_output, _raw, _reason, _context) do
      {:ok, %{"category" => "technical", "summary" => "Normalized"}}
    end

    def repair_three(_output, _raw, _reason) do
      {:ok, %{"category" => "account", "summary" => "Three arguments"}}
    end

    def raise_error(_output, _raw, _reason, _context) do
      raise "repair callback failed"
    end
  end

  test "agent macro accepts structured output config" do
    assert function_exported?(StructuredOutputAgent, :ask_sync, 3)
  end

  test "parses JSON text and validates through Zoi with normalized keys and atom enums" do
    {:ok, output} = Output.new(schema: @schema)

    assert {:ok, parsed} =
             Output.parse(output, ~s({"category":"billing","confidence":0.91,"summary":"Refund request"}))

    assert parsed == %{category: :billing, confidence: 0.91, summary: "Refund request"}
  end

  test "normalizes string keys in arrays of Zoi objects" do
    schema =
      Zoi.object(%{
        items:
          Zoi.array(
            Zoi.object(%{
              category: Zoi.enum([:billing, :technical]),
              summary: Zoi.string()
            })
          )
      })

    {:ok, output} = Output.new(schema: schema)

    assert {:ok, %{items: [%{category: :billing, summary: "Refund request"}]}} =
             Output.parse(
               output,
               ~s({"items":[{"category":"billing","summary":"Refund request"}]})
             )
  end

  test "parses fenced JSON text" do
    {:ok, output} = Output.new(schema: @schema)

    assert {:ok, parsed} =
             Output.parse(output, """
             ```JSON
             {"category":"account","confidence":0.82,"summary":"Password reset"}
             ```
             """)

    assert parsed.category == :account
  end

  test "applies Zoi defaults and returns structured output validation errors" do
    {:ok, output} = Output.new(schema: @schema)

    assert {:ok, %{category: :technical, confidence: 1.0, summary: "Login is failing"}} =
             Output.validate(output, %{"category" => "technical", "summary" => "Login is failing"})

    assert {:error, %Jido.AI.Error.Validation.Output{} = error} = Output.parse(output, "not json")
    assert error.field == :output
    assert error.details.reason |> elem(0) == :parse
    assert error.details.raw_preview == "not json"
  end

  test "normalizes retry bounds and validation modes" do
    assert {:ok, %Output{retries: 3}} = Output.new(schema: @schema, retries: 10)
    assert {:ok, %Output{on_validation_error: :error}} = Output.new(schema: @schema, on_validation_error: "error")
    assert {:error, _reason} = Output.new(schema: @schema, retries: -1)
    assert {:error, _reason} = Output.new(schema: @schema, on_validation_error: :retry_forever)
    assert {:error, _reason} = Output.new(schema: Zoi.string())
  end

  test "accepts a string-keyed JSON Schema (as decoded from JSON over the wire)" do
    json_schema = %{
      "type" => "object",
      "properties" => %{"summary" => %{"type" => "string"}},
      "required" => ["summary"]
    }

    assert Output.imported_schema?(json_schema)
    assert {:ok, %Output{schema_kind: :json_schema}} = Output.new(schema: json_schema)
  end

  test "adds structured output instructions to message lists" do
    {:ok, output} = Output.new(schema: @schema)

    messages =
      [%{role: :user, content: "Classify this"}]
      |> Output.apply_instructions(output)

    assert [%{role: :system, content: prompt}, %{role: :user, content: "Classify this"}] = messages
    assert prompt =~ "Structured output:"
    assert prompt =~ "Return the final answer as a single JSON object"
    assert prompt =~ "category"
  end

  test "appends structured output instructions to string-key system messages" do
    {:ok, output} = Output.new(schema: @schema)

    messages =
      [%{"role" => "system", "content" => "Base prompt"}, %{"role" => "user", "content" => "Classify this"}]
      |> Output.apply_instructions(output)

    assert [%{"role" => "system", "content" => prompt}, %{"role" => "user"}] = messages
    assert prompt =~ "Base prompt"
    assert prompt =~ "Structured output:"
  end

  test "redacts sensitive keys in metadata previews" do
    assert Output.raw_preview(%{api_key: "secret", nested: %{token: "hidden"}, ok: "visible"}) =~ "[REDACTED]"
    refute Output.raw_preview(%{api_key: "secret"}) =~ "secret"
  end

  test "uses a configured repair callback from the runner call path" do
    assert {:ok, output} =
             Output.new(
               schema: @schema,
               repair_fun: &RepairCallback.repair/4
             )

    assert output.repair_fun == {RepairCallback, :repair}
    assert :erlang.binary_to_term(:erlang.term_to_binary(output), [:safe]) == output

    assert {:ok, %{category: :technical, confidence: 1.0, summary: "Normalized"}} =
             Output.repair(output, "invalid", :invalid, %{})
  end

  test "builds a sanitized repair request and preserves explicit messages" do
    request =
      Output.repair_request("invalid answer", :invalid, %{
        model: :capable,
        user_message: "Classify the ticket",
        llm_opts: [tools: [:tool], tool_choice: :auto, stream: true, temperature: 0.2]
      })

    assert request.model == :capable
    assert request.tools == %{}
    assert request.llm_opts[:stream] == false
    assert request.llm_opts[:temperature] == 0.2
    refute Keyword.has_key?(request.llm_opts, :tools)
    refute Keyword.has_key?(request.llm_opts, :tool_choice)

    assert Enum.any?(request.messages, fn message ->
             message.role == :user and
               message.content =~ "Classify the ticket" and
               message.content =~ "invalid answer"
           end)

    messages = [%{role: :user, content: "Policy-adjusted repair prompt"}]
    assert Output.repair_request("invalid answer", :invalid, %{messages: messages}).messages == messages
  end

  test "covers constructor identity, nil, coercion, and raising forms" do
    assert {:ok, nil} = Output.new(nil)
    assert {:ok, output} = Output.new(schema: @schema, retries: "2", on_validation_error: "repair")
    assert {:ok, ^output} = Output.new(output)
    assert Output.new!(output) == output
    assert {:error, _} = Output.new(:invalid)
    assert {:error, _} = Output.new(schema: @schema, retries: "two")
    assert {:error, _} = Output.new(schema: @schema, retries: 1.5)
    assert {:error, _} = Output.new(schema: @schema, repair_fun: {String, :missing})
    assert {:error, _} = Output.new(schema: @schema, repair_fun: :invalid)
    assert_raise ArgumentError, fn -> apply(Output, :new!, [:invalid]) end
  end

  test "validates imported schemas and rejects unsupported raw values" do
    schema = %{type: :object, properties: %{answer: %{type: :string}}, required: [:answer]}
    assert {:ok, output} = Output.new(schema: schema)
    assert Output.json_schema(output) == schema
    assert {:ok, %{"answer" => "yes"}} = Output.validate(output, %{"answer" => "yes"})
    assert {:error, %Jido.AI.Error.Validation.Output{}} = Output.validate(output, %{"answer" => 42})
    assert {:error, %Jido.AI.Error.Validation.Output{}} = Output.validate(output, :not_a_map)
    assert {:error, %Jido.AI.Error.Validation.Output{}} = Output.parse(output, 42)
    assert {:error, %Jido.AI.Error.Validation.Output{}} = Output.parse(output, "[1,2]")

    assert {:ok, %{"answer" => "wrapped"}} =
             Output.parse(output, %{"object" => %{"answer" => "wrapped"}})

    refute Output.imported_schema?(%{type: :object})
    refute Output.imported_schema?(:object)
  end

  test "applies no instructions for nil and joins an empty atom-keyed system prompt" do
    messages = [%{role: :user, content: "hello"}]
    assert Output.apply_instructions(messages, nil) == messages

    assert {:ok, output} = Output.new(schema: @schema)
    assert [%{role: :system, content: prompt}] = Output.apply_instructions([%{role: :system, content: ""}], output)
    assert String.starts_with?(prompt, "Structured output:")
  end

  test "builds stable fingerprints and sanitized status metadata" do
    assert Output.fingerprint(nil) == ""
    assert {:ok, output} = Output.new(schema: @schema)
    assert is_binary(Output.fingerprint(output))
    assert byte_size(Output.fingerprint(output)) > 20
    assert Output.raw_preview(String.duplicate("a", 600)) == String.duplicate("a", 500)

    error = %Jido.AI.Error.Validation.Output{field: :output, details: %{token: "secret", reason: :bad}}

    meta =
      Output.meta(output, :invalid, %{token: "secret"},
        attempt: 2,
        error: error,
        validation_error: :bad_shape
      )

    assert meta.attempt == 2
    assert meta.error.token == "[REDACTED]"
    assert meta.validation_error == ":bad_shape"

    failed = Output.mark_failed(meta, RuntimeError.exception("failed"))
    assert failed.status == :error
    assert failed.error =~ "failed"
    refute Map.has_key?(failed, :validation_error)
  end

  test "supports arity-three repair callbacks and contains callback exceptions" do
    assert {:ok, output} = Output.new(schema: @schema, repair_fun: &RepairCallback.repair_three/3)

    assert {:ok, %{category: :account, summary: "Three arguments"}} =
             Output.repair(output, "invalid", :bad_shape, %{})

    assert {:ok, raising} = Output.new(schema: @schema, repair_fun: &RepairCallback.raise_error/4)

    assert {:error, %Jido.AI.Error.Validation.Output{details: %{reason: {:repair_exception, message}}}} =
             Output.repair(raising, "invalid", :bad_shape, %{})

    assert message == "repair callback failed"
  end

  test "default repair returns a structured error when no model is available" do
    assert {:ok, output} = Output.new(schema: @schema)

    assert {:error, %Jido.AI.Error.Validation.Output{details: %{reason: :missing_repair_model}}} =
             Output.repair(output, "invalid", :bad_shape, %{})

    assert {:error, %Jido.AI.Error.Validation.Output{details: %{reason: :missing_repair_model}}} =
             Output.repair(output, "invalid", :bad_shape, %{}, repair_fun: :invalid)
  end
end
