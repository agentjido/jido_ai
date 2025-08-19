defmodule SparqCommentsTest do
  use SparqTest.RoundtripCase

  describe "comments and whitespace" do
    test "handles line comments" do
      assert_roundtrip("x = 1 // This is a comment\ny = 2", fn tokens ->
        # Verify comment is preserved as a token
        assert Enum.any?(tokens, fn
                 {:line_comment, [], " This is a comment"} -> true
                 _ -> false
               end)
      end)
    end

    test "handles block comments" do
      input = """
      x = 1
      /* This is a
         block comment */
      y = 2\
      """

      assert_roundtrip(input, fn tokens ->
        # Verify block comment content
        assert Enum.any?(tokens, fn
                 {:block_comment, [], " This is a\n   block comment "} -> true
                 _ -> false
               end)
      end)
    end

    test "complex mixing of comments and whitespace" do
      input = """
      // Header comment
          x = 1  /* inline comment */
      /* Block
         comment */\ty = 2  // End comment\
      """

      assert_roundtrip(input, fn tokens ->
        # Verify we preserved all comment types
        comment_types =
          tokens
          |> Enum.filter(fn
            {:line_comment, _, _} -> true
            {:block_comment, _, _} -> true
            _ -> false
          end)
          |> Enum.map(&elem(&1, 0))

        assert comment_types == [:line_comment, :block_comment, :block_comment, :line_comment]
      end)
    end
  end
end
