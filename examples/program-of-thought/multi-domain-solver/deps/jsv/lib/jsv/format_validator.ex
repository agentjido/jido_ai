defmodule JSV.FormatValidator do
  @moduledoc """
  Behaviour for format validator implementations.

  Such implementations must be given to `JSV.build/2` in the `:formats` option:

      JSV.build!(raw_schema,
        resolver: resolver,
        formats: [MyModule | JSV.default_format_validator_modules()]
      )

  Each given module is interrogated for format support when a schema is built.
  Modules earlier in the list take precedence and if a format is found in the
  returned value of the `c:supported_formats/0` callback, the module is selected
  for compilation and no other module will be tried.

  A module can declare multiple formats.
  """

  @type format :: String.t()

  @doc """
  Returns the list of the supported formats, as strings.
  """
  @callback supported_formats :: [format]

  @doc """
  Returns `true` if the given format should be used for the input data type.

  For instance, the `"date"` format will not be validated if the input data is
  not a string.

  No validation should be done in this callback, only the _type_ of the data
  should be considered.
  """
  @callback applies_to_type?(format, data :: term) :: boolean

  @doc """
  Receives the schema format as string, and the data.

  Returns a result tuple with data optionally casted to a more meaningful data
  structure (for instance returning a `Date` struct instead of the string
  representation of the date).
  """
  @callback validate_cast(format, data :: term) :: {:ok, term} | {:error, term}
end
