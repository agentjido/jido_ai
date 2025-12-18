defmodule JSV.Vocabulary.V7.Core do
  alias JSV.Ref
  alias JSV.Vocabulary.V202012.Core, as: Fallback
  use JSV.Vocabulary, priority: 100

  @moduledoc """
  Implementation of the core vocabulary with draft 7 sepecifiticies.
  """

  @impl true
  defdelegate init_validators(opts), to: Fallback

  @impl true
  take_keyword :"$ref", raw_ref, _acc, builder, raw_schema do
    ref_relative_to_ns =
      case {raw_schema, builder} do
        # The ref is not relative to the current $id if defined at the same
        # level and there is a parent $id.
        #
        # Parent cannot be :root because a ref cannot target :root, it must be a
        # defined $id.
        {%{"$id" => _}, %{ns: _, parent_ns: parent}} when parent != :root ->
          parent

        # Otherwise take the $id at the same level or higher
        {_, %{ns: current_ns}} ->
          current_ns
      end

    ref = unwrap_ok(Ref.parse(raw_ref, ref_relative_to_ns))
    Fallback.put_ref(ref, :"$ref", [], builder)
  end

  consume_keyword :definitions

  # $ref overrides any other keyword in Draft7
  def handle_keyword(_kw_tuple, acc, builder, raw_schema) when is_map_key(raw_schema, "$ref") do
    {acc, builder}
  end

  defdelegate handle_keyword(kw_tuple, acc, builder, raw_schema), to: Fallback

  @impl true
  defdelegate finalize_validators(acc), to: Fallback

  @impl true
  defdelegate validate(data, vds, vctx), to: Fallback
end
