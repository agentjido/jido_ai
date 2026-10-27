defmodule Jido.AI.Context do
  @moduledoc """
  The immutable data boundary for one model call.

  A Context is derived from a `Jido.Session`. It is not durable conversation
  history and it does not run memory, skills, tools, or reasoning graphs.
  """

  alias Jido.AI.Context.{Item, Snapshot}
  alias Jido.AI.Thread.Projection

  @request_keys [:model, :tools, :options, :tool_choice, :output_schema, :prompt_cache]

  @schema Zoi.struct(
            __MODULE__,
            %{
              version: Zoi.integer() |> Zoi.default(1),
              id: Zoi.string() |> Zoi.min(1),
              stage: Zoi.enum([:open, :prepared, :completed]) |> Zoi.default(:open),
              source: Zoi.map() |> Zoi.default(%{}),
              call: Zoi.map() |> Zoi.default(%{}),
              request: Zoi.map() |> Zoi.default(%{}),
              limits: Zoi.map() |> Zoi.default(%{}),
              items: Zoi.list(Item.schema()) |> Zoi.default([]),
              operations: Zoi.map() |> Zoi.default(%{}),
              decisions: Zoi.list(Zoi.map()) |> Zoi.default([]),
              result: Zoi.any() |> Zoi.default(nil),
              digest: Zoi.string() |> Zoi.nullable() |> Zoi.default(nil),
              created_at_ms: Zoi.integer(),
              prepared_at_ms: Zoi.integer() |> Zoi.nullable() |> Zoi.default(nil),
              completed_at_ms: Zoi.integer() |> Zoi.nullable() |> Zoi.default(nil)
            },
            coerce: true,
            unrecognized_keys: :error
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for a model-call context."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc "Builds an open context from a Session and its projected Thread."
  @spec new(Jido.Session.t() | map(), keyword() | map()) :: {:ok, t()} | {:error, term()}
  def new(session, opts \\ []) do
    opts = options_map(opts)
    limits = field(opts, :limits) || field(opts, :context_window) || %{}

    with {:ok, session} <- Jido.Session.decode(session),
         {:ok, projection} <- Projection.explain(session, limits),
         {:ok, request} <- normalize_request(initial_request(opts)) do
      run_id = field(opts, :run_id)
      instruction_items = instruction_items(field(opts, :instructions))
      history_items = Enum.map(projection.entries, &thread_item(&1, run_id))
      repair_items = repair_items(field(opts, :repair_instruction))

      context = %__MODULE__{
        version: 1,
        id: field(opts, :id) || "context_#{Jido.generate_id()}",
        stage: :open,
        source: %{
          session_id: session.id,
          session_rev: session.rev,
          thread_id: session.thread.id,
          thread_rev: session.thread.rev
        },
        call: %{
          request_id: field(opts, :request_id),
          run_id: run_id,
          model_call: field(opts, :model_call)
        },
        request: request,
        limits: limits,
        items: instruction_items ++ history_items ++ repair_items,
        operations: %{},
        decisions: projection.decisions,
        result: nil,
        digest: nil,
        created_at_ms: System.system_time(:millisecond),
        prepared_at_ms: nil,
        completed_at_ms: nil
      }

      validate(context)
    end
  end

  @doc "Validates a context value with its Zoi schema."
  @spec validate(t()) :: {:ok, t()} | {:error, term()}
  def validate(%__MODULE__{} = context), do: Zoi.parse(@schema, context)
  def validate(_context), do: {:error, :invalid_context}

  @doc "Adds typed items to an open context. The operation ID makes the change idempotent."
  @spec add(t(), Item.t() | map() | [Item.t() | map()], keyword() | map()) ::
          {:ok, t()} | {:error, term()}
  def add(%__MODULE__{} = context, values, opts) do
    with {:ok, items} <- normalize_items(List.wrap(values)) do
      operation(context, opts, {:add, items}, fn current ->
        existing_ids = MapSet.new(current.items, & &1.id)

        case Enum.find(items, &MapSet.member?(existing_ids, &1.id)) do
          nil -> {:ok, %{current | items: current.items ++ items}}
          item -> {:error, {:duplicate_context_item, item.id}}
        end
      end)
    end
  end

  @doc "Excludes items without deleting their inspection record."
  @spec exclude(t(), String.t() | [String.t()], keyword() | map()) ::
          {:ok, t()} | {:error, term()}
  def exclude(%__MODULE__{} = context, item_ids, opts) do
    ids = item_ids |> List.wrap() |> Enum.uniq()
    reason = option(opts, :reason, :excluded)

    operation(context, opts, {:exclude, ids, reason}, fn current ->
      known = MapSet.new(current.items, & &1.id)

      case Enum.find(ids, &(not MapSet.member?(known, &1))) do
        nil ->
          selected = MapSet.new(ids)

          items =
            Enum.map(current.items, fn item ->
              if MapSet.member?(selected, item.id),
                do: %{item | state: :excluded, reason: reason},
                else: item
            end)

          decisions =
            current.decisions ++
              Enum.map(ids, &%{item_id: &1, state: :excluded, reason: reason})

          {:ok, %{current | items: items, decisions: decisions}}

        id ->
          {:error, {:unknown_context_item, id}}
      end
    end)
  end

  @doc "Excludes existing items and adds one replacement as one idempotent operation."
  @spec replace(t(), String.t() | [String.t()], Item.t() | map(), keyword() | map()) ::
          {:ok, t()} | {:error, term()}
  def replace(%__MODULE__{} = context, item_ids, replacement, opts) do
    ids = item_ids |> List.wrap() |> Enum.uniq()

    with {:ok, item} <- normalize_item(replacement) do
      operation(context, opts, {:replace, ids, item}, fn current ->
        known = MapSet.new(current.items, & &1.id)

        cond do
          Enum.any?(ids, &(not MapSet.member?(known, &1))) ->
            id = Enum.find(ids, &(not MapSet.member?(known, &1)))
            {:error, {:unknown_context_item, id}}

          MapSet.member?(known, item.id) ->
            {:error, {:duplicate_context_item, item.id}}

          true ->
            selected = MapSet.new(ids)

            items =
              Enum.map(current.items, fn existing ->
                if MapSet.member?(selected, existing.id),
                  do: %{existing | state: :excluded, reason: :replaced},
                  else: existing
              end)

            decisions =
              current.decisions ++
                Enum.map(ids, &%{item_id: &1, state: :excluded, reason: :replaced_by, by: item.id})

            {:ok, %{current | items: items ++ [item], decisions: decisions}}
        end
      end)
    end
  end

  @doc "Merges model request data into an open context."
  @spec configure(t(), map(), keyword() | map()) :: {:ok, t()} | {:error, term()}
  def configure(%__MODULE__{} = context, patch, opts) when is_map(patch) do
    with {:ok, patch} <- normalize_request(patch) do
      operation(context, opts, {:configure, patch}, fn current ->
        {:ok, %{current | request: Map.merge(current.request, patch)}}
      end)
    end
  end

  def configure(%__MODULE__{}, _patch, _opts), do: {:error, :invalid_context_request}

  @doc "Freezes item order and assigns the stable model-request digest."
  @spec prepare(t()) :: {:ok, t()} | {:error, term()}
  def prepare(%__MODULE__{stage: :prepared} = context), do: {:ok, context}
  def prepare(%__MODULE__{stage: :completed}), do: {:error, :context_already_completed}

  def prepare(%__MODULE__{stage: :open} = context) do
    items = Enum.sort_by(context.items, &item_order/1)
    prepared_at = System.system_time(:millisecond)

    digest =
      term_digest(%{
        source: context.source,
        call: context.call,
        request: context.request,
        limits: context.limits,
        items: items,
        decisions: context.decisions
      })

    validate(%{context | stage: :prepared, items: items, digest: digest, prepared_at_ms: prepared_at})
  end

  @doc "Attaches the provider outcome without changing the prepared request digest."
  @spec complete(t(), term()) :: {:ok, t()} | {:error, term()}
  def complete(%__MODULE__{stage: :prepared} = context, result) do
    validate(%{
      context
      | stage: :completed,
        result: result,
        completed_at_ms: System.system_time(:millisecond)
    })
  end

  def complete(%__MODULE__{stage: :completed, result: result} = context, result), do: {:ok, context}
  def complete(%__MODULE__{stage: :completed}, _result), do: {:error, :context_already_completed}
  def complete(%__MODULE__{}, _result), do: {:error, :context_not_prepared}

  @doc "Captures a portable view before or after a model call."
  @spec snapshot(t(), keyword()) :: Snapshot.t()
  def snapshot(%__MODULE__{} = context, opts \\ []), do: Snapshot.new(context, opts)

  @doc "Compares two context snapshots."
  @spec diff(Snapshot.t(), Snapshot.t()) :: map()
  def diff(%Snapshot{} = before, %Snapshot{} = later), do: Snapshot.diff(before, later)

  @doc false
  @spec identity_document(t()) :: map()
  def identity_document(%__MODULE__{} = context) do
    context
    |> snapshot(content: :none)
    |> Snapshot.to_map()
    |> Map.delete(:captured_at_ms)
  end

  @doc false
  @spec term_digest(term()) :: String.t()
  def term_digest(value) do
    value
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp operation(context, opts, payload, change) do
    with {:ok, operation_id} <- operation_id(opts) do
      payload_digest = term_digest(payload)

      case Map.fetch(context.operations, operation_id) do
        {:ok, ^payload_digest} ->
          {:ok, context}

        {:ok, _other_digest} ->
          {:error, {:context_operation_conflict, operation_id}}

        :error when context.stage != :open ->
          {:error, :context_not_open}

        :error ->
          with {:ok, changed} <- change.(context) do
            validate(%{changed | operations: Map.put(changed.operations, operation_id, payload_digest)})
          end
      end
    end
  end

  defp operation_id(opts) do
    case option(opts, :op_id, nil) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _other -> {:error, :context_operation_id_required}
    end
  end

  defp normalize_items(items) do
    Enum.reduce_while(items, {:ok, []}, fn item, {:ok, normalized} ->
      case normalize_item(item) do
        {:ok, value} -> {:cont, {:ok, [value | normalized]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, normalized} -> {:ok, Enum.reverse(normalized)}
      error -> error
    end
  end

  defp normalize_item(%Item{} = item), do: Zoi.parse(Item.schema(), item)
  defp normalize_item(item), do: Item.new(item)

  defp initial_request(opts) do
    %{
      model: field(opts, :model),
      tools: field(opts, :tools) || [],
      options: field(opts, :options) || %{},
      tool_choice: field(opts, :tool_choice),
      output_schema: field(opts, :output_schema),
      prompt_cache: field(opts, :prompt_cache)
    }
  end

  defp normalize_request(request) do
    allowed = @request_keys ++ Enum.map(@request_keys, &Atom.to_string/1)

    if Map.keys(request) -- allowed == [] do
      normalized =
        Enum.reduce(@request_keys, %{}, fn key, values ->
          case fetch_field(request, key) do
            {:ok, value} -> Map.put(values, key, value)
            :error -> values
          end
        end)

      {:ok, normalized}
    else
      {:error, :invalid_context_request}
    end
  end

  defp instruction_items(nil), do: []
  defp instruction_items(""), do: []

  defp instruction_items(instructions) do
    [
      Item.new!(%{
        id: "context:instructions",
        kind: :instruction,
        role: :system,
        content: instructions,
        source: %{type: :agent_instructions},
        placement: :instructions,
        priority: 100,
        required: true,
        order: 0
      })
    ]
  end

  defp repair_items(nil), do: []
  defp repair_items(""), do: []

  defp repair_items(instruction) do
    [
      Item.new!(%{
        id: "context:repair",
        kind: :repair,
        role: :system,
        content: instruction,
        source: %{type: :output_repair},
        placement: :repair,
        priority: 100,
        required: true,
        order: 0
      })
    ]
  end

  defp thread_item(entry, run_id) do
    message = entry.message
    entry_run_id = field(entry.refs, :run_id)
    current? = is_binary(run_id) and run_id != "" and entry_run_id == run_id

    Item.new!(%{
      id: "thread:#{entry.id}",
      kind: :message,
      role: message.role,
      content: message.content,
      name: message.name,
      tool_call_id: message.tool_call_id,
      tool_calls: message.tool_calls,
      output: message.output,
      metadata: message.metadata,
      source: %{
        type: :thread_entry,
        entry_id: entry.id,
        seq: entry.seq,
        at: entry.at,
        refs: entry.refs
      },
      placement: if(current?, do: :input, else: :history),
      priority: 0,
      required: current?,
      order: entry.seq
    })
  end

  defp item_order(item) do
    rank =
      case item.placement do
        :instructions -> 0
        :history -> 1
        :knowledge -> 2
        :input -> 3
        :repair -> 4
      end

    {rank, -item.priority, item.order, item.id}
  end

  defp options_map(opts) when is_list(opts), do: Map.new(opts)
  defp options_map(opts) when is_map(opts), do: opts
  defp options_map(_opts), do: %{}

  defp option(opts, key, default) when is_list(opts), do: Keyword.get(opts, key, default)
  defp option(opts, key, default) when is_map(opts), do: field(opts, key) || default
  defp option(_opts, _key, default), do: default

  defp fetch_field(map, key) do
    cond do
      Map.has_key?(map, key) -> {:ok, Map.fetch!(map, key)}
      Map.has_key?(map, Atom.to_string(key)) -> {:ok, Map.fetch!(map, Atom.to_string(key))}
      true -> :error
    end
  end

  defp field(map, key) when is_map(map), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
  defp field(_map, _key), do: nil
end

defimpl Runic.Identity.Projectable, for: Jido.AI.Context do
  def identity_document(context), do: Jido.AI.Context.identity_document(context)
end
