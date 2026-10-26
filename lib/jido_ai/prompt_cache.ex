defmodule Jido.AI.PromptCache do
  @moduledoc """
  Builds portable prompt-cache plans from effective model options.

  ReqLLM and the model provider own the cache. This module records the stable
  prompt identity, configured lifetime, and observed cache usage.
  """

  alias Jido.AI.Thread.Projection

  @doc "Builds one cache plan for a projected conversation."
  @spec plan(Jido.Session.t(), [map()], String.t(), map(), map(), integer()) :: map()
  def plan(session, messages, model, options, config, now_ms)
      when is_list(messages) and is_binary(model) and is_map(options) and is_map(config) do
    enabled = field(config, :enabled) == true
    ttl = field(config, :ttl) || option_ttl(options)
    ttl_ms = ttl_ms(ttl)
    key = field(config, :key) || session.id

    %{
      enabled: enabled,
      provider: provider(model),
      model: model,
      key: key,
      prefix_fingerprint: fingerprint(messages),
      projected_thread_rev: session.thread.rev,
      breakpoint_seq: Projection.breakpoint(session),
      planned_at_ms: now_ms,
      segments: [
        %{
          kind: :stable_prefix,
          ttl: ttl,
          ttl_ms: ttl_ms,
          token_count: nil,
          observed_write_at_ms: nil,
          observed_read_at_ms: nil,
          expires_at_ms: nil
        }
      ]
    }
  end

  @doc "Adds provider cache options without changing unrelated request options."
  @spec apply_options(map(), map()) :: map()
  def apply_options(options, %{enabled: false}), do: options

  def apply_options(options, %{enabled: true, provider: "openai"} = plan) do
    cache_options = if ttl(plan), do: %{ttl: ttl(plan)}, else: %{}

    options
    |> update_provider_options(:prompt_cache_key, plan.key)
    |> maybe_put_provider_options(:prompt_cache_options, cache_options)
  end

  def apply_options(options, %{enabled: true, provider: "anthropic"} = plan) do
    options
    |> update_provider_options(:anthropic_prompt_cache, true)
    |> maybe_put_provider_option(:anthropic_prompt_cache_ttl, ttl(plan))
  end

  def apply_options(options, %{enabled: true, provider: provider} = plan)
      when provider in ["amazon_bedrock", "bedrock"] do
    options
    |> update_provider_options(:prompt_cache, true)
    |> maybe_put_provider_option(:prompt_cache_ttl, ttl(plan))
  end

  def apply_options(options, _plan), do: options

  @doc "Builds request-level cache data while retaining every model observation."
  @spec summary(map(), [map()]) :: map()
  def summary(config, observations) when is_map(config) and is_list(observations) do
    base = %{
      enabled: field(config, :enabled) == true,
      configured_ttl: field(config, :ttl),
      attempts: observations
    }

    case List.last(observations) do
      nil -> base
      last -> Map.merge(last, base)
    end
  end

  @doc "Adds provider-observed cache usage and local observation timestamps."
  @spec observe(map(), map(), integer()) :: map()
  def observe(plan, usage, completed_at_ms) when is_map(plan) and is_integer(completed_at_ms) do
    usage = ReqLLM.Usage.normalize(usage)
    read? = positive?(usage[:cache_read_tokens])
    write? = positive?(usage[:cache_write_tokens])

    segments = observed_segments(plan, usage, read?, write?, completed_at_ms)

    Map.merge(plan, %{
      observed_at_ms: completed_at_ms,
      observed_read_at_ms: if(read?, do: completed_at_ms, else: nil),
      observed_write_at_ms: if(write?, do: completed_at_ms, else: nil),
      usage: cache_usage(usage),
      segments: segments
    })
  end

  @doc "Converts a supported cache lifetime to milliseconds."
  @spec ttl_ms(term()) :: non_neg_integer() | nil
  def ttl_ms(value) when is_integer(value) and value >= 0, do: value

  def ttl_ms(value) when is_binary(value) do
    case Regex.run(~r/^(\d+)(ms|s|m|h)$/, value) do
      [_, count, unit] -> String.to_integer(count) * unit_ms(unit)
      _other -> nil
    end
  end

  def ttl_ms(_value), do: nil

  defp cache_usage(usage) do
    Map.take(usage, [
      :input_tokens,
      :output_tokens,
      :total_tokens,
      :input_includes_cached,
      :cache_read_tokens,
      :cache_write_tokens,
      :cache_write_tokens_by_ttl
    ])
  end

  defp option_ttl(options) do
    field(options, :prompt_cache_ttl) ||
      field(options, :anthropic_prompt_cache_ttl) ||
      options |> field(:provider_options) |> field(:prompt_cache_options) |> field(:ttl)
  end

  defp update_provider_options(options, key, value) do
    provider_options = options |> field(:provider_options) |> provider_options_map()
    Map.put(options, :provider_options, Map.put(provider_options, key, value))
  end

  defp observed_segments(plan, usage, read?, write?, completed_at_ms) do
    case write_lifetimes(usage) do
      [] ->
        Enum.map(plan.segments, fn segment ->
          write_at = if write?, do: completed_at_ms, else: nil

          segment
          |> Map.put(:observed_write_at_ms, write_at)
          |> Map.put(:observed_read_at_ms, if(read?, do: completed_at_ms, else: nil))
          |> Map.put(:expires_at_ms, expires_at(write_at, segment.ttl_ms))
        end)

      lifetimes ->
        Enum.map(lifetimes, fn {ttl, tokens} ->
          ttl_ms = ttl_ms(ttl)

          %{
            kind: :stable_prefix,
            ttl: ttl,
            ttl_ms: ttl_ms,
            token_count: tokens,
            observed_write_at_ms: completed_at_ms,
            observed_read_at_ms: if(read?, do: completed_at_ms, else: nil),
            expires_at_ms: expires_at(completed_at_ms, ttl_ms)
          }
        end)
    end
  end

  defp write_lifetimes(usage) do
    case usage[:cache_write_tokens_by_ttl] do
      groups when is_map(groups) ->
        groups
        |> Enum.filter(fn {_ttl, tokens} -> positive?(tokens) end)
        |> Enum.sort_by(fn {ttl, _tokens} -> to_string(ttl) end)

      _other ->
        []
    end
  end

  defp ttl(%{segments: [segment | _rest]}), do: segment.ttl
  defp ttl(_plan), do: nil

  defp maybe_put_provider_option(options, _key, nil), do: options
  defp maybe_put_provider_option(options, key, value), do: update_provider_options(options, key, value)
  defp maybe_put_provider_options(options, _key, value) when value == %{}, do: options
  defp maybe_put_provider_options(options, key, value), do: update_provider_options(options, key, value)
  defp provider_options_map(nil), do: %{}
  defp provider_options_map(options) when is_map(options), do: options
  defp provider_options_map(options) when is_list(options), do: Map.new(options)
  defp positive?(value), do: is_number(value) and value > 0
  defp expires_at(nil, _ttl_ms), do: nil
  defp expires_at(_write_at, nil), do: nil
  defp expires_at(write_at, ttl_ms), do: write_at + ttl_ms
  defp provider(model), do: model |> String.split(":", parts: 2) |> hd()
  defp fingerprint(messages), do: :crypto.hash(:sha256, Jason.encode!(messages)) |> Base.encode16(case: :lower)
  defp field(nil, _key), do: nil
  defp field(map, key) when is_map(map), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
  defp field(_value, _key), do: nil
  defp unit_ms("ms"), do: 1
  defp unit_ms("s"), do: 1_000
  defp unit_ms("m"), do: 60_000
  defp unit_ms("h"), do: 3_600_000
end
