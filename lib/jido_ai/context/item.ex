defmodule Jido.AI.Context.Item do
  @moduledoc "One typed value that can contribute to a model request."

  @fields [
    :id,
    :kind,
    :role,
    :content,
    :name,
    :tool_call_id,
    :tool_calls,
    :output,
    :metadata,
    :source,
    :placement,
    :priority,
    :required,
    :order,
    :state,
    :reason,
    :content_digest
  ]

  @schema Zoi.struct(
            __MODULE__,
            %{
              id: Zoi.string() |> Zoi.min(1),
              kind: Zoi.enum([:message, :memory, :skill, :resource, :instruction, :repair, :custom]),
              role:
                Zoi.enum([:system, :user, :assistant, :tool])
                |> Zoi.nullable()
                |> Zoi.default(nil),
              content: Zoi.any() |> Zoi.default(""),
              name: Zoi.string() |> Zoi.nullable() |> Zoi.default(nil),
              tool_call_id: Zoi.string() |> Zoi.nullable() |> Zoi.default(nil),
              tool_calls: Zoi.list(Zoi.any()) |> Zoi.default([]),
              output: Zoi.any() |> Zoi.default(nil),
              metadata: Zoi.map() |> Zoi.default(%{}),
              source: Zoi.map() |> Zoi.default(%{}),
              placement:
                Zoi.enum([:instructions, :history, :knowledge, :input, :repair])
                |> Zoi.default(:knowledge),
              priority: Zoi.integer() |> Zoi.default(0),
              required: Zoi.boolean() |> Zoi.default(false),
              order: Zoi.integer() |> Zoi.min(0) |> Zoi.default(0),
              state: Zoi.enum([:included, :excluded]) |> Zoi.default(:included),
              reason: Zoi.any() |> Zoi.default(nil),
              content_digest: Zoi.string() |> Zoi.min(1)
            },
            coerce: true,
            unrecognized_keys: :error
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for one context item."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc "Creates and validates one context item."
  @spec new(map() | keyword()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_list(attrs), do: new(Map.new(attrs))

  def new(attrs) when is_map(attrs) do
    attrs =
      attrs
      |> normalize_keys()
      |> normalize_enums()
      |> put_default_role()
      |> Map.put_new(:content, "")
      |> Map.put_new(:content_digest, digest(field(attrs, :content) || ""))
      |> Map.put_new(:id, item_id(attrs))

    Zoi.parse(@schema, attrs)
  end

  def new(_attrs), do: {:error, :invalid_context_item}

  @doc "Creates one context item or raises."
  @spec new!(map() | keyword()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, item} -> item
      {:error, reason} -> raise ArgumentError, "invalid context item: #{inspect(reason)}"
    end
  end

  defp put_default_role(attrs) do
    if field(attrs, :role) do
      attrs
    else
      case field(attrs, :kind) do
        kind when kind in [:instruction, :memory, :skill, :resource, :repair, :custom] ->
          Map.put(attrs, :role, :system)

        _other ->
          attrs
      end
    end
  end

  defp item_id(attrs) do
    stable =
      Map.take(attrs, [
        :kind,
        :role,
        :content,
        :name,
        :tool_call_id,
        :tool_calls,
        :output,
        :source,
        :placement,
        :order
      ])

    "context_item_#{digest(stable) |> binary_part(0, 24)}"
  end

  defp normalize_keys(attrs) do
    Enum.reduce(@fields, attrs, fn key, normalized ->
      string_key = Atom.to_string(key)

      cond do
        Map.has_key?(normalized, key) ->
          Map.delete(normalized, string_key)

        Map.has_key?(normalized, string_key) ->
          normalized |> Map.put(key, Map.fetch!(normalized, string_key)) |> Map.delete(string_key)

        true ->
          normalized
      end
    end)
  end

  defp normalize_enums(attrs) do
    attrs
    |> normalize_enum(:kind, %{
      "message" => :message,
      "memory" => :memory,
      "skill" => :skill,
      "resource" => :resource,
      "instruction" => :instruction,
      "repair" => :repair,
      "custom" => :custom
    })
    |> normalize_enum(:role, %{
      "system" => :system,
      "user" => :user,
      "assistant" => :assistant,
      "tool" => :tool
    })
    |> normalize_enum(:placement, %{
      "instructions" => :instructions,
      "history" => :history,
      "knowledge" => :knowledge,
      "input" => :input,
      "repair" => :repair
    })
    |> normalize_enum(:state, %{"included" => :included, "excluded" => :excluded})
  end

  defp normalize_enum(attrs, key, values) do
    case Map.fetch(attrs, key) do
      {:ok, value} -> Map.put(attrs, key, Map.get(values, value, value))
      :error -> attrs
    end
  end

  defp digest(value) do
    value
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp field(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
