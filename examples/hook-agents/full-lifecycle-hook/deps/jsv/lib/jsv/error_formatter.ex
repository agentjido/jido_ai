defmodule JSV.ErrorFormatter do
  alias JSV.Key
  alias JSV.Normalizer
  alias JSV.Ref
  alias JSV.ValidationError
  alias JSV.Validator
  alias JSV.Validator.Error

  @moduledoc """
  Error formatting helpers.

  Errors are grouped by:

  * Instance location: the bit of data that was invalidated
  * Schema location: the part of the schema that invalidated it
  * Evaluation path: the path followed from the root to this schema location
  """

  @type error_unit :: %{
          required(:valid) => boolean,
          required(:instanceLocation) => binary,
          required(:evaluationPath) => binary,
          required(:schemaLocation) => binary,
          optional(:errors) => [keyword_error]
        }

  @type keyword_error :: %{
          required(:kind) => atom,
          required(:message) => String.t(),
          optional(:details) => [error_unit]
        }

  @type raw_path :: [raw_path] | binary | integer | atom

  @doc false
  @spec error_schema :: module
  def error_schema do
    __MODULE__.ValidationErrorSchema
  end

  @normalize_opts_schema NimbleOptions.new!(
                           sort: [
                             type: {:in, [:asc, :desc]},
                             default: :desc,
                             doc: """
                             Controls the sort direction. Errors are sorted by `instanceLocation`.
                             """
                           ],
                           keys: [
                             type: {:in, [:atoms, :strings]},
                             doc: """
                             Define the type of the keys in the normalized errors maps.

                             While truly "normalized" JSON data should not have atom keys,
                             this option defaults to :atoms for backward compatibility reasons.
                             """
                           ]
                         )

  @type normalize_opt :: unquote(NimbleOptions.option_typespec(@normalize_opts_schema))

  @doc """
  Returns a JSON-able version of the errors contained in the ValidationError.

  This is generatlly useful to generate HTTP API responses or message broker
  responses.

  ### Options

  #{NimbleOptions.docs(@normalize_opts_schema)}
  """
  @spec normalize_error(ValidationError.t(), keyword) :: map()
  def normalize_error(%ValidationError{} = e, opts \\ []) do
    opts =
      opts
      |> NimbleOptions.validate!(@normalize_opts_schema)
      |> Keyword.put_new(:keys, :atoms)

    top = %{valid: false, details: normalize_errors(e.errors, opts)}
    normalize_keys(top, opts)
  end

  defp normalize_keys(with_atoms, opts) do
    case opts[:keys] do
      :atoms -> with_atoms
      :strings -> Normalizer.normalize(with_atoms)
    end
  end

  defp normalize_errors(errors, opts) do
    errors
    |> Enum.group_by(fn
      %Error{data_path: dp, eval_path: ep, schema_path: sp} -> {dp, ep, sp}
      %{valid: _, instanceLocation: _, evaluationPath: _, schemaLocation: _} = already_normalized -> already_normalized
    end)
    |> Enum.map(fn
      {{data_path, eval_path, schema_path}, errors} -> error_annot(data_path, eval_path, schema_path, errors, opts)
      {already_normalized, [already_normalized]} -> already_normalized
    end)
    |> sort_errors(opts[:sort])
  end

  defp sort_errors(errors, order) do
    Enum.sort_by(errors, & &1.instanceLocation, order)
  end

  defp error_annot(rev_data_path, rev_eval_path, rev_schema_path, errors, opts) do
    errors_fmt = Enum.map(errors, &build_error(&1, opts))

    %{
      valid: false,
      errors: errors_fmt,
      instanceLocation: format_data_path(rev_data_path),
      evaluationPath: format_eval_path(rev_eval_path),
      schemaLocation: format_schema_path(rev_schema_path)
    }
  end

  defp build_error(error, opts) do
    %Error{kind: kind, data: data, formatter: formatter, args: args} =
      error

    args_map = Map.new(args)

    case formatter.format_error(kind, args_map, data) do
      message when is_binary(message) ->
        %{message: message, kind: kind}

      {new_kind, message} when is_atom(new_kind) and is_binary(message) ->
        %{message: message, kind: new_kind}

      {message, sub_errors} when is_binary(message) and is_list(sub_errors) ->
        %{message: message, kind: kind, details: normalize_errors(sub_errors, opts)}

      {new_kind, message, sub_errors} when is_atom(new_kind) and is_binary(message) and is_list(sub_errors) ->
        %{message: message, kind: new_kind, details: normalize_errors(sub_errors, opts)}
    end
  end

  @doc """
  Returns an output unit with `valid: true` for the given
  `#{inspect(Validator)}`. This can be substitued to an Error struct in the
  nested details of an error. Mostly used to show multiple validated schemas
  with `:oneOf`.
  """
  @spec valid_annot(Validator.validator(), Validator.context()) :: error_unit

  def valid_annot(subschema, vctx) do
    evaluation_path = format_eval_path(vctx.eval_path)

    %{
      valid: true,
      instanceLocation: format_data_path(vctx.data_path),
      evaluationPath: evaluation_path,
      schemaLocation: format_schema_path(subschema)
    }
  end

  @spec format_data_path(raw_path) :: String.t()
  def format_data_path([]) do
    "#"
  end

  def format_data_path(rev_data_path) do
    iodata =
      List.foldl(rev_data_path, [], fn
        index, acc when is_integer(index) -> [?/, Integer.to_string(index) | acc]
        key, acc -> [?/, Ref.escape_json_pointer(key) | acc]
      end)

    IO.iodata_to_binary(["#" | iodata])
  end

  @doc false
  @spec format_eval_path(list) :: binary
  def format_eval_path([]) do
    "#"
  end

  def format_eval_path(rev_eval_path) do
    # map to string but also reverse the path
    iodata = List.foldl(rev_eval_path, [], fn segment, acc -> [?/, format_eval_path_segment(segment) | acc] end)
    IO.iodata_to_binary(["#" | iodata])
  end

  @doc false
  @spec format_schema_path([term] | Validator.validator()) :: binary
  def format_schema_path(rev_path)

  def format_schema_path([]) do
    "#"
  end

  def format_schema_path(rev_path) when is_list(rev_path) do
    format_schema_path(rev_path, [])
  end

  def format_schema_path({:alias_of, key}) do
    Key.to_iodata(key)
  end

  def format_schema_path(%{schema_path: sp}) do
    format_schema_path(sp)
  end

  defp format_schema_path([segment, next | rev_path], acc) do
    format_schema_path([next | rev_path], [?/, format_eval_path_segment(segment) | acc])
  end

  defp format_schema_path([last], acc) do
    final_path =
      case last do
        :root -> IO.iodata_to_binary(["#" | acc])
        id when is_binary(id) -> [id, "#" | acc]
      end

    IO.iodata_to_binary(final_path)
  end

  defp format_eval_path_segment(item) do
    case item do
      atom when is_atom(atom) -> Ref.escape_json_pointer(Atom.to_string(atom))
      key when is_binary(key) -> Ref.escape_json_pointer(key)
      index when is_integer(index) -> Integer.to_string(index)
      {tag, key} when is_binary(key) -> [Atom.to_string(tag), ?/, Ref.escape_json_pointer(key)]
      {tag, index} when is_integer(index) -> [Atom.to_string(tag), ?/, Integer.to_string(index)]
      {_, :"$ref", _} -> "$ref"
      {_, :"$dynamicRef", _} -> "$dynamicRef"
      other -> raise "invalid eval path segment: #{inspect(other)}"
    end
  end
end
