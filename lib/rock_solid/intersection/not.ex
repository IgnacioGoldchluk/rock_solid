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
      [] -> false
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
  def add_clause(schema, not_clause)

  def add_clause(%{"type" => "object"} = schema, %{"anyOf" => clauses} = not_clause) do
    case Enum.find(clauses, &object_properties?/1) do
      nil -> add_not_clause(schema, not_clause)
      matching_clause -> apply_not_properties(schema, matching_clause)
    end
  end

  def add_clause(schema, not_clause) do
    if object_properties?(not_clause) and is_map(schema) do
      apply_not_properties(schema, not_clause)
    else
      add_not_clause(schema, not_clause)
    end
  end

  def add_not_clause(false, _), do: false
  def add_not_clause(true, clause), do: %{"not" => clause}

  def add_not_clause(schema, new_clause) when is_map(schema) do
    schema = drop_meta(schema)

    case Intersection.safe_intersection(schema, new_clause) do
      false -> schema
      ^schema -> false
      _ -> do_add_clause(schema, new_clause)
    end
  end

  defp drop_meta(schema) do
    schema |> Map.drop(["$id", "$schema"]) |> RockSolid.Transformation.drop_non_keywords()
  end

  defp object_properties?(%{"type" => "object"} = not_clause) do
    object_properties?(Map.delete(not_clause, "type"))
  end

  defp object_properties?(not_clause) when is_map(not_clause) and map_size(not_clause) > 0 do
    not_clause |> Map.keys() |> Enum.all?(&(&1 in ["required", "properties"]))
  end

  defp object_properties?(_), do: false

  defp apply_not_properties(schema, not_clause) when is_map(schema) do
    existing_required = Map.get(schema, "required", [])

    not_clause
    |> to_override_properties(existing_required)
    |> Enum.map(fn {key, _value} = property ->
      new_schema = apply_not_property(property, schema)
      if impossible?(new_schema, key), do: false, else: new_schema
    end)
    |> Enum.reject(&(&1 == false))
    |> case do
      [] -> false
      [single_schema] -> single_schema
      schemas when is_list(schemas) and length(schemas) > 1 -> %{"anyOf" => schemas}
    end
  end

  defp apply_not_property(kv, schema) when not is_map_key(schema, "properties") do
    apply_not_property(kv, Map.put(schema, "properties", %{}))
  end

  defp apply_not_property({key, false}, schema) do
    Map.update(schema, "required", [key], &([key | &1] |> Enum.uniq()))
  end

  defp apply_not_property({key, value}, %{"properties" => props} = schema) do
    new_props =
      case value do
        true -> Map.put(props, key, false)
        %{"const" => const} -> remove_enum(props, key, [const])
        %{"enum" => enums} -> remove_enum(props, key, enums)
        subschema -> Map.update(props, key, %{"not" => subschema}, &add_clause(&1, subschema))
      end

    Map.put(schema, "properties", new_props)
  end

  defp impossible?(schema, property) do
    get_in(schema, ["properties", property]) == false and
      property in Map.get(schema, "required", [])
  end

  defp to_override_properties(not_clause, existing_required) when is_map(not_clause) do
    # Convert all 'required' properties to false if they are not in 'properties' already,
    # ignore all existing required from the positive schema
    properties = Map.get(not_clause, "properties", %{})

    not_clause
    |> Map.get("required", [])
    |> Enum.reject(&(&1 in existing_required))
    |> Map.from_keys(true)
    |> Map.merge(properties)
  end

  defp remove_enum(props, key, to_remove) do
    Map.update(props, key, %{"not" => %{"enum" => to_remove}}, fn
      %{"enum" => values} ->
        case Enum.filter(values, &(&1 not in to_remove)) do
          [] -> false
          remaining -> %{"enum" => remaining}
        end

      other ->
        do_add_clause(other, %{"enum" => to_remove})
    end)
  end

  defp do_add_clause(false, _), do: false

  defp do_add_clause(%{"not" => %{"anyOf" => clauses}} = schema, new_clause) do
    put_in(schema, ["not", "anyOf"], Enum.uniq([new_clause | clauses]))
  end

  defp do_add_clause(%{"not" => clause} = schema, new_clause) do
    Map.put(schema, "not", %{"anyOf" => Enum.uniq([clause, new_clause])})
  end

  defp do_add_clause(schema, new_clause), do: Map.put(schema, "not", new_clause)
end
