defmodule RockSolid.Context do
  @moduledoc """
  Module to access the current process' schema
  """
  alias RockSolid.Resolution
  alias RockSolid.Transformation
  import RockSolid.Traversal

  defmodule InvalidId do
    defexception [:id]

    def message(%{id: id} = _exception) do
      "Schema with id '#{id}' not found in context"
    end
  end

  defmodule InvalidRecursionError do
    defexception []

    def message(_) do
      """
      Recursion error when traversing schema. This happens because the schema, or
      a schema referenced by the schema, contain a recursive "$ref" that depends
      on itself from multiple paths. While recursive schemas are supported,
      certain cases cannot be resolved currently.
      """
    end
  end

  # Possible keys
  # - "http(s)://..." -> key for migrated (non simplified) schemas
  # - {:simplified, "https://..."} -> key for simplified schemas and subschemas
  # - {:placeholder, "#/PLACEHOLDER_..."} -> key for placeholder and on-the-fly-def for
  # recursive intersections

  @doc """
  Puts a key-value pair in the local process table
  """
  def put(key, value) when not is_nil(value), do: :ets.insert(table(), {key, value})

  @doc """
  Stores a schema using its id
  """
  def put_schema(%{"$id" => id} = schema), do: put(Resolution.base_id(id), schema)

  @doc """
  Returns a schema by its id
  """
  def fetch_schema!(id) do
    schema = get_value(id)

    if is_nil(schema) do
      raise InvalidId, id: id
    end

    schema
  end

  defp get_simplified(pointer), do: get_value({:simplified, pointer})

  def put_simplified(full_pointer, simplified_schema) do
    :ets.insert(table(), {{:simplified, full_pointer}, simplified_schema})
  end

  @doc """
  Returns the value for the given pointer
  """
  def get_ref(pointer)

  # Placeholders are stored in memory outside of schemas
  def get_ref("#/PLACEHOLDER" <> _ = placeholder_name) do
    value = get_value({:placeholder, placeholder_name})

    if is_nil(value) do
      raise InvalidRecursionError
    end

    value
  end

  # "$defs" and remote schemas are not simplified when doing the transformation because
  # some schemas have too many unused "$defs" and it is not worth it.
  # Additionally, simplification is a destructive action and simplifying
  # a schema inside "$defs" might result in invalid pointers later in the schema.
  # Instead we use separate keys {:simplified, pointer} for simplified refs
  def get_ref(pointer) when is_binary(pointer) do
    case get_simplified(pointer) do
      nil ->
        base_schema = fetch_base_schema!(pointer)
        relative_pointer = to_relative(pointer)
        path = to_path(relative_pointer)
        reversed_path = Enum.reverse(path)

        non_simplified = get_in_schema(base_schema, path)
        simplified = Transformation.simplify(non_simplified, reversed_path)
        put_simplified(pointer, simplified)
        get_ref(pointer)

      simplified_value ->
        simplified_value
    end
  end

  @doc """
  Stores a placeholder for the intersection of a `$ref` and another schema. Returns
  the placeholder name
  """
  @spec put_placeholder(term()) :: String.t()
  def put_placeholder(key) do
    placeholder_name = placeholder()
    :ets.insert(table(), {key, placeholder_name})
    placeholder_name
  end

  @doc """
  Adds a new `$ref` to the reference stored schema and updates the entry.
  """
  def add_on_the_fly_def(key, placeholder_name) do
    put({:placeholder, placeholder_name}, get(key))
  end

  @doc """
  Builds a subschema including all the remote schemas in the context
  """
  @spec build(map() | boolean()) :: {:ok, JSV.Root.t()} | {:error, Exception.t() | String.t()}
  def build(schema) when is_map(schema), do: JSV.build(schema, resolver: [RockSolid.Resolver])
  def build(schema) when is_boolean(schema), do: JSV.build(schema)

  @doc """
  Same as `build/1` but raises on error
  """
  def build!(subschema) do
    case build(subschema) do
      {:ok, subschema} -> subschema
      {:error, exception_or_msg} -> raise exception_or_msg
    end
  end

  @doc """
  Returns the value associated with the key from the local process table, or `nil`
  if the key does not exist
  """
  def get({k1, k2}) do
    # Also check the reverse key since we cannot control the order and
    # some iterations might reverse it
    value = get_value({k1, k2})
    if is_nil(value), do: get_value({k2, k1}), else: value
  end

  defp table do
    case Process.get(table_key()) do
      nil ->
        # Since it's per process, only the same process that created the table
        # can read and write to it
        Process.put(table_key(), :ets.new(:whatever, [:set, :protected]))
        table()

      table_ref when is_reference(table_ref) ->
        table_ref
    end
  end

  # The ets table key inside the process key-value dictionary.
  # This is not the ets table name! We don't use the table name at all
  defp table_key, do: :rock_solid_process_ets_table

  defp placeholder, do: "#/PLACEHOLDER_#{System.unique_integer([:positive])}"

  # Returns the base schema of the pointer. For example if pointer is "https://foo.bar#/$defs/baz"
  # then the full schema at "https://foo.bar" is returned
  defp fetch_base_schema!(pointer) do
    {base, _} = Resolution.base_fragment(pointer)
    fetch_schema!(base)
  end

  # Returns the relative pointer of a full URI, including the leading "#"
  defp to_relative(pointer) when is_binary(pointer) do
    {_base, fragment} = Resolution.base_fragment(pointer)
    if is_nil(fragment), do: "#", else: "#" <> fragment
  end

  # Returns the value or nil
  defp get_value(key) do
    case :ets.lookup(table(), key) do
      [] -> nil
      [{_, value}] -> value
    end
  end

  def store_intersection(p1, p2, result) when is_binary(p1) and is_binary(p2) do
    :ets.insert(table(), {{:intersection, p1, p2}, result})
    :ets.insert(table(), {{:intersection, p2, p1}, result})
  end

  def get_intersection(p1, p2) when is_binary(p1) and is_binary(p2) do
    get_value({:intersection, p1, p2})
  end
end
