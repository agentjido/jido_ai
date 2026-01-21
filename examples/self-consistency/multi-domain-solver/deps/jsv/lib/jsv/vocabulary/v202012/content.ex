defmodule JSV.Vocabulary.V202012.Content do
  use JSV.Vocabulary, priority: 300

  @moduledoc """
  Placeholder implementation for the
  `https://json-schema.org/draft/2020-12/vocab/content` vocabulary. No
  validation is performed.
  """

  @impl true
  def init_validators(_) do
    []
  end

  @impl true
  consume_keyword :contentMediaType
  consume_keyword :contentEncoding
  consume_keyword :contentSchema
  ignore_any_keyword()

  @impl true
  def finalize_validators([]) do
    :ignore
  end

  @impl true
  @spec validate(term, term, term) :: no_return()
  def validate(_data, _validators, _context) do
    raise "should not be called"
  end
end
