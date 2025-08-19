defmodule Sparq.Integration.HelloWorldTest do
  use ExUnit.Case, async: true
  alias Sparq.Parser

  @hello_world_script """
  character Greeter do
    // This is a friendly character
    /* They like to say hello */
  end

  scene HelloWorldScene do
    beat :start do
      say Greeter, "Hello, World!"
    end
  end
  """

  describe "hello world script" do
    test "parses and preserves whitespace" do
      {:ok, tokens} = Parser.parse(@hello_world_script)

      # Convert tokens back to source
      result = Parser.format(tokens)

      # Should exactly match original, including whitespace
      assert result == @hello_world_script
    end

    test "correctly removes whitespace tokens" do
      {:ok, tokens} = Parser.parse(@hello_world_script, whitespace: false)

      # Verify no whitespace tokens exist in the AST
      assert Enum.all?(tokens, fn
               {type, _, children} when is_list(children) ->
                 type not in [:spaces, :newline, :line_comment, :block_comment] and
                   Enum.all?(children, fn
                     list when is_list(list) ->
                       Enum.all?(list, fn
                         {type, _, _} ->
                           type not in [:spaces, :newline, :line_comment, :block_comment]

                         _ ->
                           true
                       end)

                     _ ->
                       true
                   end)

               _ ->
                 true
             end)

      # Basic structure should still be intact
      assert [
               {:character, [], [:Greeter, []]},
               {:scene, [], [:HelloWorldScene, [beat]]}
             ] = tokens

      assert {:beat, [], [:start, [{:say, [], [:Greeter, "Hello, World!"]}]]} = beat
    end

    test "parses into correct AST structure" do
      {:ok, tokens} = Parser.parse(@hello_world_script)

      # Find the character definition
      character = Enum.find(tokens, &match?({:character, _, _}, &1))

      assert {:character, [],
              [
                :Greeter,
                [
                  {:spaces, [], 2},
                  {:line_comment, [], " This is a friendly character"},
                  {:newline, [], :lf},
                  {:spaces, [], 2},
                  {:block_comment, [], " They like to say hello "},
                  {:newline, [], :lf}
                ]
              ]} = character

      # Find the scene definition
      scene = Enum.find(tokens, &match?({:scene, _, _}, &1))

      assert {:scene, [],
              [
                :HelloWorldScene,
                [
                  {:spaces, [], 2},
                  {:beat, [],
                   [
                     :start,
                     [
                       {:spaces, [], 4},
                       {:say, [], [:Greeter, "Hello, World!"]},
                       {:newline, [], :lf},
                       {:spaces, [], 2}
                     ]
                   ]},
                  {:newline, [], :lf}
                ]
              ]} = scene
    end
  end
end
