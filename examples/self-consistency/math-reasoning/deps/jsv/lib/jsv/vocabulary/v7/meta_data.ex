defmodule JSV.Vocabulary.V7.MetaData do
  alias JSV.Vocabulary.V202012.MetaData, as: Fallback
  use JSV.Vocabulary, priority: 300

  @moduledoc """
  Implementation of the meta-data vocabulary with draft 7 sepecifiticies.
  """

  @impl true
  defdelegate init_validators(opts), to: Fallback

  @impl true
  defdelegate handle_keyword(kw_tuple, acc, builder, raw_schema), to: Fallback

  @impl true
  defdelegate finalize_validators(acc), to: Fallback

  @impl true
  @spec validate(term, term, term) :: no_return()
  def validate(_data, _validators, _context) do
    raise "should not be called"
  end
end
