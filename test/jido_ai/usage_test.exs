defmodule Jido.AI.UsageTest do
  use ExUnit.Case, async: true

  describe "merge/2" do
    test "adds numeric usage and preserves nested non-numeric provider metadata" do
      first = %{
        input_tokens: 10,
        output_tokens: 5,
        total_cost: 0.001,
        add_reasoning_to_cost: false,
        cost: %{
          total: 0.001,
          input_cost: 0.0008,
          line_items: [%{id: "first"}]
        },
        tool_usage: %{calls: 1}
      }

      second = %{
        input_tokens: 7,
        output_tokens: 3,
        total_cost: 0.002,
        add_reasoning_to_cost: true,
        cost: %{
          total: 0.002,
          input_cost: 0.0015,
          line_items: [%{id: "second"}]
        },
        tool_usage: %{calls: 2}
      }

      assert Jido.AI.Usage.merge(first, second) == %{
               input_tokens: 17,
               output_tokens: 8,
               total_cost: 0.003,
               add_reasoning_to_cost: true,
               cost: %{
                 total: 0.003,
                 input_cost: 0.0023,
                 line_items: [%{id: "second"}]
               },
               tool_usage: %{calls: 3}
             }
    end

    test "sums numeric strings and ignores malformed top-level usage inputs" do
      assert Jido.AI.Usage.merge(%{input_tokens: "10", cost: %{total: "0.001"}}, %{
               input_tokens: 7,
               cost: %{total: "0.002"},
               provider: "anthropic"
             }) == %{
               input_tokens: 17,
               cost: %{total: 0.003},
               provider: "anthropic"
             }

      assert Jido.AI.Usage.merge(:bad_usage, %{input_tokens: "3"}) == %{input_tokens: 3}
      assert Jido.AI.Usage.merge(%{input_tokens: 3}, :bad_usage) == %{input_tokens: 3}
    end

    test "derives total tokens when input and output counters are present" do
      assert Jido.AI.Usage.ensure_total_tokens(%{input_tokens: 2, output_tokens: "3"}) == %{
               input_tokens: 2,
               output_tokens: "3",
               total_tokens: 5
             }

      assert Jido.AI.Usage.ensure_total_tokens(%{input_tokens: 2, output_tokens: 3, total_tokens: 99}) == %{
               input_tokens: 2,
               output_tokens: 3,
               total_tokens: 99
             }
    end
  end
end
