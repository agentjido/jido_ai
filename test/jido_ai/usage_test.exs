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
  end
end
