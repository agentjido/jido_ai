defmodule Jido.AI.ContextTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Context
  alias Jido.AI.Context.Item
  alias Jido.AI.Thread.Projection

  test "builds one model-call context from the canonical Thread" do
    session = Jido.Session.new(id: "session:context", now: 1)

    {:ok, session} =
      Projection.append(
        session,
        %{role: :user, content: "Earlier request"},
        %{run_id: "earlier"},
        2
      )

    {:ok, session} =
      Projection.append(
        session,
        %{role: :assistant, content: "Earlier answer"},
        %{run_id: "earlier"},
        3
      )

    {:ok, session} =
      Projection.append(
        session,
        %{role: :user, content: "Current request"},
        %{run_id: "current"},
        4
      )

    assert {:ok, context} =
             Context.new(session,
               instructions: "Answer briefly.",
               request_id: "request-1",
               run_id: "current",
               model_call: 1
             )

    assert context.stage == :open
    assert context.source.thread_id == session.thread.id

    assert Enum.map(context.items, &{&1.kind, &1.placement, &1.required}) == [
             {:instruction, :instructions, true},
             {:message, :history, false},
             {:message, :history, false},
             {:message, :input, true}
           ]

    assert Enum.all?(context.items, &is_binary(&1.content_digest))
    assert Enum.count(context.decisions, &(&1.state == :included)) == 3
  end

  test "applies context contributions once and renders stable request order" do
    session = Jido.Session.new(id: "session:context-render", now: 1)

    {:ok, session} =
      Projection.append(session, %{role: :user, content: "Use what you know."}, %{run_id: "run-1"}, 2)

    {:ok, context} =
      Context.new(session,
        instructions: "Be exact.",
        repair_instruction: "Return a complete answer.",
        run_id: "run-1"
      )

    memory = %{
      id: "memory:customer-name",
      kind: :memory,
      content: "The customer name is Ada.",
      source: %{type: :memory, record_id: "customer-name"},
      placement: :knowledge,
      priority: 10
    }

    assert {:ok, with_memory} = Context.add(context, memory, op_id: "recall:customer")
    assert {:ok, ^with_memory} = Context.add(with_memory, memory, op_id: "recall:customer")

    assert {:error, {:context_operation_conflict, "recall:customer"}} =
             Context.add(with_memory, Map.put(memory, :content, "Different"), op_id: "recall:customer")

    assert {:ok, configured} =
             Context.configure(
               with_memory,
               %{model: "openai:gpt-4o-mini", options: %{temperature: 0}},
               op_id: "request:1"
             )

    assert {:error, :invalid_context_request} =
             Context.configure(with_memory, %{modle: "typo"}, op_id: "request:typo")

    before = Context.snapshot(configured, content: :none)
    assert {:ok, prepared} = Context.prepare(configured)
    assert prepared.stage == :prepared
    assert is_binary(prepared.digest)
    assert {:error, :context_not_open} = Context.add(prepared, memory, op_id: "recall:other")

    assert {:ok, request} = Context.ReqLLM.render(prepared)
    assert request.model == "openai:gpt-4o-mini"
    assert request.options[:temperature] == 0

    messages = ReqLLM.Context.to_list(request.context)

    assert Enum.map(messages, & &1.role) == [:system, :system, :user, :system]

    assert Enum.map(messages, &message_text/1) == [
             "Be exact.",
             "The customer name is Ada.",
             "Use what you know.",
             "Return a complete answer."
           ]

    change = Context.diff(before, Context.snapshot(prepared, content: :none))
    assert change.before.stage == :open
    assert change.after.stage == :prepared
    refute change.request_changed
  end

  test "snapshots expose shape, cache request data, usage, and safe content controls" do
    session = Jido.Session.new(id: "session:snapshot", now: 1)
    {:ok, session} = Projection.append(session, %{role: :user, content: "Secret input"}, %{}, 2)

    assert {:ok, context} = Context.new(session, instructions: "System text")

    item =
      Item.new!(%{
        id: "skill:search",
        kind: :skill,
        content: "Search instructions",
        source: %{type: :skill, name: "search"},
        placement: :knowledge
      })

    assert {:ok, context} = Context.add(context, item, op_id: "skill:search")

    assert {:ok, context} =
             Context.configure(
               context,
               %{
                 model: "openai:gpt-4o-mini",
                 options: %{max_tokens: 100, api_key: "do-not-record"},
                 prompt_cache: %{enabled: true, key: "session:snapshot"}
               },
               op_id: "request:snapshot"
             )

    assert {:ok, context} = Context.prepare(context)

    outcome = %{
      status: :ok,
      usage: %{input_tokens: 12, output_tokens: 4, cache_read_tokens: 8},
      prompt_cache: %{requested: true, read_tokens: 8}
    }

    assert {:ok, completed} = Context.complete(context, outcome)

    manifest = completed |> Context.snapshot(content: :none) |> Context.Snapshot.to_map()
    assert manifest.stage == :completed
    assert manifest.shape.included_item_count == 3
    assert manifest.shape.message_count == 3
    assert manifest.usage.input_tokens == 12
    assert manifest.request.options.max_tokens == 100
    assert manifest.request.options.api_key == "[REDACTED]"
    refute Enum.any?(manifest.items, &Map.has_key?(&1, :content))

    full = completed |> Context.snapshot(content: :full) |> Context.Snapshot.to_map()
    assert Enum.any?(full.items, &(&1[:content] == "Secret input"))

    encoded = completed |> Context.snapshot(content: :none) |> Context.Snapshot.encode()
    assert Context.Snapshot.decode!(encoded)["stage"] == "completed"
  end

  test "context item schemas coerce portable string keys" do
    assert {:ok, item} =
             Item.new(%{
               "kind" => "memory",
               "content" => "Known fact",
               "source" => %{"type" => "memory"},
               "placement" => "knowledge"
             })

    assert item.kind == :memory
    assert item.role == :system
    assert item.placement == :knowledge
    assert is_binary(item.id)
    assert is_binary(item.content_digest)
  end

  test "runtime manifests hash tool schemas while full snapshots expose them" do
    {:ok, tool} =
      ReqLLM.Tool.new(
        name: "lookup",
        description: "Look up one record",
        parameter_schema: %{
          "type" => "object",
          "properties" => %{"id" => %{"type" => "string"}},
          "required" => ["id"]
        },
        callback: fn _arguments -> {:error, :not_executable_here} end,
        strict: true
      )

    assert {:ok, context} = Context.new(Jido.Session.new(id: "session:tool-snapshot", now: 1))

    assert {:ok, context} =
             Context.configure(
               context,
               %{model: "openai:gpt-4o-mini", tools: [tool]},
               op_id: "request:tool-snapshot"
             )

    assert {:ok, context} = Context.prepare(context)

    manifest = context |> Context.snapshot(content: :none) |> Context.Snapshot.to_map()
    [manifest_tool] = manifest.request.tools
    assert manifest_tool.name == "lookup"
    assert is_binary(manifest_tool.schema_digest)
    refute Map.has_key?(manifest_tool, :schema)

    full = context |> Context.snapshot(content: :full) |> Context.Snapshot.to_map()
    [full_tool] = full.request.tools
    assert full_tool.schema["function"]["parameters"]["required"] == ["id"]
  end

  test "projection explains failed requests, incomplete exchanges, and window drops" do
    session = Jido.Session.new(id: "session:context-decisions", now: 1)
    {:ok, session} = Projection.append(session, %{role: :user, content: "Old"}, %{run_id: "old"}, 2)

    session =
      Projection.observe(
        session,
        :ai_request_outcome,
        %{status: :failed},
        %{run_id: "old"},
        3
      )

    {:ok, session} = Projection.append(session, %{role: :user, content: "First"}, %{}, 4)

    {:ok, session} =
      Projection.append(
        session,
        %{
          role: :assistant,
          content: "",
          tool_calls: [%{id: "open", name: "lookup", arguments: %{}}]
        },
        %{},
        5
      )

    {:ok, session} = Projection.append(session, %{role: :user, content: "Current"}, %{}, 6)

    assert {:ok, explanation} = Projection.explain(session, %{max_messages: 1})
    assert Enum.map(explanation.messages, & &1.content) == ["Current"]

    assert Enum.map(explanation.decisions, & &1.reason) == [
             :request_not_completed,
             :outside_context_window,
             :incomplete_tool_exchange,
             :projected
           ]
  end

  test "portable rich message content is restored before the ReqLLM call" do
    session = Jido.Session.new(id: "session:rich-context", now: 1)

    content = [
      ReqLLM.Message.ContentPart.text("Inspect this image."),
      ReqLLM.Message.ContentPart.image_url("https://example.com/image.png")
    ]

    assert {:ok, session} = Projection.append(session, %{role: :user, content: content}, %{}, 2)
    assert {:ok, context} = Context.new(session)

    assert {:ok, context} =
             Context.configure(context, %{model: "openai:gpt-4o-mini"}, op_id: "request:rich")

    assert {:ok, context} = Context.prepare(context)
    assert {:ok, request} = Context.ReqLLM.render(context)
    [message] = ReqLLM.Context.to_list(request.context)

    assert Enum.map(message.content, &{&1.type, &1.text, &1.url}) == [
             {:text, "Inspect this image.", nil},
             {:image_url, nil, "https://example.com/image.png"}
           ]
  end

  defp message_text(message) do
    message.content
    |> Enum.filter(&(&1.type == :text))
    |> Enum.map_join(& &1.text)
  end
end
