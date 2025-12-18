defmodule JSV.Vocabulary.V7.Content do
  alias JSV.Vocabulary.V202012.Content, as: Fallback
  use JSV.Vocabulary, priority: 300

  @moduledoc """
  Implementation of the content vocabulary with draft 7 sepecifiticies. No
  validation is performed.
  """

  @impl true
  defdelegate init_validators(opts), to: Fallback

  @impl true
  ignore_keyword(:contentSchema)

  defdelegate handle_keyword(kw_tuple, acc, builder, raw_schema), to: Fallback

  @impl true
  defdelegate finalize_validators(acc), to: Fallback

  @impl true
  @spec validate(term, term, term) :: no_return()
  def validate(_data, _validators, _context) do
    raise "should not be called"
  end
end
