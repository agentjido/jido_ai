defmodule JidoAI.APIInventory do
  @moduledoc false
  @root Path.expand("../..", __DIR__)
  @target Path.join(@root, "docs/v3-spike/api-inventory.json")

  def build do
    files =
      @root
      |> Path.join("lib/**/*.ex")
      |> Path.wildcard()
      |> Enum.sort()
      |> Enum.map(&source/1)

    %{
      schema_version: 2,
      scope: "Current declared source under lib; not a compatibility promise or expanded BEAM export list.",
      historical_inventory: "api-inventory-v2.json",
      contract_map: "public-api-map.md",
      generator: "scripts/api_inventory.exs",
      source_digest: digest(Enum.map_join(files, "\n", &(&1.path <> ":" <> &1.sha256))),
      file_count: length(files),
      limits: [
        "No compilation or macro evaluation is used to index source declarations.",
        "Public def/defmacro declarations include implementation helpers; consult the contract map for supported use.",
        "Generated exports from use/derive/DSL macros are not expanded. Quoted templates are marked separately.",
        "Default arities are included; repeated clauses are merged by module, name, kind and quoted status.",
        "Doc attributes are retained as declarations, not interpreted as per-function public API approval.",
        "Source presence and checksums do not establish passing behavior, compatibility, or release readiness."
      ],
      ownership: %{"Jido.Session" => "jido_ai", "Jido.Thread" => "jido_ai", "Jido.Thread.Entry" => "jido_ai"},
      files: files
    }
  end

  def run(args) do
    encoded = Jason.encode!(build(), pretty: true) <> "\n"

    case args do
      [] ->
        File.write!(@target, encoded)
        IO.puts("Updated #{Path.relative_to(@target, @root)}")

      ["--check"] ->
        if Jason.decode!(File.read!(@target)) != Jason.decode!(encoded) do
          Mix.raise("API inventory is stale. Run mix run scripts/api_inventory.exs")
        end

        IO.puts("API inventory matches current lib source")

      _ ->
        Mix.raise("Usage: mix run scripts/api_inventory.exs [--check]")
    end
  end

  defp source(path) do
    text = File.read!(path)
    declarations = declarations(text)

    %{
      path: Path.relative_to(path, @root),
      sha256: digest(text),
      modules: declarations |> Enum.filter(&(&1.kind == "defmodule")) |> Enum.map(& &1.name) |> Enum.uniq(),
      declarations: declarations
    }
  end

  def declarations(text), do: text |> Code.string_to_quoted!(columns: true) |> walk(nil, false) |> merge_clauses()

  defp walk({:defmodule, meta, [name, body]}, owner, quoted) do
    module = module_name(name, owner)
    [entry("defmodule", meta, owner, quoted, %{name: module}) | walk(body, module, quoted)]
  end

  defp walk({:quote, _, args}, owner, _quoted), do: walk(args, owner, true)

  defp walk({kind, meta, [head | rest]}, owner, quoted) when kind in [:def, :defmacro, :defdelegate] do
    case head_name(head) do
      {name, args} ->
        defaults = Enum.count(args, &match?({:\\, _, _}, &1))
        arity = length(args)

        [
          entry(Atom.to_string(kind), meta, owner, quoted, %{
            name: Atom.to_string(name),
            arities: Enum.to_list((arity - defaults)..arity)
          })
          | walk(rest, owner, quoted)
        ]

      nil ->
        walk(rest, owner, quoted)
    end
  end

  defp walk({:@, meta, [{name, _, args}]}, owner, quoted) when name in [:moduledoc, :doc] do
    status =
      case args do
        [false] -> "hidden"
        [text] when is_binary(text) -> "documented"
        _ -> "metadata_or_expression"
      end

    [entry("attribute", meta, owner, quoted, %{name: Atom.to_string(name), status: status})]
  end

  defp walk({:@, meta, [{name, _, args}]}, owner, quoted)
       when name in [:callback, :macrocallback, :behaviour, :derive, :optional_callbacks] do
    [entry("attribute", meta, owner, quoted, %{name: Atom.to_string(name), source: Macro.to_string(args)})]
  end

  defp walk({:defimpl, meta, args}, owner, quoted) do
    header = Enum.reject(args, &(is_list(&1) and Keyword.has_key?(&1, :do)))
    scope = Macro.to_string({:defimpl, [], header})
    [entry("defimpl", meta, owner, quoted, %{source: scope}) | walk(args, scope, quoted)]
  end

  defp walk({kind, meta, args}, owner, quoted) when kind in [:defstruct, :defexception, :use] do
    [entry(Atom.to_string(kind), meta, owner, quoted, %{source: Macro.to_string(args)}) | walk(args, owner, quoted)]
  end

  defp walk({_, _, args}, owner, quoted) when is_list(args), do: walk(args, owner, quoted)
  defp walk(values, owner, quoted) when is_list(values), do: Enum.flat_map(values, &walk(&1, owner, quoted))
  defp walk({left, right}, owner, quoted), do: walk(left, owner, quoted) ++ walk(right, owner, quoted)
  defp walk(_, _, _), do: []

  defp head_name({:when, _, [head | _]}), do: head_name(head)
  defp head_name({name, _, args}) when is_atom(name) and is_list(args), do: {name, args}
  defp head_name({name, _, nil}) when is_atom(name), do: {name, []}
  defp head_name(_), do: nil

  defp module_name({:__aliases__, _, parts}, owner) do
    case parts do
      [{:__MODULE__, _, _} | tail] -> Enum.join([owner | tail], ".")
      [:"Elixir" | tail] -> Enum.join(tail, ".")
      _ when is_nil(owner) -> Enum.join(parts, ".")
      _ -> Enum.join([owner | parts], ".")
    end
  end

  defp module_name({:__MODULE__, _, _}, owner), do: owner
  defp module_name(other, _), do: Macro.to_string(other)

  defp entry(kind, meta, owner, quoted, attrs),
    do: Map.merge(%{kind: kind, line: meta[:line], module: owner, quoted: quoted}, attrs)

  defp merge_clauses(declarations) do
    declarations
    |> Enum.group_by(fn item ->
      if Map.has_key?(item, :arities),
        do: {item.module, item.kind, item.name, item.quoted},
        else: {:declaration, item}
    end)
    |> Enum.map(fn
      {{:declaration, item}, _} ->
        item

      {_, items} ->
        first = Enum.min_by(items, & &1.line)

        Map.merge(first, %{
          arities: items |> Enum.flat_map(& &1.arities) |> Enum.uniq() |> Enum.sort(),
          clause_lines: items |> Enum.map(& &1.line) |> Enum.sort()
        })
    end)
    |> Enum.sort_by(&{&1.line, &1.kind, Map.get(&1, :name, "")})
  end

  defp digest(text), do: :crypto.hash(:sha256, text) |> Base.encode16(case: :lower)
end
