defmodule Uniq.Macros do
  otp_version =
    case String.split(to_string(:erlang.system_info(:otp_release)), ".", trim: true) do
      [maj] ->
        Version.parse!("#{maj}.0.0")

      [maj, min] ->
        Version.parse!("#{maj}.#{min}.0")

      [maj, min, patch] ->
        Version.parse!("#{maj}.#{min}.#{patch}")

      [maj, min, patch | _] ->
        Version.parse!("#{maj}.#{min}.#{patch}")
    end

  hex_encoding = Version.match?(otp_version, ">= 24.0.0", allow_pre: true)

  @builtins [
    binary: [
      encode_hex: hex_encoding,
      decode_hex: hex_encoding
    ]
  ]

  defmacro defextension(module, do: body) do
    module = Macro.expand(module, __ENV__)

    if Code.ensure_loaded?(module) do
      quote do
        unquote(body)
      end
    end
  end

  defmacro defshim({_, meta, _} = function, [to: module], do: fallback) do
    {name, args} =
      case function do
        {:when, _, _} ->
          raise ArgumentError, "guards are not allowed in defshim/3"

        _ ->
          case Macro.decompose_call(function) do
            {_, _} = pair -> pair
            _ -> raise ArgumentError, "invalid syntax in defshim/3 #{Macro.to_string(function)}"
          end
      end

    if get_in(@builtins, [module, name]) == true do
      {:defdelegate, meta, [{name, meta, args}, [to: module]]}
    else
      quote do
        unquote(fallback)
      end
    end
  end
end
