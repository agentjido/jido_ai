defmodule Jido.AI.Reasoning.ReAct.Transformers.SystemOne do
  @moduledoc """
  ReAct request transformer that asks a System One decision model, before each LLM
  turn, which tool the next step needs and how much reasoning the request needs.

  Every tool schema is sent to the LLM on every turn, so an agent with many tools pays
  for all of them on every call. This transformer narrows each turn's `tools` to the
  few the decision model rates as useful (or to none when the next step needs no tool),
  and can optionally pick a model alias from a reasoning-depth score.

  One decision call per turn asks three questions over the same state:

    * `needs_tool` (noul): does the next step need one of the available actions?
    * `tool` (choice): which action, over every tool name plus `none`
    * `depth` (score, 3 levels): direct step, a few dependent steps, or a long chain

  ## Usage

      defmodule MyApp.ToolRouter do
        use Jido.AI.Reasoning.ReAct.Transformers.SystemOne,
          client: SystemOneClient,
          client_opts: [provider: :typesafe],
          top_k: 3
      end

      defmodule MyApp.Agent do
        use Jido.AI.Agent,
          name: "my_agent",
          tools: [...],
          request_transformer: MyApp.ToolRouter
      end

  `client` is any module implementing `Jido.AI.SystemOne.Client`.

  ## Options

    * `:client` (required) - module implementing `Jido.AI.SystemOne.Client`
    * `:client_opts` - keyword passed to `client.evaluate/3` (default `[]`)
    * `:top_k` - most tools to offer on a turn that needs one (default `3`); tools the
      model scored at zero are never offered
    * `:needs_tool_threshold` - below this `needs_tool` probability the turn gets no
      tools (default `0.5`)
    * `:models` - `{fast, capable, reasoning}` model aliases or specs to route by depth;
      `nil` (the default) leaves the configured model alone
    * `:depth_thresholds` - `{low, high}` depth cuts between the three models
      (default `{0.75, 1.5}`)

  A request can override `:client`, `:client_opts`, and the other options through
  the runtime context key `:system_one` (a keyword list), for example per tenant
  credentials.

  ## Failure behaviour

  The transformer never fails a request. A client error, a raise, a missing or
  malformed answer, invalid runtime override, or more tools than one choice question
  can hold (254) all return no overrides, so the turn runs exactly as configured.

  ## Telemetry

  Each decision emits `[:jido, :ai, :strategy, :react, :system_one_route]` through
  `Jido.AI.Observe`, with measurement `duration_ms` (the decision call) and metadata
  `request_id`, `run_id`, `iteration`, `needs_tool`, `depth`, `chosen_tools`,
  `chosen_model`, and `top_tools` (the three most probable names).
  """

  require Logger

  alias Jido.AI.Observe

  @max_choice_tools 254
  @defaults [
    client_opts: [],
    top_k: 3,
    needs_tool_threshold: 0.5,
    models: nil,
    depth_thresholds: {0.75, 1.5}
  ]

  @doc false
  defmacro __using__(opts) do
    # Options are compile-time literals (aliases, atoms, tuples); evaluate them in the caller.
    {opts, _binding} = Code.eval_quoted(opts, [], __CALLER__)

    opts =
      try do
        validate_options!(opts)
      rescue
        e in ArgumentError ->
          reraise CompileError,
                  [description: Exception.message(e), file: __CALLER__.file, line: __CALLER__.line],
                  __STACKTRACE__
      end

    behaviour = Jido.AI.Reasoning.ReAct.RequestTransformer
    transformer = __MODULE__

    quote do
      @behaviour unquote(behaviour)

      @impl unquote(behaviour)
      def transform_request(request, state, config, runtime_context) do
        unquote(transformer).transform(request, state, config, runtime_context, unquote(Macro.escape(opts)))
      end
    end
  end

  @doc """
  Validates transformer options and fills in defaults. Raises `ArgumentError`.
  """
  @spec validate_options!(keyword()) :: keyword()
  def validate_options!(opts) when is_list(opts) do
    opts = Keyword.validate!(opts, [:client | @defaults])
    Enum.each(opts, &validate_option!/1)
    unless Keyword.has_key?(opts, :client), do: validate_option!({:client, nil})
    opts
  end

  def validate_options!(other), do: raise(ArgumentError, "expected a keyword list, got: #{inspect(other)}")

  defp validate_option!({:client, client}) when is_atom(client) and not is_nil(client), do: :ok

  defp validate_option!({:client, _}),
    do: raise(ArgumentError, "Jido.AI SystemOne transformer requires a :client module")

  defp validate_option!({:client_opts, opts}) when is_list(opts), do: :ok
  defp validate_option!({:top_k, k}) when is_integer(k) and k > 0, do: :ok
  defp validate_option!({:needs_tool_threshold, t}) when is_number(t), do: :ok
  defp validate_option!({:models, nil}), do: :ok
  defp validate_option!({:models, {_, _, _}}), do: :ok

  defp validate_option!({:depth_thresholds, {low, high}}) when is_number(low) and is_number(high) and low <= high,
    do: :ok

  defp validate_option!({key, value}) do
    expected = %{
      client_opts: "a keyword list",
      top_k: "a positive integer",
      needs_tool_threshold: "a number",
      models: "nil or {fast, capable, reasoning}",
      depth_thresholds: "{low, high} numbers with low <= high"
    }

    raise ArgumentError, ":#{key} must be #{Map.fetch!(expected, key)}, got: #{inspect(value)}"
  end

  @doc """
  Runs one routing decision. Used by modules that `use` this transformer; call it
  directly to test a configuration.
  """
  @spec transform(map(), term(), term(), map(), keyword()) :: {:ok, map()}
  def transform(request, state, config, runtime_context, opts) do
    with {:ok, opts} <- merge_runtime_opts(Keyword.merge(@defaults, opts), runtime_context) do
      tools = Map.get(request, :tools) || %{}

      cond do
        map_size(tools) > @max_choice_tools ->
          Logger.warning("Jido.AI SystemOne transformer: #{map_size(tools)} tools exceed one choice question; skipping")

          {:ok, %{}}

        map_size(tools) == 0 and is_nil(opts[:models]) ->
          {:ok, %{}}

        true ->
          decide(request, tools, state, config, runtime_context, opts)
      end
    else
      {:error, reason} -> fail_open(reason)
    end
  rescue
    error -> fail_open({:transformer_raised, Exception.message(error)})
  catch
    kind, reason -> fail_open({kind, reason})
  end

  defp decide(request, tools, state, config, runtime_context, opts) do
    pairs = Enum.map(tools, fn {name, mod} -> {to_string(name), description(mod)} end)

    with {:ok, answers, meta} <-
           safe_evaluate(opts[:client], build_state(request), questions(pairs), opts[:client_opts]),
         {:ok, needs, probs, depth} <- read_answers(answers) do
      overrides = overrides(tools, needs, probs, depth, opts)
      emit(config, runtime_context, state, meta, needs, probs, depth, overrides)
      {:ok, overrides}
    else
      {:error, reason} -> fail_open(reason)
    end
  end

  defp fail_open(reason) do
    Logger.warning("Jido.AI SystemOne transformer: no decision (#{inspect(reason, limit: 5)}); turn unchanged")
    {:ok, %{}}
  end

  defp overrides(tools, needs, probs, depth, opts) do
    tool_overrides =
      cond do
        needs < opts[:needs_tool_threshold] -> %{tools: %{}}
        (gated = top_k(tools, probs, opts[:top_k])) != %{} -> %{tools: gated}
        true -> %{}
      end

    case opts[:models] do
      nil -> tool_overrides
      models -> Map.put(tool_overrides, :model, tier(depth, models, opts[:depth_thresholds]))
    end
  end

  @doc """
  The decision-model state for one turn: the latest user request, up to three recent
  tool results, and every available tool with its description.
  """
  @spec build_state(map()) :: map()
  def build_state(%{messages: messages} = request) do
    tools = Map.get(request, :tools) || %{}
    user = messages |> Enum.filter(&(role(&1) == "user")) |> List.last()

    progress =
      messages |> Enum.filter(&(role(&1) == "tool")) |> Enum.take(-3) |> Enum.map(&tool_result_text/1)

    %{
      request: content_text(user),
      progress: if(progress == [], do: nil, else: progress),
      available_actions: Enum.map(tools, fn {n, m} -> %{name: to_string(n), description: description(m)} end)
    }
  end

  @doc """
  The three questions sent on each turn, with choice criteria built from
  `[{tool_name, description}]` plus `none`.
  """
  @spec questions([{String.t(), String.t()}]) :: map()
  def questions(pairs) do
    criteria = pairs |> Map.new() |> Map.put("none", "No listed action is needed for the next step")

    %{
      "needs_tool" => %{
        "type" => "noul",
        "instructions" =>
          "Given `request` and any `progress` so far, does the next step need one of the actions in `available_actions`?",
        "criteria" => %{
          "true" => "The next step is a computation, lookup or side effect that one of the listed actions performs",
          "false" =>
            "The request is already answered by `progress`, or is general knowledge or writing that needs no listed action"
        }
      },
      "tool" => %{
        "type" => "choice",
        "instructions" =>
          "Which action in `available_actions` should run next to make progress on `request`? Pick none if no listed action fits.",
        "criteria" => criteria
      },
      "depth" => %{
        "type" => "score",
        "instructions" => "How much reasoning does `request` need beyond calling the actions?",
        "criteria" => [
          "A single direct step or one action call",
          "A few dependent steps or two chained action calls",
          "A long chain of dependent steps, or a well-known trap where the intuitive answer is wrong"
        ]
      }
    }
  end

  defp safe_evaluate(client, state, questions, client_opts) do
    case client.evaluate(state, questions, client_opts) do
      {:ok, answers, meta} when is_map(answers) -> {:ok, answers, if(is_map(meta), do: meta, else: %{})}
      {:error, reason} -> {:error, reason}
      other -> {:error, {:unexpected_client_result, other}}
    end
  rescue
    e -> {:error, {:client_raised, Exception.message(e)}}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  defp read_answers(answers) do
    with %{noul: needs} when is_number(needs) and needs >= 0 and needs <= 1 <- field(answers, "needs_tool"),
         %{probabilities: probs} when is_map(probs) <- field(answers, "tool"),
         {:ok, probs} <- normalize_probabilities(probs),
         %{score: depth} when is_number(depth) and depth >= 0 and depth <= 2 <- field(answers, "depth") do
      {:ok, needs, probs, depth}
    else
      _ -> {:error, :incomplete_answers}
    end
  end

  defp normalize_probabilities(probs) do
    Enum.reduce_while(probs, {:ok, %{}}, fn
      {name, probability}, {:ok, normalized}
      when is_binary(name) and is_number(probability) and probability >= 0 and probability <= 1 ->
        {:cont, {:ok, Map.put(normalized, name, probability)}}

      _, _acc ->
        {:halt, {:error, :invalid_probabilities}}
    end)
  end

  defp field(answers, id) do
    case Map.get(answers, id) do
      %_{} = struct -> Map.from_struct(struct)
      %{} = map -> map
      _ -> nil
    end
  end

  defp top_k(tools, probs, k) do
    by_name = Map.new(tools, fn {name, mod} -> {to_string(name), {name, mod}} end)

    probs
    |> Enum.reject(fn {name, p} -> name == "none" or p <= 0 end)
    |> Enum.sort_by(fn {_, p} -> -p end)
    |> Enum.flat_map(fn {name, _} -> List.wrap(Map.get(by_name, name)) end)
    |> Enum.take(k)
    |> Map.new()
  end

  defp tier(depth, {fast, _, _}, {low, _}) when depth < low, do: fast
  defp tier(depth, {_, capable, _}, {_, high}) when depth < high, do: capable
  defp tier(_depth, {_, _, reasoning}, _), do: reasoning

  defp emit(config, runtime_context, state, meta, needs, probs, depth, overrides) do
    top_tools =
      probs
      |> Enum.reject(fn {name, _} -> name == "none" end)
      |> Enum.sort_by(fn {_, p} -> -p end)
      |> Enum.take(3)
      |> Enum.map(fn {name, _} -> name end)

    Observe.emit(
      observability(config),
      Observe.strategy(:react, :system_one_route),
      %{duration_ms: meta_value(meta, :latency_ms) || 0},
      %{
        request_id: Map.get(runtime_context, :request_id),
        run_id: Map.get(runtime_context, :run_id),
        iteration: field_or_nil(state, :iteration),
        model: meta_value(meta, :model),
        needs_tool: needs,
        depth: depth,
        top_tools: top_tools,
        chosen_tools: overrides |> Map.get(:tools, :unchanged) |> chosen_names(),
        chosen_model: Map.get(overrides, :model, :unchanged)
      }
    )
  end

  defp chosen_names(:unchanged), do: :unchanged
  defp chosen_names(tools), do: tools |> Map.keys() |> Enum.map(&to_string/1) |> Enum.sort()

  defp observability(%{observability: obs}), do: obs
  defp observability(_), do: %{}

  defp meta_value(meta, key) when is_map(meta), do: Map.get(meta, key)
  defp meta_value(_, _), do: nil

  defp field_or_nil(%{} = map, key), do: Map.get(map, key)
  defp field_or_nil(_, _), do: nil

  defp merge_runtime_opts(opts, %{system_one: overrides}) when is_list(overrides) do
    try do
      {client_opts, rest} = Keyword.pop(overrides, :client_opts, [])

      merged =
        opts
        |> Keyword.merge(rest)
        |> Keyword.update!(:client_opts, &Keyword.merge(&1, client_opts))

      {:ok, validate_options!(merged)}
    rescue
      _error -> {:error, :invalid_runtime_options}
    catch
      _kind, _reason -> {:error, :invalid_runtime_options}
    end
  end

  defp merge_runtime_opts(_opts, %{system_one: _overrides}), do: {:error, :invalid_runtime_options}
  defp merge_runtime_opts(opts, _runtime_context), do: {:ok, opts}

  defp description(mod) when is_atom(mod) do
    if Code.ensure_loaded?(mod) and function_exported?(mod, :description, 0),
      do: mod.description() || inspect(mod),
      else: inspect(mod)
  end

  defp description(other), do: inspect(other)

  defp role(%{role: r}), do: to_string(r)
  defp role(%{"role" => r}), do: to_string(r)
  defp role(_), do: ""

  defp tool_result_text(message) do
    name = Map.get(message, :name) || Map.get(message, "name") || Map.get(message, :tool_name)
    text = content_text(message)
    if name, do: "#{name} -> #{text}", else: text
  end

  defp content_text(nil), do: ""
  defp content_text(%{content: c}), do: content_text(c)
  defp content_text(%{"content" => c}), do: content_text(c)
  defp content_text(c) when is_binary(c), do: c
  defp content_text(list) when is_list(list), do: Enum.map_join(list, " ", &content_text/1)
  defp content_text(%{text: t}) when is_binary(t), do: t
  defp content_text(%{"text" => t}) when is_binary(t), do: t
  defp content_text(other), do: inspect(other, limit: 50, printable_limit: 300)
end
