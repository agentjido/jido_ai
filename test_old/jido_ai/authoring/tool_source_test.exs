defmodule Jido.AI.Authoring.ToolSourceTest do
  use ExUnit.Case, async: true

  alias Jido.AI.ToolSource

  defmodule SourceModule do
  end

  @registries %{
    ash_resources: %{"resource" => SourceModule},
    catalogs: %{"catalog" => SourceModule},
    skills: %{"skill" => SourceModule},
    agents: %{"agent" => SourceModule}
  }

  test "normalizes portable references, context policies, names, and defaults" do
    assert ToolSource.kinds() == [
             :ash_resource,
             :mcp_tools,
             :browser,
             :catalog,
             :skill,
             :load_path,
             :subagent,
             :handoff
           ]

    assert ToolSource.source_input?(%{"kind" => "browser", "name" => "docs"})
    refute ToolSource.source_input?(%{"kind" => "action"})
    refute ToolSource.source_input?(:browser)

    assert {:ok, [source]} =
             ToolSource.new(
               [
                 %{
                   "kind" => "subagent",
                   "ref" => "agent",
                   "as" => "research",
                   "forward_context" => %{"except" => ["credential"]},
                   "result" => "content"
                 }
               ],
               @registries
             )

    assert source.ref == SourceModule
    assert source.as == "research"
    assert source.forward_context == {:except, [:credential]}
    assert source.result == :content
    assert source.timeout == 30_000
  end

  test "supports keyword source data and write browsers with approval" do
    assert {:ok, [source]} =
             ToolSource.new([
               [
                 kind: :browser,
                 name: :operator,
                 mode: "read_write",
                 allow: ["https://example.com"],
                 approval: true,
                 idempotency: "unsafe_once"
               ]
             ])

    assert source.ref == "operator"
    assert source.mode == :read_write
    assert source.idempotency == :unsafe_once
  end

  test "rejects duplicate, malformed, unavailable, and unsafe source declarations" do
    browser = %{kind: :browser, name: :docs}
    assert {:error, _} = ToolSource.new([browser, browser])
    assert {:error, _} = ToolSource.new(:browser)
    assert {:error, _} = ToolSource.new([:browser])
    assert {:error, _} = ToolSource.new([["not", "keywords"]])
    assert {:error, _} = ToolSource.new([%{kind: :unknown, ref: "value"}])
    assert {:error, _} = ToolSource.new([%{kind: 42, ref: "value"}])
    assert {:error, _} = ToolSource.new([%{kind: :load_path, path: ""}])
    assert {:error, _} = ToolSource.new([%{kind: :catalog, ref: "missing"}], @registries)
    assert {:error, _} = ToolSource.new([%{kind: :catalog, ref: "catalog"}], %{catalogs: []})
    assert {:error, _} = ToolSource.new([%{kind: :catalog, ref: "catalog"}])
    assert {:error, _} = ToolSource.new([%{kind: :catalog, catalog: DoesNotExist}])

    assert {:error, _} =
             ToolSource.new([
               [kind: :browser, name: :docs, mode: :read_only, mode: :read_write, approval: true]
             ])

    assert {:error, _} =
             ToolSource.new([
               %{kind: :browser, name: :writer, mode: :read_write, allow: ["https://example.com"]}
             ])

    assert {:error, _} =
             ToolSource.new([
               %{kind: :browser, name: :docs, mode: :read_only, allow: [:not_a_url]}
             ])
  end

  test "rejects invalid source-specific limits and static data" do
    invalid = [
      %{kind: :ash_resource, resource: SourceModule, actions: :all},
      %{kind: :mcp_tools, endpoint: :github, discover: :yes},
      %{kind: :catalog, catalog: SourceModule, max_calls: 0},
      %{kind: :subagent, agent: SourceModule, timeout: 0},
      %{kind: :subagent, agent: SourceModule, result: :unknown},
      %{kind: :browser, name: :docs, forward_context: %{only: ["not_registered_field"]}},
      %{kind: :browser, name: :docs, forward_context: %{invalid: []}},
      %{kind: :browser, name: :docs, forward_context: {:only, [42]}},
      %{kind: :browser, name: :docs, idempotency: :unknown},
      %{kind: :browser, name: :docs, mode: :unknown},
      %{kind: :browser, name: :docs, metadata: %{pid: self()}}
    ]

    for source <- invalid do
      assert {:error, _} = ToolSource.new([source])
    end
  end
end
