defmodule JSV.Validator do
  alias JSV
  alias JSV.BooleanSchema
  alias JSV.Builder
  alias JSV.Key
  alias JSV.Subschema
  alias JSV.ValidationError
  alias JSV.Validator.Error
  alias JSV.Vocabulary

  @moduledoc """
  This is the home of the recursive validation logic.

  The validator is called on the root schema, and may be called by vocabulary
  implementations to validate sub parts of the data built withing each
  vocabulary module.
  """

  defmodule ValidationContext do
    @moduledoc """
    Validation context carried along by the `JSV.Validator` and given to all
    vocabulary implementations.

    This struct is used to store errors found during validation, and to hold
    contextual information such as the current path in the data or in the
    schema.
    """

    # :eval_path stores both the current keyword nesting leading to an error, and
    # the namespace changes for error absolute location.

    @enforce_keys [:validators, :scope, :errors, :evaluated, :data_path, :eval_path, :schema_path, :opts, :cast_stacks]
    defstruct @enforce_keys

    @type t :: %__MODULE__{}
  end

  @type context :: %ValidationContext{}
  @type eval_sub_path :: Builder.path_segment() | [Builder.path_segment()]
  @type validators :: %{Key.t() => validator}
  @type validator :: JSV.Subschema.t() | BooleanSchema.t() | {:alias_of, binary}
  @type result :: {:ok, term, context} | {:error, context}

  @spec context(%{Key.t() => validator}, Key.t(), keyword()) :: context
  def context(validators, entrypoint, opts) do
    %ValidationContext{
      data_path: [],
      eval_path: key_to_eval_path(entrypoint),
      schema_path: [Key.namespace_of(entrypoint)],
      validators: validators,
      scope: [Key.namespace_of(entrypoint)],
      errors: [],
      evaluated: [%{}],
      opts: opts,
      cast_stacks: %{}
    }
  end

  defp key_to_eval_path(key) do
    # TODO how to handle anchors here ?
    case key do
      {:pointer, _, arg} -> :lists.reverse(arg)
      _ -> []
    end
  end

  @doc """
  Validate the given data with the given validator. The validator is typically a
  sub-part of a `JSV.Root` struct built with `JSV.build/2` such as a
  `JSV.Subschema` struct.
  """
  @spec validate(term, validator(), context) :: result
  def validate(data, subschema, vctx)

  def validate(data, %BooleanSchema{} = bs, vctx) do
    case bs.valid? do
      true -> return(data, vctx)
      false -> {:error, add_error(vctx, boolean_schema_error(vctx, bs, data))}
    end
  end

  def validate(data, {:alias_of, key}, vctx) do
    with_scope(vctx, key, _eval_path = [], fn vctx ->
      validate(data, Map.fetch!(vctx.validators, key), vctx)
    end)
  end

  # TODO if the :cast option is disabled for the validator, we should skip all
  # the cast stack shenanigans.

  # Executes all validators with the given data, collecting errors on the way,
  # then return either ok or error with all errors.
  def validate(data, %Subschema{} = sub, vctx) do
    %{validators: validators, cast: cast} = sub
    %{cast_stacks: cast_stacks, data_path: data_path} = vctx

    # * Set the path of the current validator to he one of the subschema
    # * push the cast of the subschema into the stack. after validation
    vctx = %{
      vctx
      | schema_path: sub.schema_path,
        cast_stacks: push_cast(cast_stacks, data_path, cast)
    }

    vdr_result =
      reduce(validators, data, vctx, fn {module, mod_validators}, data, vctx ->
        module.validate(data, mod_validators, vctx)
      end)

    case vdr_result do
      {:ok, value, vctx} -> pop_apply_cast(value, data_path, vctx)
      {:error, _} = err -> err
    end
  end

  # Pushing a cast from a subschema is special. Multiple casts can be attempted
  # to be set for the same data path (for instance with allOf) and we cannot
  # support that, so pushes are ignored when a cast is already present.
  #
  # But why do we keep all the nils in the stack? Because we want to apply the
  # casts at the last moment, in the topmost validator for the same data_path.
  #
  # To do so, when pushing a real cast like {module, tag}, the cast is pushed
  # "up" the cast (down to the tail) instead of being the new head:
  #
  # * The validate/3 function call that pushed it will pop a nil in return, and
  #   will not change the data that still needs to be validated by other
  #   keywords/oneOf-scopes/etc.
  # * The topmost validator that pushed a nil will pop the real cast and apply
  #   it after all validations have been done.
  #
  # As the stack can only contain a non-nil value, instead of using a list we
  # use a {level, value} tuple.
  defp push_cast(cast_stacks, data_path, cast) do
    case cast_stacks do
      # If the stack is already defined with nil we increment it and add the
      # cast
      %{^data_path => {n, nil}} ->
        %{cast_stacks | data_path => {n + 1, cast}}

      # If the stack is already defined with a cast we increment it and silently
      # ignore the new cast.
      #
      # We ignore it silently because while we had an implementation that could
      # track multiple casts added at the same sublevels, it was warrning false
      # positives too much. We would have to also track if we are in an allOf or
      # if/then vs. oneOf to only warn about actual conflicts.
      %{^data_path => {n, existing}} ->
        %{cast_stacks | data_path => {n + 1, existing}}

      # Define a new stack
      _ when not is_map_key(cast_stacks, data_path) ->
        Map.put(cast_stacks, data_path, {0, cast})
    end
  end

  defp pop_apply_cast(value, data_path, vctx) do
    %{cast_stacks: %{^data_path => stack} = cast_stacks} = vctx

    case stack do
      {0, nil} ->
        vctx = %{vctx | cast_stacks: Map.delete(cast_stacks, data_path)}
        {:ok, value, vctx}

      {0, cast} ->
        vctx = %{vctx | cast_stacks: Map.delete(cast_stacks, data_path)}
        Vocabulary.Cast.validate(value, cast, vctx)

      {n, cast} when n > 0 ->
        {:ok, value, %{vctx | cast_stacks: %{cast_stacks | data_path => {n - 1, cast}}}}
    end
  end

  @doc """
  Reduce over an enum with two accumulators, a user one, and the context.

  * The callback is called with `item, acc, vctx` for all items in the enum,
    regardless of previously returned values. Returning and error tuple does not
    stop the iteration.
  * When returning `{:ok, value, vctx}`, `value` will be the new user
    accumulator, and the new context is carried on.
  * When returning `{:error, vctx}`, the current accumulator is not changed, but
    the new returned context with errors is still carried on.
  * Returning an ok tuple after an error tuple on a previous item does not
    remove the errors from the context struct.

  The final return value is `{:ok, acc, vctx}` if all calls of the callback
  returned an OK tuple, `{:error, vctx}` otherwise.

  This is useful to call all possible validators for a given piece of data,
  collecting all possible errors without stopping, but still returning an error
  in the end if some error arose.
  """
  @spec reduce(Enumerable.t(), term, context, function) :: result
  def reduce(enum, datain, vctx, fun) when is_function(fun, 3) do
    {new_data, new_vctx} =
      Enum.reduce(enum, {datain, vctx}, fn item, {data, vctx} ->
        case fun.(item, data, vctx) do
          # When returning :ok, the errors may be empty or not, depending on
          # previous iterations.
          {:ok, new_data, new_vctx} ->
            {new_data, new_vctx}

          # When returning :error, an error MUST be set
          {:error, %ValidationContext{errors: [_ | _]} = new_vctx} ->
            {data, new_vctx}

          other ->
            raise "Invalid return from #{Exception.format_fa(fun, 3)}, expected {:ok, data, context} or {:error, term}, got: #{inspect(other)}"
        end
      end)

    return(new_data, new_vctx)
  end

  @doc """
  Validate the data with the given validators but separate the current
  evaluation context during the validation.

  Currently evaluated properties or items will not be seen as evaluated during
  the validation by the given `subschema`.
  """
  @spec validate_detach(term, eval_sub_path, validator, context) :: result
  def validate_detach(data, add_eval_path, subschema, %ValidationContext{} = vctx) do
    %{eval_path: eval_path, schema_path: schema_path} = vctx

    sub_vctx = %{
      vctx
      | evaluated: [%{}],
        errors: [],
        eval_path: append_eval_path(eval_path, add_eval_path),
        schema_path: append_schema_path(schema_path, add_eval_path)
    }

    case validate(data, subschema, sub_vctx) do
      {:ok, data, new_sub} -> {:ok, data, new_sub}
      {:error, new_sub} -> {:error, new_sub}
    end
  end

  @doc """
  Validates a sub term of the data, identified by `key`, which can be a property
  name (a string), or an array index (an integer).

  See `validate_as/4` to validate the same data point with a nested keyword. For
  instance `if`, `then` or `else`.
  """
  @spec validate_in(term, Builder.path_segment(), eval_sub_path, validator, context) :: result
  def validate_in(data, key, add_eval_path, subvalidators, vctx)
      when is_binary(key)
      when is_integer(key) do
    %ValidationContext{
      data_path: data_path,
      evaluated: evaluated,
      eval_path: eval_path,
      schema_path: schema_path
    } = vctx

    sub_vctx = %{
      vctx
      | data_path: [key | data_path],
        eval_path: append_eval_path(eval_path, add_eval_path),
        schema_path: append_schema_path(schema_path, add_eval_path),
        errors: [],
        evaluated: [%{} | evaluated]
    }

    case validate(data, subvalidators, sub_vctx) do
      {:ok, data, sub_vctx} ->
        # There should not be errors in sub at this point ?
        new_vctx = vctx |> add_evaluated(key) |> merge_errors(sub_vctx)
        {:ok, data, new_vctx}

      {:error, %ValidationContext{errors: [_ | _]} = sub_vctx} ->
        {:error, merge_errors(vctx, sub_vctx)}
    end
  end

  @doc """
  Validates data with a sub part of the schema, for instance `if`, `then` or
  `else`. Data path will not change in the context.

  See `validate_in/5` to validate sub terms of the data.
  """
  @spec validate_as(term, eval_sub_path(), validator(), context) :: result
  def validate_as(data, add_eval_path, subvalidators, vctx) do
    %ValidationContext{evaluated: evaluated, eval_path: eval_path, schema_path: schema_path} = vctx

    sub_vctx = %{
      vctx
      | eval_path: append_eval_path(eval_path, add_eval_path),
        schema_path: append_schema_path(schema_path, add_eval_path),
        cast_stacks: %{},
        errors: [],
        evaluated: [%{} | evaluated]
    }

    case validate(data, subvalidators, sub_vctx) do
      {:ok, data, sub_vctx} ->
        # There should not be errors in sub at this point ?
        new_vctx = vctx |> merge_tracked(sub_vctx) |> merge_errors(sub_vctx)
        {:ok, data, new_vctx}

      {:error, %ValidationContext{errors: [_ | _]} = sub_vctx} ->
        {:error, merge_errors(vctx, sub_vctx)}
    end
  end

  @spec validate_ref(term, Key.t(), eval_sub_path(), context) :: result
  def validate_ref(data, ref, eval_path, vctx) do
    with_scope(vctx, ref, {:ref, eval_path, ref}, fn vctx ->
      do_validate_ref(data, ref, vctx)
    end)
  end

  defp do_validate_ref(data, ref, %ValidationContext{} = vctx) do
    subvalidators = checkout_ref(vctx, ref)

    separate_vctx = %{vctx | errors: []}

    case validate(data, subvalidators, separate_vctx) do
      {:ok, data, separate_vctx} ->
        {:ok, data, merge_tracked(vctx, separate_vctx)}

      {:error, %ValidationContext{errors: [_ | _]} = separate_vctx} ->
        {:error, merge_errors(vctx, separate_vctx)}
    end
  end

  defp with_scope(%ValidationContext{} = vctx, sub_key, add_eval_path, fun) do
    %{scope: scopes, eval_path: eval_path, schema_path: schema_path} = vctx

    # Premature optimization that can be removed: skip appending scope if it is
    # the same as the current one.
    sub_vctx =
      case {Key.namespace_of(sub_key), scopes} do
        {same, [same | _]} ->
          %{
            vctx
            | eval_path: append_eval_path(eval_path, add_eval_path),
              schema_path: append_schema_path(schema_path, add_eval_path)
          }

        {new_scope, scopes} ->
          %{
            vctx
            | scope: [new_scope | scopes],
              eval_path: append_eval_path(eval_path, add_eval_path),
              schema_path: append_schema_path(schema_path, add_eval_path)
          }
      end

    case fun.(sub_vctx) do
      {:ok, data, vctx} -> {:ok, data, %{vctx | scope: scopes, eval_path: eval_path}}
      {:error, vctx} -> {:error, %{vctx | scope: scopes, eval_path: eval_path}}
    end
  end

  defp append_eval_path(eval_path, add_eval_path) when is_list(add_eval_path) do
    :lists.flatten(add_eval_path, eval_path)
  end

  defp append_eval_path(eval_path, segment) do
    [segment | eval_path]
  end

  defp append_schema_path(schema_path, {tag, arg}) when is_atom(arg) when is_integer(arg) when is_binary(arg) do
    [{tag, arg} | schema_path]
  end

  defp append_schema_path(schema_path, arg) when is_atom(arg) when is_integer(arg) when is_binary(arg) do
    [arg | schema_path]
  end

  defp append_schema_path(schema_path, {:ref, _, _}) do
    schema_path
  end

  defp append_schema_path(schema_path, [h | t]) do
    append_schema_path(t, append_schema_path(schema_path, h))
  end

  defp append_schema_path(schema_path, []) do
    schema_path
  end

  defp merge_errors(%ValidationContext{} = vctx, %ValidationContext{} = sub) do
    %{errors: vctx_errors} = vctx
    %{errors: sub_errors} = sub
    %{vctx | errors: do_merge_errors(vctx_errors, sub_errors)}
  end

  defp do_merge_errors([], sub_errors) do
    sub_errors
  end

  defp do_merge_errors(vctx_errors, []) do
    vctx_errors
  end

  defp do_merge_errors(vctx_errors, sub_errors) do
    # Errors are not appended. We rather build a deep list. Errors are only
    # flattened at the end of the validation when returning a ValidationError.
    [vctx_errors, sub_errors]
  end

  @doc """
  Merges tracking data from the sub context into the main context. This is
  useful to keep information defined by subschemas for the same data level as
  the parent schema. Such sub schemas are defined with oneOf/allOf/... or $ref.

  Tracking data:

  * Evaluated paths, to work with unevaluated properties/items
  * Cast functions (defschema,defcast)
  """
  @spec merge_tracked(context, context) :: context
  def merge_tracked(%ValidationContext{} = vctx, %ValidationContext{} = sub) do
    %{cast_stacks: top_cast_stacks, evaluated: [top_vctx | rest_vctx]} = vctx
    %{cast_stacks: sub_cast_stacks, evaluated: [top_sub | _rest_sub]} = sub

    cast_stacks =
      Map.merge(top_cast_stacks, sub_cast_stacks, fn
        _dpath, same, same -> same
        _dpath, {n, nil}, {_, nil} -> {n, nil}
        _dpath, {n, nil}, {_, cast} -> {n, cast}
      end)

    %{vctx | cast_stacks: cast_stacks, evaluated: [Map.merge(top_vctx, top_sub) | rest_vctx]}
  end

  @spec return(term, context) :: result
  def return(data, %ValidationContext{errors: []} = vctx) do
    {:ok, data, vctx}
  end

  def return(_data, %ValidationContext{errors: [_ | _]} = vctx) do
    {:error, vctx}
  end

  defp checkout_ref(%{scope: scope} = vctx, {:dynamic_anchor, ns, anchor}) do
    case checkout_dynamic_ref(scope, vctx, anchor) do
      :error -> checkout_ref(vctx, {:anchor, ns, anchor})
      {:ok, v} -> v
    end
  end

  defp checkout_ref(%{validators: vds}, vkey) do
    Map.fetch!(vds, vkey)
  end

  defp checkout_dynamic_ref([h | scope], vctx, anchor) do
    # Recursion first as the outermost scope should have priority. If the
    # dynamic ref resolution fails with all outer scopes, then actually try to
    # resolve from this scope.
    with :error <- checkout_dynamic_ref(scope, vctx, anchor) do
      Map.fetch(vctx.validators, {:dynamic_anchor, h, anchor})
    end
  end

  defp checkout_dynamic_ref([], _, _) do
    :error
  end

  defp boolean_schema_error(vctx, %BooleanSchema{valid?: false} = bs, data) do
    %Error{
      kind: :boolean_schema,
      data: data,
      data_path: vctx.data_path,
      eval_path: vctx.eval_path,
      schema_path: bs.schema_path,
      formatter: __MODULE__,
      args: []
    }
  end

  defmacro with_error(vctx, kind, data, args) do
    quote bind_quoted: binding() do
      JSV.Validator.__with_error__(__MODULE__, vctx, kind, data, args)
    end
  end

  @doc false
  @spec __with_error__(module, context, atom, term, term) :: context
  def __with_error__(module, vctx, kind, data, args) when is_list(args) or is_map(args) do
    if [] == vctx.schema_path do
      raise "empty schema path"
    end

    error = %Error{
      kind: kind,
      data: data,
      data_path: vctx.data_path,
      eval_path: vctx.eval_path,
      schema_path: vctx.schema_path,
      formatter: module,
      args: args
    }

    add_error(vctx, error)
  end

  defp add_error(vctx, error) do
    %ValidationContext{errors: errors} = vctx
    %{vctx | errors: [error | errors]}
  end

  defp add_evaluated(%ValidationContext{} = vctx, key) do
    %{evaluated: [current | ev]} = vctx
    current = Map.put(current, key, true)
    %{vctx | evaluated: [current | ev]}
  end

  @spec list_evaluaded(context) :: [String.t() | integer()]
  def list_evaluaded(vctx) do
    %{evaluated: [current | _]} = vctx
    Map.keys(current)
  end

  @spec flat_errors(context) :: [Error.t()]
  def flat_errors(vctx) do
    :lists.flatten(vctx.errors)
  end

  @spec to_error(context) :: ValidationError.t()
  def to_error(vctx) do
    ValidationError.of(flat_errors(vctx))
  end

  @doc """
  Returns whether the given context contains errors.
  """
  @spec error?(context) :: boolean
  def error?(vctx) do
    case vctx do
      %ValidationContext{errors: [_ | _]} -> true
      %ValidationContext{errors: []} -> false
    end
  end

  @doc false
  # error formatter implementation for the boolean schema
  @spec format_error(:boolean_schema, term, term) :: binary
  def format_error(:boolean_schema, %{}, _data) do
    "value was rejected from boolean schema: false"
  end
end
