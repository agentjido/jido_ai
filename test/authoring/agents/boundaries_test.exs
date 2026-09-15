Code.require_file("../support/agents/corpus.exs", __DIR__)

defmodule JidoAITest.Authoring.Agents.BoundariesTest do
  use ExUnit.Case, async: false
  @moduletag :authoring
  alias Jido.AI.{Authoring, Profile}
  alias Jido.Agent.{Builder, Codec}
  alias JidoAITest.Authoring.{Compiler, Agents.Corpus}

  for {file, message} <- [
        {"duplicate_profile", "Duplicate profile ID"},
        {"missing_result", "Declare exactly one block"},
        {"unknown_profile", "Unknown AI profile"},
        {"missing_field", "declared domain field"},
        {"duplicate_model", "Duplicate model role"},
        {"history_result", "separate from the result"},
        {"zero_timeout", "timeout"},
        {"mixed_models", "Use one models block or direct model declarations"},
        {"duplicate_routers", "Declare at most one model router"},
        {"conflicting_skill_paths", "Use paths or load_path declarations"},
        {"extensions_not_list", "extensions must be a compile-time list of modules"},
        {"extensions_bad_entry", "extensions must be a compile-time list of modules"}
      ] do
    @tag fixture: file, message: message
    test "invalid source: #{file}", %{fixture: file, message: message} do
      path = Corpus.fixture("invalid/#{file}.exs")
      exception = if file == "zero_timeout", do: Spark.Error.DslError, else: CompileError
      error = assert_raise exception, fn -> Compiler.compile_file(path) end
      assert Exception.message(error) =~ message
    end
  end

  for {field, value} <- [
        {:id, nil},
        {:id, true},
        {:id, false},
        {:controls, %{timeout: 0}},
        {:controls, %{max_iterations: -1}},
        {:models, %{}},
        {:reasoning, %{method: :unknown}},
        {:reasoning, %{model: :missing}},
        {:requests, %{mode: :unknown}},
        {:unknown_option, true},
        {:result, %{into: :reply, max_repairs: -1}}
      ] do
    @tag field: field, value: value
    test "profile boundary #{field}=#{inspect(value)}", %{field: field, value: value} do
      spec = Corpus.load!(:simple)
      source = hd(spec.profiles) |> Map.put(field, value)
      assert {:error, error} = Profile.new(source)
      assert is_exception(error)
      assert {:error, _} = Authoring.lower(spec.attrs, [source])
    end
  end

  test "runtime values cannot enter a portable profile or source document" do
    spec = Corpus.load!(:simple)

    for value <- [self(), make_ref(), fn -> :ok end] do
      source = Map.put(hd(spec.profiles), :metadata, %{"runtime" => value})
      assert {:error, _} = Profile.new(source)
      assert {:error, _} = Authoring.Codec.encode([source], Corpus.registry(spec))
    end
  end

  test "duplicate routes, missing result fields, managed Plugins, and initialized hosts are rejected" do
    spec = Corpus.load!(:simple)
    assert {:error, _} = Authoring.lower(%{spec.attrs | routes: spec.attrs.routes ++ spec.attrs.routes}, spec.profiles)
    assert {:error, _} = Authoring.lower(%{spec.attrs | schema: Zoi.object(%{})}, spec.profiles)
    assert {:error, _} = Authoring.lower(%{spec.attrs | plugins: [{Jido.AI.Runtime.Plugin, []}]}, spec.profiles)
    assert {:error, _} = Authoring.lower(Jido.Agent.instantiate!(Corpus.definition(spec, :map)), spec.profiles)
  end

  test "source JSON rejects wrong versions, extra fields, missing references, and duplicate map keys" do
    spec = Corpus.load!(:simple)
    doc = Corpus.source_document(:simple)
    registry = Corpus.registry(spec)

    for bad <- [
          Map.put(doc, "version", 99),
          Map.put(doc, "type", "unknown"),
          Map.put(doc, "extra", true),
          Map.put(doc, "profiles", [%{"$type" => "atom", "id" => "unknown/new-atom"}]),
          Map.put(doc, "profiles", [%{"$type" => "map", "entries" => [["id", 1], ["id", 2]]}])
        ] do
      assert {:error, error} = Authoring.Codec.decode(spec.attrs, bad, registry)
      assert is_exception(error)
    end

    assert {:error, _} = Authoring.Codec.decode(spec.attrs, doc, %{})
  end

  test "lowered Agent JSON rejects changed target identity and version" do
    spec = Corpus.load!(:simple)
    {:ok, doc, registry} = Codec.encode(Corpus.definition(spec, :map))
    assert {:error, _} = Codec.decode(Map.put(doc, "version", -1), registry)
    [route | rest] = doc["routes"]
    bad = Map.put(doc, "routes", [Map.put(route, "target", "untrusted/action") | rest])
    assert {:error, _} = Codec.decode(bad, registry)
  end

  test "Builder branches preserve AI profiles and retain their first error" do
    spec = Corpus.load!(:multi)
    builder = Builder.new(spec.module)
    original = Builder.build!(builder)
    renamed = builder |> Builder.name("renamed") |> Builder.build!()
    assert renamed === %{original | name: "renamed"}
    assert Builder.build!(builder) === original
    invalid = Builder.name(builder, false)
    assert {:error, error} = Builder.build(invalid)
    assert {:error, ^error} = invalid |> Builder.name("valid") |> Builder.build()
  end

  test "route defaults cannot replace a trusted profile and explicit input wins" do
    spec = Corpus.load!(:multi)

    attrs = %{
      spec.attrs
      | routes: [
          {"case.ask", Authoring.ai(:assistant), defaults: %{profile_id: :reviewer, query: "default", enabled: true}}
        ]
    }

    {:ok, definition} = Authoring.lower(attrs, spec.profiles)
    signal = Jido.Signal.new!("case.ask", %{query: "explicit", enabled: false}, source: "/authoring")

    assert %{id: :assistant, input: %{query: "explicit", enabled: false}} =
             Authoring.request_binding(definition, signal)
  end
end
