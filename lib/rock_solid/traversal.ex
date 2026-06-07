defmodule RockSolid.Traversal do
  @moduledoc """
  Utilities and functions to traverse schemas, collect keywords, etc.
  """

  @type path_t :: [String.t()]

  @root_path ["#"]

  defmodule InvalidPath do
    defexception [:key, :schema]

    def message(%{key: key, schema: schema}) do
      "Invalid key '#{key}' when traversing '#{inspect(schema, limit: :infinity)}"
    end
  end

  defguard is_atomic(v) when is_boolean(v) or is_nil(v) or is_number(v) or is_binary(v)

  @doc """
  Returns whether the current (reversed) path is properties

  ## Examples
      iex> RockSolid.Traversal.property?(["type", "#"])
      false

      iex> RockSolid.Traversal.property?(["properties", "person", "$defs", "#"])
      true

      iex> RockSolid.Traversal.property?(["properties", "properties", "meta", "$defs", "#"])
      false
  """
  @spec property?(list(String.t())) :: boolean()
  def property?([]), do: false

  def property?([_ | tail] = reversed_path) do
    property_keywords = ["properties", "patternProperties"]

    reversed_path
    |> Enum.take_while(&Enum.member?(property_keywords, &1))
    |> length()
    |> then(fn props_len ->
      rem(props_len, 2) != 0 and not definition?(tail) and not dependencies?(tail)
    end)
  end

  @doc """
  Returns whether the reversed path should be treated as a literal
  """
  @spec literal?(list(String.t())) :: boolean()
  def literal?([_ | rest] = reversed_path) when is_list(reversed_path) do
    if property?(rest) or definition?(rest) do
      false
    else
      # Property discarded, we know everything should be treated as keyword now
      case reversed_path do
        [key | _] when key in ["const", "default"] -> true
        [idx, prev | _] when prev in ["enum", "examples"] -> match?({_, ""}, Integer.parse(idx))
        _ -> false
      end
    end
  end

  @doc """
  Returns whether the reversed path is a definiiton.

  ## Examples

      iex> RockSolid.Traversal.definition?(["type", "#"])
      false

      iex> RockSolid.Traversal.definition?(["$defs", "#"])
      true
  """
  @spec definition?(list(String.t())) :: boolean()
  def definition?(reversed_path)

  def definition?([last | rest]),
    do:
      last in ["$defs", "definitions"] and not property?(rest) and not definition?(rest) and
        not dependencies?(rest)

  def definition?([]), do: false

  @doc """
  Returns whether the reversed path is part of a dependency definition

  ## Examples

      iex> RockSolid.Traversal.dependencies?(["dependentSchemas", "#"])
      true

      iex> RockSolid.Traversal.dependencies?(["dependentSchemas", "properties", "#"])
      false
  """
  def dependencies?(reversed_path)

  def dependencies?([last | rest]),
    do:
      last in ["dependencies", "dependentSchemas", "dependentRequired"] and not property?(rest) and
        not definition?(rest) and not dependencies?(rest)

  @doc """
  Returns a map of all references ($id, $anchor, $ref) and their corresponding values
  in the format
  ```
  %{"$ref" => %{["#", "path"] => value},  "$id" => %{}}
  ```
  """
  @spec references(map()) :: %{String.t() => %{path_t() => any()}}
  def references(schema) when is_map(schema) do
    schema
    |> collect_references(@root_path)
    |> Enum.reduce(Map.new(), fn {key, reversed_path, val}, acc ->
      path = Enum.reverse(reversed_path)
      Map.update(acc, key, %{path => val}, fn keyword_map -> Map.put(keyword_map, path, val) end)
    end)
  end

  defp collect_references(schema, path) when is_list(schema) do
    schema
    |> Enum.with_index()
    |> Enum.flat_map(fn {s, i} -> collect_references(s, [to_string(i) | path]) end)
  end

  defp collect_references(schema, path) when is_map(schema) do
    cond do
      literal?(path) ->
        []

      property?(path) or definition?(path) or dependencies?(path) ->
        Enum.flat_map(schema, fn {k, v} -> collect_references(v, [k | path]) end)

      true ->
        schema
        |> Map.take(["$id", "$ref", "$anchor"])
        |> Enum.map(fn {k, v} -> {k, path, v} end)
        |> Enum.concat(Enum.flat_map(schema, fn {k, v} -> collect_references(v, [k | path]) end))
    end
  end

  defp collect_references(_, _), do: []

  @doc """
  Converts a JSON path list to a pointer.

  If the list does not start with "#" it is assumed to be a reversed path

  ## Examples

      iex> RockSolid.Traversal.to_pointer(["#", "$defs", "foo"])
      "#/$defs/foo"

      iex> RockSolid.Traversal.to_pointer(["bar", "$defs", "#"])
      "#/$defs/bar"

      iex> RockSolid.Traversal.to_pointer(["#", "/users", "GET"])
      "#/~1users/GET"
  """
  def to_pointer(["#" | _] = path) when is_list(path), do: path |> Enum.map_join("/", &escape/1)

  def to_pointer(reversed_path) when is_list(reversed_path) do
    reversed_path |> Enum.reverse() |> to_pointer()
  end

  defp escape(k) when is_binary(k), do: String.replace(k, "~", "~0") |> String.replace("/", "~1")

  @doc """
  Converts a JSON pointer to a path

  ## Examples

      iex> RockSolid.Traversal.to_path("#/$defs/something")
      ["#", "$defs", "something"]

      iex> RockSolid.Traversal.to_path("#/paths/~1users")
      ["#", "paths", "/users"]

      iex> RockSolid.Traversal.to_path("/path/to/0/foo")
      ["path", "to", "0", "foo"]

  ## Options

    - `:include_root?` - `t:boolean/0` whether to include the root `"#"`. Defaults to `true`
  """
  @spec to_path(String.t(), Keyword.t()) :: list(String.t())
  def to_path(json_pointer, opts \\ [])

  def to_path("/" <> rest = _json_pointer, opts), do: to_path(rest, opts)

  def to_path(json_pointer, opts) when is_binary(json_pointer) do
    path =
      json_pointer
      |> String.split("/")
      |> Enum.map(fn key -> String.replace(key, "~1", "/") |> String.replace("~0", "~") end)

    if Keyword.get(opts, :include_root?, true) do
      path
    else
      ["#" | rest] = path
      rest
    end
  end

  @doc """
  Returns the value at the given location in the schema.

  The path argument may contain a leading "#". You can convert a JSON Pointer string
  to a valid path by calling `to_path/1`

  ## Examples
      iex> RockSolid.Traversal.get_in_schema(%{"foo" => %{"bar" => "baz"}}, ["#", "foo", "bar"])
      "baz"

      iex> RockSolid.Traversal.get_in_schema(%{"foo" => ["a", "b"]}, ["#", "foo", "1"])
      "b"
  """
  @spec get_in_schema(any(), list(String.t())) :: any()
  def get_in_schema(schema, []), do: schema
  def get_in_schema(schema, ["#" | rest]), do: get_in_schema(schema, rest)

  def get_in_schema(schema, [k | rest]) when is_map(schema) do
    key = if Map.has_key?(schema, k), do: k, else: URI.decode(k)

    if Map.has_key?(schema, key) do
      get_in_schema(schema[key], rest)
    else
      # This one should never happen anyway
      raise InvalidPath, key: key, schema: schema
    end
  end

  def get_in_schema(schema, [k | rest]) when is_list(schema),
    do: get_in_schema(Enum.at(schema, String.to_integer(k)), rest)

  @doc """
  Sets a value in the given (existing) path and returns the updated schema

  ## Examples

      iex> RockSolid.Traversal.put_in_schema!(%{"foo" => ["a", "b"]}, ["#", "foo", "1"], "c")
      %{"foo" => ["a", "c"]}
  """
  def put_in_schema!(schema, path, new_value)

  def put_in_schema!(schema, [k], val) when is_list(schema) do
    List.replace_at(schema, String.to_integer(k), val)
  end

  def put_in_schema!(schema, [path], val), do: Map.put(schema, path, val)
  def put_in_schema!(schema, ["#" | rest], val), do: put_in_schema!(schema, rest, val)

  def put_in_schema!(schema, [k | rest], val) when is_map(schema) do
    Map.put(schema, k, put_in_schema!(schema[k], rest, val))
  end

  def put_in_schema!(schema, [k | rest], val) when is_list(schema) do
    List.update_at(schema, String.to_integer(k), &put_in_schema!(&1, rest, val))
  end

  @doc """
  Same as `put_in_schema!/3` but returns a tuple
  """
  @spec put_in_schema(any(), [String.t()], any()) :: {:ok, any()} | {:error, Exception.t()}
  def put_in_schema(schema, path, value) do
    {:ok, put_in_schema!(schema, path, value)}
  rescue
    error -> {:error, error}
  end
end
