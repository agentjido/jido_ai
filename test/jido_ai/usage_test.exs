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

    test "does not coerce numeric-looking provider metadata identifiers" do
      assert Jido.AI.Usage.merge(
               %{
                 cost: %{line_items: [%{id: "001", cost: "0.001"}]},
                 provider_meta: %{request_id: "001", shard: "03"}
               },
               %{
                 cost: %{line_items: [%{id: "002", cost: "0.002"}]},
                 provider_meta: %{request_id: "002"}
               }
             ) == %{
               cost: %{line_items: [%{id: "002", cost: 0.002}]},
               provider_meta: %{request_id: "002", shard: "03"}
             }
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

  describe "token_counts/1" do
    test "normalizes alternate token keys for telemetry measurements" do
      response = %{
        usage: %{
          "input" => "4",
          :completion_tokens => 6,
          "totalTokenCount" => "10"
        }
      }

      assert Jido.AI.Usage.token_counts(response) == %{
               input_tokens: 4,
               output_tokens: 6,
               total_tokens: 10
             }

      assert Jido.AI.Usage.token_measurements(response) == %{
               input_tokens: 4,
               output_tokens: 6,
               total_tokens: 10
             }
    end

    test "normalizes nested and provider camel-case token keys" do
      response = %{
        usage: %{
          "tokens" => %{
            "promptTokenCount" => "8.0",
            "candidatesTokenCount" => 3.9
          },
          "totalTokenCount" => "11.0"
        }
      }

      assert Jido.AI.Usage.token_counts(response) == %{
               input_tokens: 8,
               output_tokens: 3,
               total_tokens: 11
             }
    end

    test "merges canonical token counts into provider usage metadata" do
      assert Jido.AI.Usage.with_token_counts(%{"prompt_tokens" => "2", "completion_tokens" => "3"}) == %{
               "completion_tokens" => "3",
               "prompt_tokens" => "2",
               input_tokens: 2,
               output_tokens: 3,
               total_tokens: 5
             }
    end
  end
end
