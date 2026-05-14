defmodule RockSolid.Traversal do
  @moduledoc """
  Utilities and functions to traverse schemas, collect keywords, etc.
  """

  alias RockSolid.Types

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
  Returns whether the current (reversed) path is a definiiton.

  ## Examples

      iex> RockSolid.Traversal.definition?(["type", "#"])
      false

      iex> RockSolid.Traversal.definition?(["$defs", "#"])
      true
  """
  @spec definition?(list(String.t())) :: boolean()
  def definition?([last | rest]),
    do:
      last in ["$defs", "definitions"] and not property?(rest) and not definition?(rest) and
        not dependencies?(rest)

  def definition?([]), do: false

  def dependencies?([last | rest]),
    do:
      last in ["dependencies", "dependentSchemas", "dependentRequired"] and not property?(rest) and
        not definition?(rest) and not dependencies?(rest)

  @doc """
  Returns a map of all references ($id, $anchor, $ref) and their corresponding values
  in the format of `%{"$ref" => %{["#", "path"] => value},  "$id" => %{}}`
  """
  @spec references(map()) :: %{String.t() => %{Types.path_t() => any()}}
  def references(schema) when is_map(schema) do
    schema
    |> collect_references(root_path())
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

  def root_path, do: ["#"]

  @doc """
  Converts a JSON pointer to a path

  ## Examples

      iex> RockSolid.Traversal.to_path("#/$defs/something")
      ["#", "$defs", "something"]

  ## Options

    - `:include_root?` - `t:boolean/0` whether to include the root `"#"`. Defaults to `true`
  """
  @spec to_path(String.t(), Keyword.t()) :: list(String.t())
  def to_path(json_pointer, opts \\ []) when is_binary(json_pointer) do
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

  def update_in_schema(schema, [k], val) when is_list(schema) do
    List.replace_at(schema, String.to_integer(k), val)
  end

  def update_in_schema(schema, [path], val), do: Map.put(schema, path, val)
  def update_in_schema(schema, ["#" | rest], val), do: update_in_schema(schema, rest, val)

  def update_in_schema(schema, [k | rest], val) when is_map(schema) do
    Map.put(schema, k, update_in_schema(schema[k], rest, val))
  end

  def update_in_schema(schema, [k | rest], val) when is_list(schema) do
    List.update_at(schema, String.to_integer(k), &update_in_schema(&1, rest, val))
  end
end
