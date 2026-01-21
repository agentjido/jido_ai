defmodule JSV.Vocabulary.V202012.MetaData do
  use JSV.Vocabulary, priority: 300

  @moduledoc """
  Implementation for the `https://json-schema.org/draft/2020-12/vocab/meta-data`
  vocabulary.
  """
  @impl true
  def init_validators(_) do
    []
  end

  @impl true
  consume_keyword :deprecated
  consume_keyword :description
  consume_keyword :default
  consume_keyword :title
  consume_keyword :readOnly
  consume_keyword :writeOnly
  consume_keyword :examples

  ignore_any_keyword()

  @impl true
  def finalize_validators(_) do
    :ignore
  end

  @impl true
  @spec validate(term, term, term) :: no_return()
  def validate(_data, _validators, _context) do
    raise "should not be called"
  end
end
