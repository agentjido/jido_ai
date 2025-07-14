defmodule JidoTest.AI.PromptOptionsTest do
  use ExUnit.Case, async: true
  doctest Jido.AI.Prompt
  @moduletag :capture_log

  alias Jido.AI.Prompt

  describe "prompt options" do
    test "adds options to a prompt" do
      prompt =
        Prompt.new(:user, "Generate text")
        |> Prompt.with_options(temperature: 0.7, max_tokens: 1000)

      assert prompt.options[:temperature] == 0.7
      assert prompt.options[:max_tokens] == 1000
    end

    test "with_temperature sets temperature option" do
      prompt =
        Prompt.new(:user, "Generate text")
        |> Prompt.with_temperature(0.5)

      assert prompt.options[:temperature] == 0.5
    end

    test "with_max_tokens sets max_tokens option" do
      prompt =
        Prompt.new(:user, "Generate text")
        |> Prompt.with_max_tokens(500)

      assert prompt.options[:max_tokens] == 500
    end

    test "with_top_p sets top_p option" do
      prompt =
        Prompt.new(:user, "Generate text")
        |> Prompt.with_top_p(0.9)

      assert prompt.options[:top_p] == 0.9
    end

    test "with_stop sets stop option with a string" do
      prompt =
        Prompt.new(:user, "Generate text")
        |> Prompt.with_stop("END")

      assert prompt.options[:stop] == ["END"]
    end

    test "with_stop sets stop option with a list" do
      prompt =
        Prompt.new(:user, "Generate text")
        |> Prompt.with_stop(["END", "STOP"])

      assert prompt.options[:stop] == ["END", "STOP"]
    end

    test "with_timeout sets timeout option" do
      prompt =
        Prompt.new(:user, "Generate text")
        |> Prompt.with_timeout(30_000)

      assert prompt.options[:timeout] == 30_000
    end

    test "options are preserved across new versions" do
      prompt =
        Prompt.new(:user, "Hello")
        |> Prompt.with_temperature(0.7)
        |> Prompt.with_max_tokens(500)

      v2 = Prompt.new_version(prompt, fn p -> Prompt.add_message(p, :assistant, "Hi there!") end)

      assert v2.options[:temperature] == 0.7
      assert v2.options[:max_tokens] == 500

      # Verify historical version has options
      {:ok, v1} = Prompt.get_version(v2, 1)
      assert v1.options[:temperature] == 0.7
      assert v1.options[:max_tokens] == 500
    end
  end

  describe "render_with_options/2" do
    test "renders messages with options" do
      prompt =
        Prompt.new(:user, "Generate text")
        |> Prompt.with_temperature(0.7)
        |> Prompt.with_max_tokens(500)
        |> Prompt.with_top_p(0.9)
        |> Prompt.with_stop("END")
        |> Prompt.with_timeout(30_000)

      result = Prompt.render_with_options(prompt)

      assert result[:messages] == [%{role: :user, content: "Generate text"}]
      assert result[:temperature] == 0.7
      assert result[:max_tokens] == 500
      assert result[:top_p] == 0.9
      assert result[:stop] == ["END"]
      assert result[:timeout] == 30_000
    end

    test "applies parameter overrides when rendering with options" do
      prompt =
        Prompt.new(%{
          messages: [
            %{role: :user, content: "Hello <%= @name %>", engine: :eex}
          ],
          params: %{name: "Alice"}
        })
        |> Prompt.with_temperature(0.7)

      result = Prompt.render_with_options(prompt, %{name: "Bob"})

      assert result[:messages] == [%{role: :user, content: "Hello Bob"}]
      assert result[:temperature] == 0.7
    end
  end

  describe "output schema" do
    test "with_output_schema sets output schema" do
      schema =
        NimbleOptions.new!(
          name: [type: :string, required: true],
          age: [type: :integer, required: true]
        )

      prompt =
        Prompt.new(:user, "Generate person data")
        |> Prompt.with_output_schema(schema)

      assert prompt.output_schema == schema
    end

    test "with_new_output_schema creates and sets new schema" do
      schema_spec = [
        name: [type: :string, required: true],
        age: [type: :integer, required: true]
      ]

      prompt =
        Prompt.new(:user, "Generate person data")
        |> Prompt.with_new_output_schema(schema_spec)

      assert prompt.output_schema != nil

      # Test schema works
      valid_data = [name: "John", age: 30]
      invalid_data = [name: "John", age: "thirty"]

      assert {:ok, _} = NimbleOptions.validate(valid_data, prompt.output_schema)
      assert {:error, _} = NimbleOptions.validate(invalid_data, prompt.output_schema)
    end

    test "output schema is preserved across versions" do
      schema =
        NimbleOptions.new!(
          name: [type: :string, required: true],
          age: [type: :integer, required: true]
        )

      prompt =
        Prompt.new(:user, "Generate person data")
        |> Prompt.with_output_schema(schema)

      v2 =
        Prompt.new_version(prompt, fn p -> Prompt.add_message(p, :assistant, "Generating...") end)

      assert v2.output_schema == schema

      # Verify historical version has schema
      {:ok, v1} = Prompt.get_version(v2, 1)
      assert v1.output_schema == schema
    end
  end
end
