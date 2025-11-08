defmodule Jido.AI.Prompt.Splitter do
  @moduledoc """
  This module is used to split a string into chunks by the number of tokens,
  while accounting for *other* data that might be going with it to the API
  endpoint with the limited token count.

  For example, the search entry agent may be processing a large file, one that
  must be split into 3 slices just to fit it into the payload of an API call.
  In order to retain context between chunks, the agent essentially _reduces_
  over the file, keeping track of information in the previous chunks to
  generate a final summary. Doing that means that we need to not only split the
  file by the number of tokens in each slice, but also keep some space for the
  bespoke data that will be added to the payload as the agent's "accumulator".
  """

  defstruct [
    :model,
    :input,
    :input_tokens,
    :offset,
    :done
  ]

  def new(input, model) do
    %Jido.AI.Prompt.Splitter{
      model: model,
      input: input,
      input_tokens: Jido.AI.Tokenizer.encode(input, model),
      offset: 0,
      done: false
    }
  end

  def next_chunk(%Jido.AI.Prompt.Splitter{done: true} = tok, _bespoke_input) do
    {:done, tok}
  end

  def next_chunk(tok, bespoke_input) do
    bespoke_tokens = Jido.AI.Tokenizer.encode(bespoke_input, tok.model) |> length()
    remaining_tokens = tok.model.context - bespoke_tokens
    {slice, %Jido.AI.Prompt.Splitter{} = tok} = get_slice(tok, remaining_tokens)

    tok =
      if tok.offset >= length(tok.input_tokens) do
        %Jido.AI.Prompt.Splitter{tok | done: true}
      else
        tok
      end

    {slice, tok}
  end

  defp get_slice(%Jido.AI.Prompt.Splitter{done: true} = tok, _num_tokens) do
    {"", tok}
  end

  defp get_slice(%Jido.AI.Prompt.Splitter{} = tok, num_tokens) do
    slice = Enum.slice(tok.input_tokens, tok.offset, num_tokens)
    tokens = length(slice)
    output = Jido.AI.Tokenizer.decode(slice, tok.model)
    {output, %Jido.AI.Prompt.Splitter{tok | offset: tok.offset + tokens}}
  end
end
