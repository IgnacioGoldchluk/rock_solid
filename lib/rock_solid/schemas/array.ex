defmodule RockSolid.Schemas.Array do
  @moduledoc """
  Array type
  """
  alias RockSolid.Context
  alias RockSolid.Schemas.Schema

  @specific_keywords %{
    "type" => Zoi.literal("array") |> Zoi.default("array"),
    "items" => Zoi.union([Zoi.boolean(), Zoi.map()]) |> Zoi.optional(),
    "prefixItems" => Zoi.array(Zoi.json()) |> Zoi.optional(),
    "contains" => Zoi.json() |> Zoi.optional(),
    "minItems" => Zoi.integer(gte: 0) |> Zoi.optional(),
    "maxItems" => Zoi.integer(gte: 0) |> Zoi.optional(),
    "unevaluatedItems" => Zoi.literal(false) |> Zoi.optional(),
    "uniqueItems" => Zoi.boolean() |> Zoi.optional(),
    "minContains" => Zoi.integer(gte: 1) |> Zoi.optional(),
    "maxContains" => Zoi.integer(gte: 1) |> Zoi.optional()
  }

  @schema Zoi.map(Map.merge(Schema.common_keywords(), @specific_keywords))
  def new(attrs), do: schema() |> Zoi.parse(attrs) |> maybe_empty_array()

  def schema do
    with_transformations =
      Enum.reduce(transformations(), @schema, fn fun, schema ->
        Zoi.transform(schema, fun)
      end)

    Enum.reduce(extra_validations(), with_transformations, fn fun, schema ->
      Zoi.refine(schema, fun)
    end)
  end

  defp transformations do
    [&maybe_max_items/1, &maybe_contains/1, &maybe_remove_items/1, &limit_unique_items/1]
  end

  defp extra_validations do
    [&validate_items_range/1, &validate_contains/1]
  end

  defp maybe_contains(%{"contains" => _} = schema), do: schema
  defp maybe_contains(schema), do: Map.drop(schema, ["minContains", "maxContains"])

  defp maybe_max_items(%{"items" => false, "prefixItems" => prefix_items} = schema) do
    len_prefix = length(prefix_items)
    Map.update(schema, "maxItems", len_prefix, fn max_items -> min(len_prefix, max_items) end)
  end

  defp maybe_max_items(schema), do: schema

  defp validate_items_range(%{"minItems" => min, "maxItems" => max}) when min > max do
    {:error, "minItems > maxItems"}
  end

  defp validate_items_range(_), do: :ok

  defp maybe_remove_items(%{"prefixItems" => pi, "maxItems" => max_items} = schema)
       when length(pi) >= max_items do
    schema
    |> Map.put("prefixItems", Enum.take(pi, max_items))
    |> Map.put("items", false)
  end

  defp maybe_remove_items(schema), do: schema

  defp validate_contains(%{"minContains" => mc, "maxItems" => mi}) when mc > mi do
    {:error, "minContains > maxItems"}
  end

  defp validate_contains(%{"maxContains" => maxc, "minContains" => minc}) when minc > maxc do
    {:error, "minContains > maxContains"}
  end

  defp validate_contains(_), do: :ok

  # Otherwise the strategy fails to generate items for the cases where
  # we have uniqueItems + a limited choice of item values
  defp limit_unique_items(%{"uniqueItems" => true, "items" => %{"const" => _val}} = schema) do
    prefix_length = schema |> Map.get("prefixItems", []) |> length()
    new_max_items = prefix_length + 1

    Map.update(schema, "maxItems", new_max_items, &min(&1, new_max_items))
  end

  defp limit_unique_items(%{"uniqueItems" => true, "items" => %{"enum" => vals}} = schema) do
    prefix_length = schema |> Map.get("prefixItems", []) |> length()
    new_max_items = prefix_length + length(vals)

    Map.update(schema, "maxItems", new_max_items, &min(&1, new_max_items))
  end

  defp limit_unique_items(%{"uniqueItems" => true, "items" => %{"$ref" => ref}} = schema) do
    # This does not consider `$ref` with extra keywords in "items". For example
    # %{"items" => %{"$ref" => "#/$defs/foo", "additionalProperties" => false}}
    # We should deal with that before probably?
    limit_unique_items(Map.put(schema, "items", Context.get_ref(ref)))
  end

  defp limit_unique_items(schema), do: schema

  defp maybe_empty_array({:error, _} = error), do: error

  defp maybe_empty_array({:ok, array}) do
    case {empty_array?(array), Map.get(array, "minItems", 0)} do
      {false, _} -> {:ok, array}
      {true, 0} -> {:ok, %{"enum" => [[]]}}
      {true, min_items} when min_items > 0 -> {:error, "empty array"}
    end
  end

  defp empty_array?(array) do
    Map.get(array, "items") == false and Enum.empty?(Map.get(array, "prefixItems", []))
  end
end
