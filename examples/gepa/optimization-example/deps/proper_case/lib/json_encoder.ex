defmodule ProperCase.JSONEncoder do
  @moduledoc """
    module that exposes a version of `encode_to_iodata!/1` that transforms data
    before encoding to json. This is designed to work with phoenix.

    Options:
    transform - artity 1 function that is executed before passing the result to json_encoder.encode_to_iodata!
    json_encoder - JSON encoder that implements encode_to_iodata!. Default: Jason

    usage:
      def MyApp.CustomJSONEncoder do
        use ProperCase.JSONEncoder, transform: &ProperCase.to_camel_case/1
      end

      config.exs

      :phoenix, :format_encoders, json: MyApp.CustomJSONEncoder

  """

  defmacro __using__(options) do
    json_encoder = Keyword.get(options, :json_encoder, Jason)

    quote do
      def encode_to_iodata!(data) do
        data
        |> unquote(options[:transform]).()
        |> unquote(json_encoder).encode_to_iodata!
      end
    end
  end
end
