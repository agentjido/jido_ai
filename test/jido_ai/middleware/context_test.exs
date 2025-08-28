defmodule Jido.AI.Middleware.ContextTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Middleware.Context
  alias Jido.AI.Model

  defp create_test_model do
    %Model{provider: :openai, model: "gpt-4"}
  end

  defp create_test_context do
    model = create_test_model()
    body = %{messages: [%{role: "user", content: "Hello"}]}
    opts = [temperature: 0.7]

    Context.new(:request, model, body, opts)
  end

  describe "new/4" do
    test "creates context with required fields" do
      model = create_test_model()
      body = %{messages: []}
      opts = [temperature: 0.5]

      context = Context.new(:request, model, body, opts)

      assert context.phase == :request
      assert context.model == model
      assert context.body == body
      assert context.opts == opts
      assert context.meta == %{}
      assert context.private == %{}
    end

    test "creates context with response phase" do
      model = create_test_model()
      body = %{choices: []}
      opts = []

      context = Context.new(:response, model, body, opts)

      assert context.phase == :response
    end
  end

  describe "put_phase/2" do
    test "updates phase" do
      context = create_test_context()

      updated = Context.put_phase(context, :response)

      assert updated.phase == :response
      assert updated.model == context.model
      assert updated.body == context.body
    end
  end

  describe "put_body/2" do
    test "updates body" do
      context = create_test_context()
      new_body = %{choices: [%{message: %{content: "Hi there"}}]}

      updated = Context.put_body(context, new_body)

      assert updated.body == new_body
      assert updated.phase == context.phase
      assert updated.model == context.model
    end
  end

  describe "put_opts/2" do
    test "updates opts" do
      context = create_test_context()
      new_opts = [temperature: 0.9, max_tokens: 100]

      updated = Context.put_opts(context, new_opts)

      assert updated.opts == new_opts
      assert updated.phase == context.phase
      assert updated.model == context.model
    end
  end

  describe "meta operations" do
    test "put_meta/3 adds metadata" do
      context = create_test_context()

      updated = Context.put_meta(context, :request_id, "req-123")

      assert Context.get_meta(updated, :request_id) == "req-123"
    end

    test "put_meta/3 overwrites existing metadata" do
      context =
        create_test_context()
        |> Context.put_meta(:key, "old_value")
        |> Context.put_meta(:key, "new_value")

      assert Context.get_meta(context, :key) == "new_value"
    end

    test "get_meta/2 returns nil for missing keys" do
      context = create_test_context()

      assert Context.get_meta(context, :missing) == nil
    end

    test "get_meta/3 returns default for missing keys" do
      context = create_test_context()

      assert Context.get_meta(context, :missing, "default") == "default"
    end

    test "get_meta/3 returns actual value over default" do
      context = Context.put_meta(create_test_context(), :key, "actual")

      assert Context.get_meta(context, :key, "default") == "actual"
    end

    test "merge_meta/2 combines metadata maps" do
      context =
        create_test_context()
        |> Context.put_meta(:existing, "value")

      merged = Context.merge_meta(context, %{new_key: "new_value", other: 123})

      assert Context.get_meta(merged, :existing) == "value"
      assert Context.get_meta(merged, :new_key) == "new_value"
      assert Context.get_meta(merged, :other) == 123
    end

    test "merge_meta/2 overwrites existing keys" do
      context = Context.put_meta(create_test_context(), :key, "old")

      merged = Context.merge_meta(context, %{key: "new"})

      assert Context.get_meta(merged, :key) == "new"
    end
  end

  describe "private operations" do
    test "put_private/3 adds private data" do
      context = create_test_context()

      updated = Context.put_private(context, :internal_state, %{step: 1})

      assert Context.get_private(updated, :internal_state) == %{step: 1}
    end

    test "put_private/3 overwrites existing private data" do
      context =
        create_test_context()
        |> Context.put_private(:key, "old_value")
        |> Context.put_private(:key, "new_value")

      assert Context.get_private(context, :key) == "new_value"
    end

    test "get_private/2 returns nil for missing keys" do
      context = create_test_context()

      assert Context.get_private(context, :missing) == nil
    end

    test "get_private/3 returns default for missing keys" do
      context = create_test_context()

      assert Context.get_private(context, :missing, "default") == "default"
    end

    test "get_private/3 returns actual value over default" do
      context = Context.put_private(create_test_context(), :key, "actual")

      assert Context.get_private(context, :key, "default") == "actual"
    end

    test "merge_private/2 combines private data maps" do
      context =
        create_test_context()
        |> Context.put_private(:existing, "value")

      merged = Context.merge_private(context, %{new_key: "new_value", other: 123})

      assert Context.get_private(merged, :existing) == "value"
      assert Context.get_private(merged, :new_key) == "new_value"
      assert Context.get_private(merged, :other) == 123
    end

    test "merge_private/2 overwrites existing keys" do
      context = Context.put_private(create_test_context(), :key, "old")

      merged = Context.merge_private(context, %{key: "new"})

      assert Context.get_private(merged, :key) == "new"
    end
  end

  describe "isolation between meta and private" do
    test "meta and private data are separate" do
      context =
        create_test_context()
        |> Context.put_meta(:key, "meta_value")
        |> Context.put_private(:key, "private_value")

      assert Context.get_meta(context, :key) == "meta_value"
      assert Context.get_private(context, :key) == "private_value"
    end
  end
end
