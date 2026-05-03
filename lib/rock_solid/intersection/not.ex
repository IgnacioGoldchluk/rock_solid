defmodule RockSolid.Intersection.Not do
  @moduledoc false
  alias RockSolid.Intersection

  defguardp is_any_of(schema)
            when is_map(schema) and map_size(schema) == 1 and is_map_key(schema, "anyOf")

  @doc """
  Intersects a schema with multiple negative clauses
  """
  def add_clauses(schema, not_clauses) when is_any_of(schema) and is_list(not_clauses) do
    schema
    |> Map.fetch!("anyOf")
    |> Enum.map(fn subschema -> add_clauses(subschema, not_clauses) end)
    |> Enum.reject(&(&1 == false))
    |> case do
      [] -> raise "Empty #{inspect(schema)} with 'not': #{inspect(not_clauses)}"
      [value] -> value
      values when is_list(values) -> %{"anyOf" => values}
    end
  end

  def add_clauses(%{"anyOf" => _} = s, _) do
    # Should never happen
    raise "Unexpected schema: #{inspect(s)}"
  end

  def add_clauses(schema, not_clauses) when is_list(not_clauses) do
    Enum.reduce(not_clauses, schema, fn not_clause, schema -> add_clause(schema, not_clause) end)
  end

  @doc """
  Intersects a schema with a negative clause.
  """
  def add_clause(schema, not_clause) do
    if object_properties?(not_clause) do
      apply_not_properties(schema, not_clause)
    else
      add_not_clause(schema, not_clause)
    end
  end

  def add_not_clause(false, _), do: false
  def add_not_clause(true, clause), do: %{"not" => clause}

  def add_not_clause(schema, new_clause) when is_map(schema) do
    value =
      if Intersection.safe_intersection(schema, new_clause) == false do
        schema
      else
        do_add_clause(schema, new_clause)
      end

    if Intersection.impossible?(value), do: false, else: value
  end

  defp object_properties?(not_clause) when is_map(not_clause) and map_size(not_clause) > 0 do
    not_clause |> Map.keys() |> Enum.all?(&(&1 in ["required", "properties"]))
  end

  defp object_properties?(_), do: false

  defp apply_not_properties(schema, not_clauses) when is_map(schema) do
    existing_props = Map.get(schema, "properties", %{})
    existing_required = Map.get(schema, "required", [])

    new_props =
      not_clauses
      |> to_override_properties(existing_required)
      |> Enum.reduce(existing_props, fn kv, props ->
        case kv do
          {key, true} -> Map.put(props, key, false)
          {key, false} -> Map.put(props, key, false)
          {key, %{"const" => val}} -> remove_enum(props, key, [val])
          {key, %{"enum" => vals}} when is_list(vals) -> remove_enum(props, key, vals)
        end
      end)

    Map.put(schema, "properties", new_props)
  end

  defp to_override_properties(not_clause, existing_required) when is_map(not_clause) do
    # Convert all 'required' properties to false if they are not in 'properties' already,
    # ignore all existing required from the positive schema
    properties = Map.get(not_clause, "properties", %{})

    not_clause
    |> Map.get("required", [])
    |> Enum.reject(&(&1 in existing_required))
    |> Map.from_keys(false)
    |> Map.merge(properties)
  end

  defp remove_enum(props, key, to_remove) do
    Map.update(props, key, %{"not" => %{"enum" => to_remove}}, fn
      %{"enum" => values} -> %{"enum" => Enum.filter(values, &(&1 not in to_remove))}
      other -> do_add_clause(other, %{"enum" => to_remove})
    end)
  end

  defp do_add_clause(%{"not" => %{"anyOf" => clauses}} = schema, new_clause) do
    put_in(schema, ["not", "anyOf"], Enum.uniq([new_clause | clauses]))
  end

  defp do_add_clause(%{"not" => clause} = schema, new_clause) do
    Map.put(schema, "not", %{"anyOf" => Enum.uniq([clause, new_clause])})
  end

  defp do_add_clause(schema, new_clause), do: Map.put(schema, "not", new_clause)
end
