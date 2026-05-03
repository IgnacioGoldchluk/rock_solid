defmodule RockSolid.Resolution do
  @moduledoc false
  import RockSolid.Traversal
  alias RockSolid.Resolution.Cache

  defp missing_root_id, do: "root://no-uri"

  @doc """
  Returns the base id of a full schema $id path.
  """
  def base_id(path) when is_binary(path) do
    {base, _fragment} = base_fragment(path)
    base
  end

  @doc """
  Returns the `$id` or `id` of an schema
  """
  def id(%{"id" => id}), do: id |> base_id()
  def id(%{"$id" => id}), do: id |> base_id()
  # Delete after ensuring every schema has `$id`
  def id(s) when is_map(s), do: missing_root_id()

  @doc """
  Fetches all schemas referenced directly or indirectly by the base schema
  """
  def fetch_all(base_schema, resolver) when is_map(base_schema) do
    {refs_ids, updated_base} = refs_base_ids(base_schema)
    fetch_schemas(refs_ids, %{id(updated_base) => updated_base}, resolver)
  end

  defp fetch_schemas([], fetched_schemas, _), do: {:ok, fetched_schemas}

  defp fetch_schemas([base_id | rest], schemas, resolver) do
    with {:fetched?, false} <- {:fetched?, Map.has_key?(schemas, base_id)},
         {:ok, schema} <- fetch_schema(base_id, resolver),
         _ <- Cache.store_in_local_dir(base_id, schema),
         :ok <- check_matches_id(schema, base_id) do
      {refs, updated_schema} = refs_base_ids(schema)
      fetch_schemas(rest ++ refs, Map.put(schemas, base_id, updated_schema), resolver)
    else
      {:fetched?, true} -> fetch_schemas(rest, schemas, resolver)
      {:error, _} = error -> error
    end
  end

  defp refs_base_ids(schema) when is_map(schema) do
    base_uri = schema |> id() |> URI.parse()
    refs = schema |> references() |> Map.get("$ref", %{})

    remote_ids =
      refs
      |> Map.values()
      |> Enum.map(&base_id/1)
      |> Enum.uniq()
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(fn ref -> to_absolute(ref, base_uri) end)

    # We also have to update all the schemas that contain `path`
    updated_schema =
      Enum.reduce(refs, schema, fn {path_as_list, value}, schema ->
        update_in_schema(
          schema,
          path_as_list ++ ["$ref"],
          to_absolute_schema(URI.parse(value), base_uri)
        )
      end)

    {remote_ids, updated_schema}
  end

  defp check_matches_id(%{"$id" => id}, base_id) do
    if(base_id(id) == base_id,
      do: :ok,
      else: {:error, "mismatched $id: #{id} and referenced path #{base_id}"}
    )
  end

  defp check_matches_id(%{"id" => id}, base_id) do
    if(base_id(id) == base_id,
      do: :ok,
      else: {:error, "mismatched id: #{id} and referenced path #{base_id}"}
    )
  end

  defp check_matches_id(_, _), do: :ok

  defp fetch_schema(base_id, {resolver_mod, opts}) do
    case Cache.get_schema(base_id) do
      nil -> resolver_mod.resolve(base_id, opts)
      schema when is_map(schema) -> {:ok, schema}
    end
  end

  @doc """
  Returns a tuple {base, fragment} given the full JSON pointer.
  Fragment is `nil` if there is no '#', and an empty string if the pointer ends in '#'
  """
  def base_fragment(full_path) when is_binary(full_path) do
    case String.split(full_path, "#") do
      [base] -> {base, nil}
      [base, fragment] -> {base, fragment}
    end
  end

  defp to_absolute(maybe_relative_ref, base_url) do
    to_absolute_schema(URI.parse(maybe_relative_ref), URI.parse(base_url))
  end

  defp to_absolute_schema(%URI{scheme: nil} = relative_uri, %URI{} = base_uri) do
    if relative_to_current_schema?(relative_uri) do
      # Keep it as it is for now, it'll be eventually replaced as part of the migration
      to_string(relative_uri)
    else
      # Relative in terms of URL resolution but not to the current schema.
      # For example we have "https://example.com/schema.json" as $id and it contains
      # "$ref": "remote.json#/a", we have to convert it to
      # "$ref": "https://example.com/remote.json/#a"
      fields = [:scheme, :userinfo, :host, :port]
      base_uri = Map.from_struct(base_uri)

      Enum.reduce(fields, relative_uri, fn field, relative_uri ->
        base_uri_field = base_uri[field]

        if is_nil(base_uri_field) do
          relative_uri
        else
          Map.put(relative_uri, field, base_uri_field)
        end
      end)
      |> then(fn
        %URI{path: nil} = uri -> uri
        %URI{path: p} = uri when is_binary(p) -> Map.put(uri, :path, "/" <> p)
      end)
      |> to_string()
    end
  end

  defp to_absolute_schema(%URI{} = relative_uri, %URI{} = _base_uri) do
    to_string(relative_uri)
  end

  defp relative_to_current_schema?(%URI{} = relative_uri) do
    case base_fragment(to_string(relative_uri)) do
      {"", _} -> true
      _ -> false
    end
  end
end
