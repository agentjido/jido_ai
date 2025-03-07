# defmodule JidoTest.AI.TokenizerTest do
#   @moduledoc """
#   Use the [official tokenizer](https://platform.openai.com/tokenizer) to
#   generate token IDs for `@input` to add new test cases.

#   Note that `text-embedding-3-large` uses the same tokenizer as
#   `gpt-3.5`/`gpt-3.5-turbo` in the official tool.
#   """

#   use ExUnit.Case, async: true

#   @input "Now is the time for all good men to come to the aid of their country."

#   describe "cl100k-base" do
#     setup do
#       tokens = [
#         7184,
#         374,
#         279,
#         892,
#         369,
#         682,
#         1695,
#         3026,
#         311,
#         2586,
#         311,
#         279,
#         12576,
#         315,
#         872,
#         3224,
#         13
#       ]

#       {:ok, tokens: tokens}
#     end

#     test "encode/1 <=> decode/1", %{tokens: tokens} do
#       model = Jido.AI.Model.embeddings()
#       encoded = Jido.AI.Tokenizer.encode(@input, model)
#       assert encoded == tokens
#       assert Jido.AI.Tokenizer.decode(encoded, model) == @input
#     end

#     test "chunk/2", _ctx do
#       model = Jido.AI.Model.new("mst-3k", nil, 10)
#       chunks = Jido.AI.Tokenizer.chunk(@input, model)

#       assert [
#                "Now is the time for all good men to come",
#                " to the aid of their country."
#              ] = chunks
#     end
#   end

#   describe "o200k-base" do
#     setup do
#       tokens = [
#         10620,
#         382,
#         290,
#         1058,
#         395,
#         722,
#         1899,
#         1966,
#         316,
#         3063,
#         316,
#         290,
#         13765,
#         328,
#         1043,
#         4931,
#         13
#       ]

#       {:ok, tokens: tokens}
#     end

#     test "encode/1 <=> decode/1", %{tokens: tokens} do
#       model = Jido.AI.Model.new("gpt-4o", nil, 128_000)
#       encoded = Jido.AI.Tokenizer.encode(@input, model)
#       assert encoded == tokens
#       assert Jido.AI.Tokenizer.decode(encoded, model) == @input
#     end

#     test "chunk/2", _ctx do
#       model = Jido.AI.Model.new("mst-3k", nil, 10)
#       chunks = Jido.AI.Tokenizer.chunk(@input, model)

#       assert [
#                "Now is the time for all good men to come",
#                " to the aid of their country."
#              ] = chunks
#     end
#   end
# end
