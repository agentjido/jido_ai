defmodule Jido.AI.OutputTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Output

  @schema Zoi.object(%{
            category: Zoi.enum([:billing, :technical, :account]),
            confidence: Zoi.float() |> Zoi.default(1.0),
            summary: Zoi.string()
          })

  defmodule StructuredOutputAgent do
    use Jido.AI.Agent,
      name: "structured_output_test_agent",
      tools: [],
      output: [
        schema:
          Zoi.object(%{
            category: Zoi.enum([:billing, :technical, :account]),
            confidence: Zoi.float(),
            summary: Zoi.string()
          })
      ]
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
end
