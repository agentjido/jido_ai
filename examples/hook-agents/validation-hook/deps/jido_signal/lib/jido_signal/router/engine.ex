defmodule Jido.Signal.Router.Engine do
  @moduledoc """
  The routing engine that matches signals to handlers.
  """

  use ExDbug, enabled: false

  alias Jido.Signal

  alias Jido.Signal.Router.{
    HandlerInfo,
    NodeHandlers,
    PatternMatch,
    Route,
    TrieNode
  }

  @doc """
  Builds the trie structure from validated routes.
  """
  @spec build_trie([Route.t()], TrieNode.t()) :: TrieNode.t()
  def build_trie(routes, base_trie \\ %TrieNode{}) do
    Enum.reduce(routes, base_trie, fn %Route{} = route, trie ->
      segments = route.path |> sanitize_path() |> String.split(".")

      case route.match do
        nil ->
          handler_info = %HandlerInfo{
            target: route.target,
            priority: route.priority,
            complexity: calculate_complexity(route.path)
          }

          do_add_path_route(segments, trie, handler_info)

        match_fn ->
          pattern_match = %PatternMatch{
            match: match_fn,
            target: route.target,
            priority: route.priority,
            complexity: calculate_complexity(route.path)
          }

          do_add_pattern_route(segments, trie, pattern_match)
      end
    end)
  end

  @doc """
  Routes a signal through the trie to find matching handlers.
  """
  @spec route_signal(TrieNode.t(), Signal.t()) :: [term()]
  def route_signal(%TrieNode{} = trie, %Signal{type: type} = signal) when not is_nil(type) do
    segments = String.split(type, ".")
    results = do_route(segments, trie, signal, [])
    Enum.map(results, fn {target, _priority, _complexity} -> target end)
  end

  @doc """
  Removes a path from the trie.
  """
  @spec remove_path(String.t(), TrieNode.t()) :: TrieNode.t()
  def remove_path(path, trie) do
    segments = path |> sanitize_path() |> String.split(".")
    do_remove_path(segments, trie)
  end

  @doc """
  Counts total routes in the trie.
  """
  @spec count_routes(TrieNode.t()) :: non_neg_integer()
  def count_routes(%TrieNode{segments: segments, handlers: handlers}) do
    handler_count =
      case handlers do
        %NodeHandlers{handlers: handlers} when is_list(handlers) ->
          length(handlers)

        _ ->
          0
      end

    Enum.reduce(segments, handler_count, fn {_segment, node}, acc ->
      acc + count_routes(node)
    end)
  end

  @doc """
  Collects all routes from the trie into a list of Route structs.
  """
  @spec collect_routes(TrieNode.t()) :: [Route.t()]
  def collect_routes(%TrieNode{} = trie) do
    collect_routes(trie, [], "")
  end

  # Private helpers

  defp sanitize_path(path) do
    path
    |> String.trim()
    |> String.replace(~r/\.+/, ".")
    |> String.replace(~r/(^\.|\.$)/, "")
  end

  defp calculate_complexity(path) do
    segments = String.split(path, ".")

    # Base score from segment count (increase multiplier)
    base_score = length(segments) * 2000

    # Exact segment matches are worth more at start of path
    exact_matches =
      Enum.with_index(segments)
      |> Enum.reduce(0, fn {segment, index}, acc ->
        case segment do
          "**" -> acc
          "*" -> acc
          # Higher weight for exact matches
          _ -> acc + 3000 * (length(segments) - index)
        end
      end)

    # Penalty calculation with position weighting
    penalties =
      Enum.with_index(segments)
      |> Enum.reduce(0, fn {segment, index}, acc ->
        case segment do
          # Double wildcard has massive penalty, reduced if it comes after exact matches
          "**" -> acc + 2000 - index * 200
          # Single wildcard has smaller penalty
          "*" -> acc + 1000 - index * 100
          _ -> acc
        end
      end)

    base_score + exact_matches - penalties
  end

  # Insert a HandlerInfo in descending order by (complexity, priority).
  defp insert_handler_sorted([], handler), do: [handler]

  defp insert_handler_sorted([h | t] = list, new_handler) do
    cond do
      new_handler.complexity > h.complexity ->
        [new_handler | list]

      new_handler.complexity < h.complexity ->
        [h | insert_handler_sorted(t, new_handler)]

      # complexities are equal, compare priority
      new_handler.priority > h.priority ->
        [new_handler | list]

      new_handler.priority < h.priority ->
        [h | insert_handler_sorted(t, new_handler)]

      # When both complexity and priority are equal, append the new handler
      true ->
        [h | [new_handler | t]]
    end
  end

  # Insert a PatternMatch in descending order by (complexity, priority).
  defp insert_matcher_sorted([], matcher), do: [matcher]

  defp insert_matcher_sorted([m | t] = list, new_matcher) do
    cond do
      new_matcher.complexity > m.complexity ->
        [new_matcher | list]

      new_matcher.complexity < m.complexity ->
        [m | insert_matcher_sorted(t, new_matcher)]

      new_matcher.priority > m.priority ->
        [new_matcher | list]

      new_matcher.priority < m.priority ->
        [m | insert_matcher_sorted(t, new_matcher)]

      # When both complexity and priority are equal, append the new matcher
      true ->
        [m | [new_matcher | t]]
    end
  end

  # Merge two descending-sorted lists (by {complexity, priority}).
  defp merge_sorted([], list2), do: list2
  defp merge_sorted(list1, []), do: list1

  defp merge_sorted([x = {_t1, p1, c1} | xs], [y = {_t2, p2, c2} | ys]) do
    cond do
      c1 > c2 ->
        [x | merge_sorted(xs, [y | ys])]

      c1 < c2 ->
        [y | merge_sorted([x | xs], ys)]

      # complexities are equal; compare priority
      p1 > p2 ->
        [x | merge_sorted(xs, [y | ys])]

      p1 < p2 ->
        [y | merge_sorted([x | xs], ys)]

      true ->
        [x | merge_sorted(xs, [y | ys])]
    end
  end

  # Core routing logic
  defp do_route([], %TrieNode{} = _trie, %Signal{} = _signal, acc), do: acc

  defp do_route([segment | rest] = _segments, %TrieNode{} = trie, %Signal{} = signal, acc) do
    # Try exact match first
    matching_handlers =
      case Map.get(trie.segments, segment) do
        nil ->
          acc

        %TrieNode{} = node ->
          handlers = collect_handlers(node.handlers, signal, acc)

          if rest == [] do
            handlers
          else
            do_route(rest, node, signal, handlers)
          end
      end

    # Then try single wildcard
    matching_handlers =
      case Map.get(trie.segments, "*") do
        nil ->
          matching_handlers

        %TrieNode{} = node ->
          handlers = collect_handlers(node.handlers, signal, matching_handlers)

          if rest == [] do
            handlers
          else
            do_route(rest, node, signal, handlers)
          end
      end

    # Finally try multi-level wildcard
    case Map.get(trie.segments, "**") do
      nil ->
        matching_handlers

      %TrieNode{} = node ->
        handlers = collect_handlers(node.handlers, signal, matching_handlers)

        # Try all possible remaining segment combinations
        [rest, []]
        |> Stream.concat(tails(rest))
        |> Enum.reduce(handlers, fn remaining, acc ->
          if remaining == [] do
            acc
          else
            do_route(remaining, node, signal, acc)
          end
        end)
    end
  end

  # Helper to get all possible tails of a list
  defp tails([]), do: []
  defp tails([_h | t]), do: [t | tails(t)]

  # Handler collection logic
  defp collect_handlers(%NodeHandlers{} = node_handlers, %Signal{} = signal, acc) do
    handler_results =
      case node_handlers.handlers do
        handlers when is_list(handlers) ->
          Enum.map(handlers, fn info ->
            case info.target do
              targets when is_list(targets) ->
                # For multiple dispatch targets, create a tuple for each target
                Enum.map(targets, fn target ->
                  {target, info.priority, info.complexity}
                end)

              target ->
                [{target, info.priority, info.complexity}]
            end
          end)
          |> List.flatten()

        _ ->
          []
      end

    pattern_results = collect_pattern_matches(node_handlers.matchers || [], signal)

    merge_sorted(
      merge_sorted(handler_results, pattern_results),
      acc
    )
  end

  defp collect_handlers(nil, %Signal{} = _signal, acc) do
    acc
  end

  # Pattern matching
  defp collect_pattern_matches(matchers, %Signal{} = signal) do
    Enum.reduce(matchers, [], fn %PatternMatch{} = matcher, matches ->
      try do
        case matcher.match.(signal) do
          true ->
            case matcher.target do
              targets when is_list(targets) ->
                # For multiple dispatch targets, create a tuple for each target
                Enum.map(targets, fn target ->
                  {target, matcher.priority, 0}
                end) ++ matches

              target ->
                [{target, matcher.priority, 0} | matches]
            end

          false ->
            matches

          _ ->
            matches
        end
      rescue
        _ ->
          matches
      end
    end)
  end

  # Route addition to trie
  defp do_add_path_route([segment], %TrieNode{} = trie, %HandlerInfo{} = handler_info) do
    Map.update(
      trie,
      :segments,
      %{segment => %TrieNode{handlers: %NodeHandlers{handlers: [handler_info]}}},
      fn segments ->
        Map.update(
          segments,
          segment,
          %TrieNode{handlers: %NodeHandlers{handlers: [handler_info]}},
          fn node ->
            # If the target is a list of dispatch configs, create a handler info for each
            handlers =
              case handler_info.target do
                targets when is_list(targets) ->
                  Enum.map(targets, fn target ->
                    %HandlerInfo{
                      target: target,
                      priority: handler_info.priority,
                      complexity: handler_info.complexity
                    }
                  end)

                _ ->
                  [handler_info]
              end

            %TrieNode{
              node
              | handlers: %NodeHandlers{
                  handlers:
                    Enum.reduce(
                      handlers,
                      node.handlers.handlers || [],
                      fn handler, acc -> insert_handler_sorted(acc, handler) end
                    ),
                  matchers: node.handlers.matchers
                }
            }
          end
        )
      end
    )
  end

  defp do_add_path_route([segment | rest], %TrieNode{} = trie, %HandlerInfo{} = handler_info) do
    Map.update(
      trie,
      :segments,
      %{segment => do_add_path_route(rest, %TrieNode{}, handler_info)},
      fn segments ->
        Map.update(
          segments,
          segment,
          do_add_path_route(rest, %TrieNode{}, handler_info),
          fn node -> do_add_path_route(rest, node, handler_info) end
        )
      end
    )
  end

  defp do_add_pattern_route([segment], %TrieNode{} = trie, %PatternMatch{} = matcher) do
    Map.update(
      trie,
      :segments,
      %{segment => %TrieNode{handlers: %NodeHandlers{matchers: [matcher]}}},
      fn segments ->
        Map.update(
          segments,
          segment,
          %TrieNode{handlers: %NodeHandlers{matchers: [matcher]}},
          fn node ->
            %TrieNode{
              node
              | handlers: %NodeHandlers{
                  handlers: node.handlers.handlers,
                  matchers: insert_matcher_sorted(node.handlers.matchers || [], matcher)
                }
            }
          end
        )
      end
    )
  end

  defp do_add_pattern_route([segment | rest], %TrieNode{} = trie, %PatternMatch{} = matcher) do
    Map.update(
      trie,
      :segments,
      %{segment => do_add_pattern_route(rest, %TrieNode{}, matcher)},
      fn segments ->
        Map.update(
          segments,
          segment,
          do_add_pattern_route(rest, %TrieNode{}, matcher),
          fn node -> do_add_pattern_route(rest, node, matcher) end
        )
      end
    )
  end

  # Recursively removes a path from the trie
  defp do_remove_path([], trie), do: trie

  defp do_remove_path([segment], %TrieNode{segments: segments} = trie) do
    # Remove the leaf node
    new_segments = Map.delete(segments, segment)
    %TrieNode{trie | segments: new_segments}
  end

  defp do_remove_path([segment | rest], %TrieNode{segments: segments} = trie) do
    case Map.get(segments, segment) do
      nil ->
        trie

      node ->
        new_node = do_remove_path(rest, node)
        # If the node is empty after removal, remove it too
        if map_size(new_node.segments) == 0 do
          %TrieNode{trie | segments: Map.delete(segments, segment)}
        else
          %TrieNode{trie | segments: Map.put(segments, segment, new_node)}
        end
    end
  end

  # Collects all routes from the trie into a list of Route structs
  defp collect_routes(%TrieNode{segments: segments, handlers: handlers}, acc, path_prefix) do
    # Add any handlers at current node
    acc =
      case handlers do
        %NodeHandlers{handlers: handlers} when is_list(handlers) and length(handlers) > 0 ->
          # Preserve order by not reversing here
          Enum.map(handlers, fn %HandlerInfo{
                                  target: target,
                                  priority: priority
                                } ->
            %Route{
              path: String.trim_leading(path_prefix, "."),
              target: target,
              priority: priority
            }
          end) ++ acc

        %NodeHandlers{matchers: matchers} when is_list(matchers) and length(matchers) > 0 ->
          # Preserve order by not reversing here
          Enum.map(matchers, fn %PatternMatch{
                                  target: target,
                                  priority: priority,
                                  match: match
                                } ->
            %Route{
              path: String.trim_leading(path_prefix, "."),
              target: target,
              priority: priority,
              match: match
            }
          end) ++ acc

        _ ->
          acc
      end

    # Recursively collect from child nodes
    segments
    # Sort segments for consistent ordering
    |> Enum.sort()
    |> Enum.reduce(acc, fn {segment, node}, acc ->
      new_prefix = path_prefix <> "." <> segment
      collect_routes(node, acc, new_prefix)
    end)
  end
end
