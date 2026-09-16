Code.require_file("../compiler.exs", __DIR__)
Code.require_file("cases.exs", __DIR__)

defmodule JidoAITest.Authoring.Agents.Corpus do
  @moduledoc false
  alias Jido.Agent.{Builder, Codec}
  alias Jido.AI.Authoring
  alias Jido.AI.Profile
  alias Jido.Codec.Registry
  alias JidoAITest.Authoring.{Compiler, Agents.Cases}
  @fixtures Path.expand("fixtures", __DIR__)

  def variants, do: Cases.variants()
  def forms, do: [:module, :map, :keyword, :profiles, :builder, :module_builder, :source_json, :agent_json]
  def fixture(path), do: Path.join(@fixtures, path)

  def load!(id) do
    Compiler.require_file!(fixture("tools.exs"))
    Compiler.require_file!(fixture("#{id}.exs"))
    Cases.spec(id)
  end

  def definition(spec, :module), do: spec.module.definition()
  def definition(spec, :map), do: lower!(spec.attrs, spec.profiles)
  def definition(spec, :keyword), do: lower!(Map.to_list(spec.attrs), spec.profiles)
  def definition(spec, :profiles), do: lower!(spec.attrs, Enum.map(spec.profiles, &Profile.new!/1))
  def definition(spec, :module_builder), do: Builder.new(spec.module) |> Builder.build!()

  def definition(spec, :builder) do
    # Builder consumes lowered core attributes. It has no AI profile setter.
    lowered = definition(spec, :map)
    attrs = lowered |> Map.from_struct() |> Map.drop([:id, :state, :plugins, :routes])

    builder =
      Enum.reduce(lowered.plugins, Builder.new(attrs), fn {module, opts}, acc ->
        Builder.plugin(acc, module, opts)
      end)

    Enum.reduce(lowered.routes, builder, fn route, acc ->
      Builder.route(acc, route.path, route.target, priority: route.priority, match: route.match)
    end)
    |> Builder.build!()
  end

  def definition(spec, :source_json) do
    document = spec.id |> source_document()
    {:ok, definition} = Authoring.Codec.decode(spec.attrs, document, registry(spec))
    definition
  end

  def definition(spec, :agent_json) do
    {:ok, _document, registry} = Codec.encode(definition(spec, :map))
    {:ok, definition} = Codec.decode(agent_document(spec.id), registry)
    definition
  end

  def agent_document(id), do: fixture("json/#{id}.agent.json") |> File.read!() |> Jason.decode!()

  def source_document(id), do: fixture("json/#{id}.json") |> File.read!() |> Jason.decode!()

  def registry(spec) do
    # Registry discovery supplies trusted identities, never expected behavior.
    values = Enum.map(spec.profiles, &(Profile.new!(&1) |> Map.from_struct()))
    atoms = [:routes | collect_atoms(values ++ spec.profiles)] |> Enum.uniq()
    references = Map.new(atoms, &{"atoms/#{&1}", {:atom, &1}})

    Registry.new!(
      Map.merge(references, %{
        "values/model" => {:value, Jido.AI.Test.MockLLM.model()},
        "values/reviewer" => {:value, Jido.AI.Test.MockLLM.model("gpt-4o")},
        "values/output" => {:value, Cases.output_schema()}
      })
    )
  end

  defp collect_atoms(%_{}), do: []

  defp collect_atoms(value) when is_map(value),
    do: Enum.flat_map(value, fn {k, v} -> collect_atoms(k) ++ collect_atoms(v) end)

  defp collect_atoms(value) when is_list(value), do: Enum.flat_map(value, &collect_atoms/1)
  defp collect_atoms(value) when is_tuple(value), do: value |> Tuple.to_list() |> collect_atoms()
  defp collect_atoms(value) when is_atom(value) and value not in [nil, true, false], do: [value]
  defp collect_atoms(_), do: []

  defp lower!(attrs, profiles) do
    {:ok, definition} = Authoring.lower(attrs, profiles)
    definition
  end
end
