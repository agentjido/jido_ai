defmodule Sparq.Evaluator.WhitespaceTest do
  use ExUnit.Case, async: true
  alias Sparq.Evaluator

  describe "whitespace filtering" do
    test "filters out whitespace and comments during script evaluation" do
      # Test through direct evaluation
      input = [
        {:spaces, [], 2},
        {:character, [], [:Greeter, []]},
        {:newline, [], :lf},
        {:line_comment, [], " A comment"},
        {:scene, [], [:Scene, []]},
        {:block_comment, [], " Another comment"},
        {:newline, [], :lf}
      ]

      filtered = Evaluator.filter_whitespace(input)
      assert length(filtered) == 2

      assert Enum.all?(filtered, fn
               {:character, _, _} -> true
               {:scene, _, _} -> true
               _ -> false
             end)
    end

    test "filter_whitespace removes all whitespace and comment tokens" do
      input = [
        {:spaces, [], 2},
        {:character, [], [:Greeter, []]},
        {:newline, [], :lf},
        {:line_comment, [], " A comment"},
        {:scene, [], [:Scene, []]},
        {:block_comment, [], " Another comment"},
        {:newline, [], :lf}
      ]

      expected = [
        {:character, [], [:Greeter, []]},
        {:scene, [], [:Scene, []]}
      ]

      assert Evaluator.filter_whitespace(input) == expected
    end

    test "filter_whitespace handles nested expressions" do
      input = [
        {:character, [],
         [
           :Greeter,
           [
             {:spaces, [], 2},
             {:line_comment, [], " Comment"},
             {:newline, [], :lf}
           ]
         ]}
      ]

      # Should preserve the whitespace in the body since it's part of the character definition
      assert Evaluator.filter_whitespace(input) == input
    end

    test "filter_whitespace returns non-list expressions unchanged" do
      input = {:character, [], [:Greeter, []]}
      assert Evaluator.filter_whitespace(input) == input
    end
  end
end
