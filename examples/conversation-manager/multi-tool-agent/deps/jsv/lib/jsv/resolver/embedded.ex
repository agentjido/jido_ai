defmodule JSV.Resolver.Embedded do
  alias JSV.Resolver.Internal

  @behaviour JSV.Resolver

  mapping = %{
    "http://json-schema.org/draft-07/schema" => __MODULE__.Draft7.Schema,
    "https://json-schema.org/draft/2020-12/schema" => __MODULE__.Draft202012.Schema,
    "https://json-schema.org/draft/2020-12/meta/core" => __MODULE__.Draft202012.Meta.Core,
    "https://json-schema.org/draft/2020-12/meta/validation" => __MODULE__.Draft202012.Meta.Validation,
    "https://json-schema.org/draft/2020-12/meta/applicator" => __MODULE__.Draft202012.Meta.Applicator,
    "https://json-schema.org/draft/2020-12/meta/unevaluated" => __MODULE__.Draft202012.Meta.Unevaluated,
    "https://json-schema.org/draft/2020-12/meta/meta-data" => __MODULE__.Draft202012.Meta.MetaData,
    "https://json-schema.org/draft/2020-12/meta/format-annotation" => __MODULE__.Draft202012.Meta.FormatAnnotation,
    "https://json-schema.org/draft/2020-12/meta/format-assertion" => __MODULE__.Draft202012.Meta.FormatAssertion,
    "https://json-schema.org/draft/2020-12/meta/content" => __MODULE__.Draft202012.Meta.Content
  }

  ids_list = mapping |> Map.keys() |> Enum.sort(:desc)

  @moduledoc """
  A `JSV.Resolver` implementation that resolves known schemas shipped as part of
  the `JSV` library.

  Internal URIs such as `jsv:module:<module name>` are delegated to the
  #{inspect(Internal)} resolver.

  ### Embedded schemas

  #{Enum.map(ids_list, &["* ", &1, "\n"])}
  """

  @impl true
  def resolve(url, opts)

  Enum.each(mapping, fn {url, module} ->
    def resolve(unquote(url), _) do
      {:normal, unquote(module).json_schema()}
    end
  end)

  def resolve(other, _) do
    {:error, {:not_embedded, other}}
  end

  @doc """
  Returns the list of meta schemas embedded in this resolver. The IDs are given
  in normalized form, _i.e._ URLs without fragments.
  """

  @spec embedded_normalized_ids :: [String.t()]
  def embedded_normalized_ids do
    unquote(ids_list)
  end
end
