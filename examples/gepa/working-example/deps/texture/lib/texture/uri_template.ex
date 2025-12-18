defmodule Texture.UriTemplate do
  alias Texture.UriTemplate.Matcher
  alias Texture.UriTemplate.Renderer
  alias Texture.UriTemplate.TemplateMatchError

  @moduledoc ~S"""
  URI Template parser implementation following RFC 6570 (levels 1–4).

  Parsing returns a `%Texture.UriTemplate{}` struct. Use `render/2` to expand it
  with variable values provided either as atom or binary keys.

  ## Parsing

      {:ok, template} = Texture.UriTemplate.parse("/users/{id}")
      %Texture.UriTemplate{}

  An invalid template returns an error tuple:

      iex> Texture.UriTemplate.parse("/x/{not_closed")
      {:error, {:invalid_value, "{not_closed"}}

  ## Rendering

  Provide a map whose keys are either atoms or binaries. Values are coerced
  to strings; lists and exploded maps are supported per RFC 6570.

      iex> {:ok, t} = Texture.UriTemplate.parse("https://ex.com{/ver}{/res*}{?q,lang}{&page}")
      iex> Texture.UriTemplate.render(t, %{ver: "v1", res: ["users", 42], q: "café", lang: :fr, page: 2})
      "https://ex.com/v1/users/42?q=caf%C3%A9&lang=fr&page=2"

  Reserved expansion keeps reserved characters (e.g. '+'):

      iex> {:ok, t} = Texture.UriTemplate.parse("/files{+path}")
      iex> Texture.UriTemplate.render(t, %{path: "/a/b c"})
      "/files/a/b%20c"

  Simple expansion percent-encodes reserved characters:

      iex> {:ok, t} = Texture.UriTemplate.parse("/files/{path}")
      iex> Texture.UriTemplate.render(t, %{path: "/a/b c"})
      "/files/%2Fa%2Fb%20c"

  Exploded list path segments:

      iex> {:ok, t} = Texture.UriTemplate.parse("/api{/segments*}")
      iex> Texture.UriTemplate.render(t, %{segments: ["v1", "users", 42]})
      "/api/v1/users/42"

  Query continuation & omission of undefined variables:

      iex> {:ok, t} = Texture.UriTemplate.parse("?fixed=1{&x,y}")
      iex> Texture.UriTemplate.render(t, %{x: 2})
      "?fixed=1&x=2"

  Fragment expansion with unicode & prefix modifier:

      iex> {:ok, t} = Texture.UriTemplate.parse("{#frag:6}")
      iex> Texture.UriTemplate.render(t, %{frag: "café-bar"})
      "#caf%C3%A9-b"

  Empty list omits expression:

      iex> {:ok, t} = Texture.UriTemplate.parse("/s{?list}")
      iex> Texture.UriTemplate.render(t, %{list: []})
      "/s"

  ## Notes

  * Undefined variables are silently omitted.
  * Empty string values may contribute a key without '=' (for certain operators like ';').
  * Order of exploded map query parameters is not guaranteed (maps are unordered).
  """
  @external_resource "priv/grammars/uri-template.abnf"

  @enforce_keys [:parts, :raw]
  defstruct @enforce_keys

  use AbnfParsec,
    abnf_file: "priv/grammars/uri-template.abnf",
    unbox: ["URI-Template", "varchar", "op-level2", "op-level3", "op-reserve", "modifier-level4"],
    unwrap: ["literals", "explode"],
    untag: ["max-length"],
    ignore: [],
    private: true

  @type t :: %__MODULE__{parts: term, raw: binary}

  @doc """
  Parses an URI template into an internal representation.
  """
  @spec parse(binary) :: {:ok, t} | {:error, term}
  def parse(data) do
    case uri_template(data) do
      {:ok, parts, "", _, _, _} -> {:ok, %__MODULE__{parts: post_parse(parts), raw: data}}
      {:ok, _, rest, _, _, _} -> {:error, {:invalid_value, rest}}
    end
  end

  @spec parse!(binary) :: t
  def parse!(data) do
    case parse(data) do
      {:ok, t} -> t
      {:error, {:invalid_value, rest}} -> raise ArgumentError, "invalid template, syntax error before: #{inspect(rest)}"
    end
  end

  defp post_parse(parts) do
    parts
    |> post_parse_literals()
    |> Enum.map(&post_parse_part/1)
  end

  defp post_parse_literals(parts) do
    parts
    |> Enum.chunk_by(fn
      {:literals, _} -> true
      _ -> false
    end)
    |> Enum.flat_map(fn
      [{:literals, _} | _] = lits -> [{:lit, join_literals(lits)}]
      parts -> parts
    end)
  end

  defp join_literals(literals) do
    Enum.reduce(literals, <<>>, fn
      {:literals, c}, acc when is_integer(c) -> <<acc::binary, c>>
      {:literals, {:ucschar, [c]}}, acc -> <<acc::binary, c::utf8>>
      {:literals, {:iprivate, [c]}}, acc -> <<acc::binary, c::utf8>>
      {:literals, {:pct_encoded, graphemes}}, acc -> <<acc::binary, Enum.join(graphemes)::binary>>
    end)
  end

  defp post_parse_part(part) do
    case part do
      {:lit, _} = lit ->
        lit

      {:expression, ["{" | expr]} ->
        {"}", expr} = List.pop_at(expr, -1)

        {op, varlist} =
          case expr do
            [operator: [op], variable_list: varlist] -> {op, post_parse_varlist(varlist)}
            [variable_list: varlist] -> {:default, post_parse_varlist(varlist)}
          end

        {:expr, op, varlist}
    end
  end

  defp post_parse_varlist(elems) do
    Enum.flat_map(elems, fn
      "," ->
        []

      {:varspec, [varname: varname]} ->
        [{:var, Enum.join(varname), nil}]

      {:varspec, [varname: varname, explode: "*"]} ->
        [{:var, Enum.join(varname), :explode}]

      {:varspec, [varname: varname, prefix: [":", n_aslist]]} ->
        {max_len, ""} = Integer.parse(List.to_string(n_aslist))
        [{:var, Enum.join(varname), {:prefix, max_len}}]
    end)
  end

  @doc """
  Expands a URI template with provided variable values.

  Returns a rendered URI string by expanding all template expressions with the
  given parameters. Variables are looked up by name (as atoms or binaries) and
  values are automatically coerced to strings. Follows RFC 6570 levels 1–4.

  ## Supported Operators

  All RFC 6570 operators are supported:

  * **Default** (no operator): `{var}` – Simple string expansion with
    percent-encoding
  * **Reserved** (`+`): `{+var}` – Reserved expansion, keeps `/`, `?`, `&`, etc.
  * **Fragment** (`#`): `{#var}` – Fragment identifier expansion
  * **Label** (`.`): `{.var}` – Dot-prefixed label expansion
  * **Path segment** (`/`): `{/var}` – Path segment expansion
  * **Path-style parameter** (`;`): `{;var}` – Semicolon-prefixed parameters
  * **Query** (`?`): `{?var}` – Form-style query parameters
  * **Query continuation** (`&`): `{&var}` – Query continuation

  ## Basic Examples

      iex> t = Texture.UriTemplate.parse!("http://example.com/users/{id}")
      iex> Texture.UriTemplate.render(t, %{id: "42"})
      "http://example.com/users/42"

      iex> t = Texture.UriTemplate.parse!("http://example.com/users/{id}")
      iex> Texture.UriTemplate.render(t, %{"id" => "42"})
      "http://example.com/users/42"

      iex> t = Texture.UriTemplate.parse!("http://example.com{?q,lang}")
      iex> Texture.UriTemplate.render(t, %{q: "café", lang: "fr"})
      "http://example.com?q=caf%C3%A9&lang=fr"

      iex> t = Texture.UriTemplate.parse!("http://example.com/api{/version,resource}")
      iex> Texture.UriTemplate.render(t, %{version: "v1", resource: "users"})
      "http://example.com/api/v1/users"

  ## Reserved vs Simple Expansion

  Simple expansion percent-encodes reserved characters:

      iex> t = Texture.UriTemplate.parse!("http://example.com/files/{path}")
      iex> Texture.UriTemplate.render(t, %{path: "/a/b c"})
      "http://example.com/files/%2Fa%2Fb%20c"

  Reserved expansion (`+`) keeps reserved characters like `/`:

      iex> t = Texture.UriTemplate.parse!("http://example.com/files{+path}")
      iex> Texture.UriTemplate.render(t, %{path: "/a/b c"})
      "http://example.com/files/a/b%20c"

  ## List Expansion

  Lists are expanded differently based on the operator and explode modifier:

      # Simple expansion (comma-separated)
      iex> t = Texture.UriTemplate.parse!("http://example.com/{segments}")
      iex> Texture.UriTemplate.render(t, %{segments: ["v1", "users", "42"]})
      "http://example.com/v1,users,42"

      # Path segment expansion with explode
      iex> t = Texture.UriTemplate.parse!("http://example.com/api{/segments*}")
      iex> Texture.UriTemplate.render(t, %{segments: ["v1", "users", "42"]})
      "http://example.com/api/v1/users/42"

      # Query parameters with explode
      iex> t = Texture.UriTemplate.parse!("http://example.com{?list*}")
      iex> Texture.UriTemplate.render(t, %{list: ["red", "green"]})
      "http://example.com?list=red&list=green"

      # Query parameters without explode (comma-separated)
      iex> t = Texture.UriTemplate.parse!("http://example.com{?list}")
      iex> Texture.UriTemplate.render(t, %{list: ["red", "green"]})
      "http://example.com?list=red,green"

  ## Map Expansion

  Maps and keyword lists can be expanded with the explode modifier:

      # Query with exploded map
      iex> t = Texture.UriTemplate.parse!("http://example.com{?map*}")
      iex> Texture.UriTemplate.render(t, %{map: %{a: "1", b: "2"}})
      "http://example.com?a=1&b=2"

      # Semicolon parameters with exploded keyword list
      iex> t = Texture.UriTemplate.parse!("http://example.com{;params*}")
      iex> Texture.UriTemplate.render(t, %{params: [x: "1", y: "2"]})
      "http://example.com;x=1;y=2"

      # Non-exploded map (comma-separated key,value pairs)
      iex> t = Texture.UriTemplate.parse!("http://example.com/{map}")
      iex> Texture.UriTemplate.render(t, %{map: %{a: "1", b: "2"}})
      "http://example.com/a,1,b,2"

  ## Prefix Modifier

  The prefix modifier (`:n`) truncates values to a maximum length:

      iex> t = Texture.UriTemplate.parse!("http://example.com/p/{var:3}")
      iex> Texture.UriTemplate.render(t, %{var: "abcdef"})
      "http://example.com/p/abc"

      # Works with reserved expansion
      iex> t = Texture.UriTemplate.parse!("http://example.com{+path:5}")
      iex> Texture.UriTemplate.render(t, %{path: "/a/b/c"})
      "http://example.com/a/b/"

      # Works with fragment expansion
      iex> t = Texture.UriTemplate.parse!("http://example.com{#frag:6}")
      iex> Texture.UriTemplate.render(t, %{frag: "café-bar"})
      "http://example.com#caf%C3%A9-b"

  ## Undefined Variables

  Undefined variables are silently omitted from the output:

      iex> t = Texture.UriTemplate.parse!("http://example.com{/ver}{?q,lang}")
      iex> Texture.UriTemplate.render(t, %{q: "search"})
      "http://example.com?q=search"

      iex> t = Texture.UriTemplate.parse!("http://example.com/users{/id}")
      iex> Texture.UriTemplate.render(t, %{})
      "http://example.com/users"

  ## Empty Values

  Empty strings contribute differently based on the operator:

      # Simple expansion: empty string outputs nothing
      iex> t = Texture.UriTemplate.parse!("http://example.com/a{empty}b")
      iex> Texture.UriTemplate.render(t, %{empty: ""})
      "http://example.com/ab"

      # Query parameter: key with equals sign
      iex> t = Texture.UriTemplate.parse!("http://example.com{?x}")
      iex> Texture.UriTemplate.render(t, %{x: ""})
      "http://example.com?x="

      # Semicolon parameter: key without equals sign
      iex> t = Texture.UriTemplate.parse!("http://example.com{;id}")
      iex> Texture.UriTemplate.render(t, %{id: ""})
      "http://example.com;id"

  Empty lists and maps omit the entire expression:

      iex> t = Texture.UriTemplate.parse!("http://example.com/s{?list*}")
      iex> Texture.UriTemplate.render(t, %{list: []})
      "http://example.com/s"

      iex> t = Texture.UriTemplate.parse!("http://example.com/p{;map*}")
      iex> Texture.UriTemplate.render(t, %{map: %{}})
      "http://example.com/p"

  ## Unicode and Encoding

  Unicode characters are properly percent-encoded:

      iex> t = Texture.UriTemplate.parse!("http://example.com/q/{term}")
      iex> Texture.UriTemplate.render(t, %{term: "café"})
      "http://example.com/q/caf%C3%A9"

      # Even in reserved expansion (non-ASCII must be encoded per RFC 6570)
      iex> t = Texture.UriTemplate.parse!("http://example.com/u/{+term}")
      iex> Texture.UriTemplate.render(t, %{term: "東京/渋谷"})
      "http://example.com/u/%E6%9D%B1%E4%BA%AC/%E6%B8%8B%E8%B0%B7"

      iex> t = Texture.UriTemplate.parse!("http://example.com{?emoji}")
      iex> Texture.UriTemplate.render(t, %{emoji: "🙂"})
      "http://example.com?emoji=%F0%9F%99%82"

  ## Value Coercion

  Non-string values are automatically coerced to strings:

      iex> t = Texture.UriTemplate.parse!("http://example.com/t/{num}/{bool}")
      iex> Texture.UriTemplate.render(t, %{num: 0, bool: false})
      "http://example.com/t/0/false"

  ## Complex Examples

      # Mixed expressions with multiple operators
      iex> t = Texture.UriTemplate.parse!("http://example.com{/ver}{/res*}{?q,lang}{&page}")
      iex> Texture.UriTemplate.render(t, %{ver: "v1", res: ["users", 42], q: "café", lang: "fr", page: 2})
      "http://example.com/v1/users/42?q=caf%C3%A9&lang=fr&page=2"

      # Query continuation with partial matches
      iex> t = Texture.UriTemplate.parse!("http://example.com?fixed=1{&x,y}")
      iex> Texture.UriTemplate.render(t, %{x: 2})
      "http://example.com?fixed=1&x=2"

  ## Implementation Notes

  * Parameter keys can be atoms or binaries – both `%{id: "42"}` and `%{"id" =>
    "42"}` work
  * Literal parts of templates (outside `{` `}`) are returned as-is, not
    percent-encoded
  * Map key order is not guaranteed in exploded expansions
  * Empty lists are treated as undefined values and omit the expression
  * Exploding scalar values (e.g., `{var*}`) wraps them in a list
  * Lists of tuples (including keyword lists) are rendered as maps when exploded
  * Tuples as standalone values are not supported
  """
  @spec render(t, %{optional(atom) => term, optional(binary) => term}) :: binary
  def render(%__MODULE__{} = t, params) do
    Renderer.render(t, params)
  end

  @doc """
  Extracts variables from a URL based on a parsed URI template.

  Returns `{:ok, map}` on success or `{:error, exception}` on failure.

  See `match!/2` for examples and detailed documentation.
  """
  @spec match(t, binary) :: {:ok, %{binary => term}} | {:error, term}
  def match(%__MODULE__{} = t, url) do
    {:ok, Matcher.match!(t, url)}
  rescue
    e in TemplateMatchError -> {:error, e}
  end

  @doc """
  Same as `match/2` but raises `Texture.UriTemplate.TemplateMatchError` on failure.

  This implementation has **limited support** and is designed for
  straightforward, simple templates. Use it for basic path and query parameter
  extraction. Rendering is a lossy operation, so the reverse operation cannot
  always regenerate original values.

  ## Supported Operators

  Only three operators are supported:

  * **Default** (no operator): `{foo}`
  * **Path segment** (`/`): `{/foo}`
  * **Query** (`?`): `{?foo}`

  Other operators like `+`, `#`, `.`, `;`, `&` are **not supported** for
  matching.

  ## Unsupported Features

  * **Prefix modifier** (`:n`): Templates with prefix modifiers like `{var:3}`
    are not supported for matching and will raise an error

  ## Basic Examples

      iex> t = Texture.UriTemplate.parse!("http://example.com/{foo}")
      iex> Texture.UriTemplate.match!(t, "http://example.com/hello")
      %{"foo" => "hello"}

      iex> t = Texture.UriTemplate.parse!("http://example.com/{foo}/{bar}")
      iex> Texture.UriTemplate.match!(t, "http://example.com/hello/world")
      %{"foo" => "hello", "bar" => "world"}

      iex> t = Texture.UriTemplate.parse!("http://example.com{/version,resource}")
      iex> Texture.UriTemplate.match!(t, "http://example.com/v1/users")
      %{"version" => "v1", "resource" => "users"}

      iex> t = Texture.UriTemplate.parse!("http://example.com/api{?foo,bar}")
      iex> Texture.UriTemplate.match!(t, "http://example.com/api?foo=1&bar=2")
      %{"foo" => "1", "bar" => "2"}

  ## More Complex Examples

      iex> t = Texture.UriTemplate.parse!("http://example.com/search{?foo*,bar}")
      iex> Texture.UriTemplate.match!(t, "http://example.com/search?foo=1&foo=2&foo=3&bar=hello")
      %{"foo" => ["1", "2", "3"], "bar" => "hello"}

      iex> t = Texture.UriTemplate.parse!("http://example.com/api{?map*,simple}")
      iex> Texture.UriTemplate.match!(t, "http://example.com/api?a=1&b=&simple=value")
      %{"map" => %{"a" => "1", "b" => ""}, "simple" => "value"}

  ## Behavior Details

  ### Empty Values

  * Empty parameter values return `nil`
  * Lists containing empty strings preserve them: `["", "b", ""]`
  * Empty values in maps preserve empty keys or values

  ### Value Types

  * All extracted values are strings (including numeric-like values)
  * Unicode characters are properly decoded
  * Percent-encoding is handled automatically

  ### List Matching

  * Lists are comma-separated in default and query operators
  * With other operators,lLists are comma-separated only when the parameter is
    not exploded .
  * With multiple parameters, the last accumulates remaining values as a list
  * Insufficient values assign `nil` to remaining parameters

  Examples:

      # Lists with comma separator
      iex> t = Texture.UriTemplate.parse!("{foo}")
      iex> Texture.UriTemplate.match!(t, "1,2,3")
      %{"foo" => ["1", "2", "3"]}

      # Multiple params share list values
      iex> t = Texture.UriTemplate.parse!("{foo,bar}")
      iex> Texture.UriTemplate.match!(t, "1,2,3")
      %{"foo" => "1", "bar" => ["2", "3"]}

  ### Exploded Parameters (`*`)

  * Exploded lists take all matching items into a list
  * Exploded maps take all `key=value` pairs into a map
  * Non-exploded maps are ambiguous and parsed as lists

  Examples:

      # Path segments with exploded list
      iex> t = Texture.UriTemplate.parse!("{/foo*}")
      iex> Texture.UriTemplate.match!(t, "/a/b/c")
      %{"foo" => ["a", "b", "c"]}

  ### Query Parameters

  * Parameters are matched by name, not position
  * Order doesn't matter for query parameters
  * Duplicate names in exploded lists accumulate into a list
  * First occurrence wins for duplicate non-exploded parameters

  Examples:

  Query parameters (`{?foo,bar*,baz*}`) use a three-phase matching algorithm:

  1. Each non-exploded parameter takes its matching `key=value` pair from the
     URL by name
  2. Exploded parameters that have matching names in the URL collect all
     occurrences into a list (e.g., `foo=1&foo=2` → `["1", "2"]`)
  3. The first exploded parameter that hasn't matched any names takes all
     remaining `key=value` pairs as a map

          iex> t = Texture.UriTemplate.parse!("{?none,simple,items*,rest*,none_expl*}")
          iex> Texture.UriTemplate.match!(t, "?extra=1&other=2&items=a&items=b&simple=value")
          %{
            "none" => nil,
            "simple" => "value",
            "items" => ["a", "b"],
            "rest" => %{"extra" => "1", "other" => "2"},
            "none_expl" => nil
          }

  ### Parameter Skipping

  Extra query parameters that don't match any template variable are silently
  ignored. This allows matching URLs with tracking parameters added by external
  tools

  ### Value Encoding

  * Percent-encoding is handled automatically
  * Unicode characters are properly decoded

  Examples:

      # Percent-encoded values
      iex> t = Texture.UriTemplate.parse!("{foo}")
      iex> Texture.UriTemplate.match!(t, "hello%20world")
      %{"foo" => "hello world"}

      # Query with empty parameter
      iex> t = Texture.UriTemplate.parse!("{?foo,bar}")
      iex> Texture.UriTemplate.match!(t, "?foo=&bar=value")
      %{"foo" => nil, "bar" => "value"}

  ### Duplicate Parameters

  When the same parameter name appears multiple times in a template, the first
  occurrence is preserved. This ensures path parameters are not overridden by
  query parameters.

  Example:

      # Duplicate parameter names (first wins)
      iex> t = Texture.UriTemplate.parse!("{foo}/{foo}")
      iex> Texture.UriTemplate.match!(t, "first/second")
      %{"foo" => "first"}

  ### Error Cases

  Raises `Texture.UriTemplate.TemplateMatchError` when:

  * Non-exploded parameter receives dict syntax unexpectedly
  * Extra path segment values don't match template structure
  * Invalid parameter syntax (e.g., `foo==bar`)
  * Lists treated as keys in wrong context
  """
  @spec match!(t, binary) :: %{binary => term}
  def match!(%__MODULE__{} = t, url) do
    Matcher.match!(t, url)
  end

  defimpl Inspect do
    @spec inspect(term, term) :: binary
    def inspect(t, _) do
      "Texture.UriTemplate.parse!(#{inspect(t.raw)})"
    end
  end
end
