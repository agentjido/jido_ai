defmodule Jido.AI.Context.Snapshot do
  @moduledoc "A portable inspection record for one context lifecycle stage."

  alias Jido.AI.Context

  @schema Zoi.struct(
            __MODULE__,
            %{
              type: Zoi.literal("jido.ai.context.snapshot") |> Zoi.default("jido.ai.context.snapshot"),
              version: Zoi.integer() |> Zoi.default(1),
              context_id: Zoi.string(),
              stage: Zoi.enum([:open, :prepared, :completed]),
              digest: Zoi.string() |> Zoi.nullable() |> Zoi.default(nil),
              source: Zoi.map() |> Zoi.default(%{}),
              call: Zoi.map() |> Zoi.default(%{}),
              request: Zoi.map() |> Zoi.default(%{}),
              shape: Zoi.map() |> Zoi.default(%{}),
              items: Zoi.list(Zoi.map()) |> Zoi.default([]),
              decisions: Zoi.list(Zoi.map()) |> Zoi.default([]),
              usage: Zoi.any() |> Zoi.default(nil),
              response: Zoi.any() |> Zoi.default(nil),
              content: Zoi.enum([:none, :redacted, :full]) |> Zoi.default(:redacted),
              captured_at_ms: Zoi.integer()
            },
            coerce: true,
            unrecognized_keys: :error
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for a context snapshot."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc false
  @spec new(Context.t(), keyword()) :: t()
  def new(%Context{} = context, opts \\ []) do
    content = Keyword.get(opts, :content, :redacted)
    stage = snapshot_stage(context, Keyword.get(opts, :stage))
    included = Enum.filter(context.items, &(&1.state == :included))

    %__MODULE__{
      type: "jido.ai.context.snapshot",
      version: 1,
      context_id: context.id,
      stage: stage,
      digest: context.digest,
      source: portable(context.source),
      call: portable(context.call),
      request: request_summary(context.request, content),
      shape: shape(context.items, included),
      items: Enum.map(context.items, &item_summary(&1, content)),
      decisions: portable(context.decisions),
      usage: stage |> snapshot_result(context) |> field(:usage) |> portable(),
      response: stage |> snapshot_result(context) |> response_summary(content),
      content: content,
      captured_at_ms: captured_at(context, stage)
    }
  end

  @doc "Converts a snapshot to a portable map."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = snapshot), do: snapshot |> Map.from_struct() |> portable()

  @doc "Encodes a snapshot as a portable JSON document."
  @spec encode(t()) :: String.t()
  def encode(%__MODULE__{} = snapshot), do: snapshot |> to_map() |> Jason.encode!()

  @doc "Decodes a portable snapshot JSON document."
  @spec decode(String.t()) :: {:ok, map()} | {:error, term()}
  def decode(document) when is_binary(document) do
    with {:ok, %{"type" => "jido.ai.context.snapshot", "version" => 1} = snapshot} <-
           Jason.decode(document) do
      {:ok, snapshot}
    else
      {:ok, _document} -> {:error, :invalid_context_snapshot}
      error -> error
    end
  end

  def decode(_document), do: {:error, :invalid_context_snapshot}

  @doc "Decodes a portable snapshot JSON document or raises."
  @spec decode!(String.t()) :: map()
  def decode!(document) when is_binary(document) do
    case decode(document) do
      {:ok, snapshot} -> snapshot
      {:error, reason} -> raise ArgumentError, "invalid context snapshot: #{inspect(reason)}"
    end
  end

  @doc "Compares two snapshots by item, request, decision, usage, and response changes."
  @spec diff(t(), t()) :: map()
  def diff(%__MODULE__{} = before, %__MODULE__{} = later) do
    before_items = Map.new(before.items, &{field(&1, :id), &1})
    after_items = Map.new(later.items, &{field(&1, :id), &1})
    before_ids = MapSet.new(Map.keys(before_items))
    after_ids = MapSet.new(Map.keys(after_items))

    shared = MapSet.intersection(before_ids, after_ids)

    %{
      before: %{stage: before.stage, digest: before.digest},
      after: %{stage: later.stage, digest: later.digest},
      added_items: after_ids |> MapSet.difference(before_ids) |> values(after_items),
      removed_items: before_ids |> MapSet.difference(after_ids) |> values(before_items),
      changed_items:
        shared
        |> Enum.filter(&(Map.fetch!(before_items, &1) != Map.fetch!(after_items, &1)))
        |> Enum.sort()
        |> Enum.map(&%{before: Map.fetch!(before_items, &1), after: Map.fetch!(after_items, &1)}),
      request_changed: before.request != later.request,
      decisions_changed: before.decisions != later.decisions,
      usage_changed: before.usage != later.usage,
      response_changed: before.response != later.response
    }
  end

  defp values(ids, items), do: ids |> Enum.sort() |> Enum.map(&Map.fetch!(items, &1))

  defp snapshot_stage(%Context{stage: :completed}, :prepared), do: :prepared
  defp snapshot_stage(%Context{stage: stage}, nil), do: stage
  defp snapshot_stage(%Context{stage: stage}, stage), do: stage

  defp snapshot_stage(_context, stage) do
    raise ArgumentError, "context has no #{inspect(stage)} snapshot"
  end

  defp snapshot_result(:completed, context), do: context.result
  defp snapshot_result(_stage, _context), do: nil

  defp captured_at(context, :open), do: context.created_at_ms
  defp captured_at(context, :prepared), do: context.prepared_at_ms || context.created_at_ms

  defp captured_at(context, :completed),
    do: context.completed_at_ms || context.prepared_at_ms || context.created_at_ms

  defp request_summary(request, content) do
    request
    |> Map.take([:model, :tool_choice, :options, :output_schema, :prompt_cache])
    |> Map.put(:tools, Enum.map(Map.get(request, :tools) || [], &tool_summary(&1, content)))
    |> portable()
  end

  defp tool_summary(%ReqLLM.Tool{} = tool, content) do
    schema = ReqLLM.Tool.to_json_schema(tool)

    summary = %{
      name: tool.name,
      description: tool.description,
      strict: tool.strict,
      schema_digest: Context.term_digest(schema)
    }

    if content == :full, do: Map.put(summary, :schema, portable(schema)), else: summary
  rescue
    _error -> %{name: tool.name, description: tool.description, strict: tool.strict}
  end

  defp tool_summary(tool, :full), do: portable(tool)

  defp tool_summary(tool, _content) do
    %{
      name: field(tool, :name),
      description: field(tool, :description),
      strict: field(tool, :strict) == true,
      schema_digest: Context.term_digest(field(tool, :parameter_schema))
    }
  end

  defp response_summary(nil, _content), do: nil
  defp response_summary(result, :full), do: portable(result)

  defp response_summary(result, _content) when is_map(result) do
    result
    |> Map.take([
      :status,
      :kind,
      :category,
      :finish_reason,
      :retryable,
      :reason,
      :req_llm_request_id,
      :response_id,
      :model,
      :prompt_cache,
      :started_at_ms,
      :completed_at_ms
    ])
    |> Map.put(:digest, Context.term_digest(result))
    |> portable()
  end

  defp response_summary(result, _content), do: portable(result)

  defp shape(items, included) do
    %{
      item_count: length(items),
      included_item_count: length(included),
      excluded_item_count: length(items) - length(included),
      message_count: Enum.count(included, &(&1.role in [:system, :user, :assistant, :tool])),
      content_bytes: Enum.sum(Enum.map(included, &content_bytes/1)),
      kinds: frequencies(included, & &1.kind),
      placements: frequencies(included, & &1.placement),
      roles: frequencies(included, & &1.role)
    }
  end

  defp frequencies(values, key) do
    values
    |> Enum.map(key)
    |> Enum.reject(&is_nil/1)
    |> Enum.frequencies()
  end

  defp content_bytes(item) do
    %{content: item.content, output: item.output, tool_calls: item.tool_calls}
    |> Jason.encode!()
    |> byte_size()
  rescue
    _error -> byte_size(:erlang.term_to_binary(item.content))
  end

  defp item_summary(item, content) do
    base = %{
      id: item.id,
      kind: item.kind,
      role: item.role,
      placement: item.placement,
      priority: item.priority,
      required: item.required,
      order: item.order,
      state: item.state,
      reason: portable(item.reason),
      source: portable(item.source),
      content_digest: item.content_digest,
      content_shape: content_shape(item.content),
      name: item.name,
      tool_call_id: item.tool_call_id,
      tool_call_count: length(item.tool_calls)
    }

    case content do
      :none ->
        base

      :redacted ->
        Map.put(base, :content, "[REDACTED]")

      :full ->
        base
        |> Map.put(:content, portable(item.content))
        |> Map.put(:output, portable(item.output))
        |> Map.put(:metadata, portable(item.metadata))
        |> Map.put(:tool_calls, portable(item.tool_calls))
    end
  end

  defp content_shape(value) when is_binary(value), do: %{type: :text, bytes: byte_size(value)}
  defp content_shape(value) when is_list(value), do: %{type: :parts, count: length(value)}
  defp content_shape(nil), do: %{type: :none}
  defp content_shape(_value), do: %{type: :term}

  defp portable(nil), do: nil
  defp portable(value) when is_binary(value) or is_number(value) or is_boolean(value), do: value
  defp portable(value) when is_atom(value), do: value
  defp portable(value) when is_function(value), do: "[FUNCTION]"
  defp portable(value) when is_pid(value), do: "[PID]"
  defp portable(value) when is_reference(value), do: "[REFERENCE]"
  defp portable(value) when is_port(value), do: "[PORT]"
  defp portable(value) when is_tuple(value), do: value |> Tuple.to_list() |> Enum.map(&portable/1)
  defp portable(value) when is_list(value), do: Enum.map(value, &portable/1)

  defp portable(%_module{} = value), do: value |> Map.from_struct() |> portable()

  defp portable(value) when is_map(value) do
    Map.new(value, fn {key, item} ->
      portable_key = if is_atom(key) or is_binary(key), do: key, else: inspect(key)

      if sensitive_key?(portable_key) do
        {portable_key, "[REDACTED]"}
      else
        {portable_key, portable(item)}
      end
    end)
  end

  defp portable(value), do: inspect(value)

  defp sensitive_key?(key) do
    key = key |> to_string() |> String.downcase()

    key in [
      "api_key",
      "access_token",
      "auth_token",
      "bearer_token",
      "refresh_token",
      "secret",
      "password",
      "authorization",
      "credential",
      "cookie"
    ] or String.ends_with?(key, ["_api_key", "_secret", "_password", "_credential"])
  end

  defp field(nil, _key), do: nil
  defp field(map, key) when is_map(map), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
  defp field(_value, _key), do: nil
end
