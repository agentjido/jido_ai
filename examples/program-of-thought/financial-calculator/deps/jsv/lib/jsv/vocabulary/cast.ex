defmodule JSV.Vocabulary.Cast do
  alias JSV.Helpers.StringExt
  alias JSV.Validator

  use JSV.Vocabulary,
    # Priority is meaningless here as this vocabulary is handled by the library
    # core. But it takes precedences over all other vocabularies when registering
    # a cast during validation, so we mark it as zero.
    priority: :internal

  @moduledoc false

  @impl true
  def init_validators([]) do
    %{}
  end

  take_keyword :"jsv-cast", [module_str, arg], vds, builder, _ do
    module = unwrap_ok(StringExt.safe_string_to_existing_module(module_str))
    {Map.put(vds, :"jsv-cast", {module, arg}), builder}
  end

  ignore_any_keyword()

  @impl true
  def finalize_validators(map) do
    case map_size(map) do
      0 -> :ignore
      _ -> map
    end
  end

  @impl true
  def validate(data, %{"jsv-cast": {module, arg}}, vctx) do
    cond do
      Validator.error?(vctx) ->
        {:ok, data, vctx}

      vctx.opts[:cast] ->
        call_cast(module, arg, data, vctx)

      :other ->
        {:ok, data, vctx}
    end
  end

  defp call_cast(module, arg, data, vctx) do
    case module.__jsv__(arg, data) do
      {:ok, new_data} ->
        {:ok, new_data, vctx}

      {:error, reason} ->
        {:error,
         JSV.Validator.__with_error__(__MODULE__, vctx, :"jsv-cast", data, module: module, reason: reason, arg: arg)}
    end
  rescue
    e in [UndefinedFunctionError, FunctionClauseError] ->
      case e do
        %{module: ^module, function: :__jsv__} ->
          {:error,
           JSV.Validator.__with_error__(__MODULE__, vctx, :"bad-cast", data, module: module, reason: e, arg: arg)}

        _ ->
          reraise e, __STACKTRACE__
      end
  end

  @impl true
  def format_error(:"jsv-cast", args, data) do
    if function_exported?(args.module, :format_error, 3) do
      case args.module.format_error(args.arg, args.reason, data) do
        message when is_binary(message) -> {:cast, message}
        other -> other
      end
    else
      {:cast, "cast failed"}
    end
  end

  def format_error(:"bad-cast", _args, _data) do
    {:cast, "invalid cast"}
  end
end
