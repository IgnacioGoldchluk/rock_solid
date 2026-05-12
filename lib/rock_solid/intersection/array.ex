defmodule RockSolid.Intersection.Array do
  @moduledoc """
  Intersection of arrays
  """
  alias RockSolid.Intersection
  alias RockSolid.Intersection.Number

  alias RockSolid.Schemas.Array
  alias RockSolid.Schemas.Schema

  def intersection(s1, s2) do
    schema =
      %{
        "maxItems" => Number.maximum_intersection(s1["maxItems"], s2["maxItems"]),
        "minItems" => Number.minimum_intersection(s1["minItems"], s2["minItems"]),
        "maxContains" => Number.maximum_intersection(s1["maxContains"], s2["maxContains"]),
        "minContains" => Number.minimum_intersection(s1["minContains"], s2["minContains"]),
        "uniqueItems" => s1["uniqueItems"] == true or s2["uniqueItems"] == true
      }

    with {:ok, items_intersection} <- items_intersection(s1, s2),
         merged = Map.merge(schema, items_intersection),
         contains = Enum.reject([s1["contains"], s2["contains"]], &is_nil/1),
         {:ok, with_contains} <- contains_intersection(merged, contains) do
      with_contains |> discard_defaults() |> Schema.discard_nulls() |> Array.new()
    end
  end

  defp defaults do
    %{"uniqueItems" => false, "items" => true}
  end

  defp discard_defaults(schema) do
    Enum.reduce(defaults(), schema, fn {key, val}, acc ->
      if(acc[key] == val, do: Map.delete(acc, key), else: acc)
    end)
  end

  defp items_intersection(s1, s2) do
    if Map.has_key?(s1, "prefixItems") or Map.has_key?(s2, "prefixItems") do
      with_prefix_items(s1, s2)
    else
      no_prefix_items(s1, s2)
    end
  end

  defp no_prefix_items(s1, s2) do
    case Intersection.intersection(Map.get(s1, "items", true), Map.get(s2, "items", true)) do
      {:ok, value} -> {:ok, %{"items" => value}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp with_prefix_items(s1, s2) do
    items =
      Intersection.safe_intersection(Map.get(s1, "items", true), Map.get(s2, "items", true))

    [s1, s2] = Enum.sort_by([s1, s2], fn s -> length(Map.get(s, "prefixItems", [])) end)
    pi1 = Map.get(s1, "prefixItems", [])
    pi2 = Map.get(s2, "prefixItems", [])

    matching =
      [pi1, pi2]
      |> Enum.zip()
      |> Enum.reduce_while([], fn {prefix1, prefix2}, matching ->
        case Intersection.intersection(prefix1, prefix2) do
          {:ok, value} -> {:cont, [value | matching]}
          {:error, _} -> {:halt, matching}
        end
      end)

    cond do
      length(matching) < length(pi1) ->
        {:ok, %{"items" => false, "prefixItems" => Enum.reverse(matching)}}

      length(matching) == length(pi1) ->
        remaining_prefix_items = Enum.slice(pi2, length(matching)..-1//1)
        remaining_items = Map.get(s1, "items", true)

        matching =
          Enum.reduce_while(remaining_prefix_items, matching, fn prefix_item, acc ->
            case Intersection.intersection(prefix_item, remaining_items) do
              {:ok, value} -> {:cont, [value | acc]}
              {:error, _} -> {:halt, acc}
            end
          end)

        if length(matching) == length(pi2) do
          {:ok, %{"items" => items, "prefixItems" => Enum.reverse(matching)}}
        else
          {:ok, %{"items" => false, "prefixItems" => Enum.reverse(matching)}}
        end
    end
  end

  defp contains_intersection(schema, contains_clauses) when is_list(contains_clauses) do
    # We can do this because no analysed schema contained `maxContains` or `minContains`
    # so what we do is to always calculate the intersection of contains + whatever
    # and put it as part of prefixItems
    Enum.reduce_while(contains_clauses, {:ok, schema}, fn contains, {:ok, schema} ->
      case matching_prefix_item(Map.get(schema, "prefixItems", []), contains) do
        {value, idx} ->
          {:cont,
           {:ok,
            schema
            |> Map.update!("prefixItems", &List.replace_at(&1, idx, value))
            # Since we're adding contains as part of prefixItems, we have to make sure
            # to generate items until the position to where the `contains` clause was
            # intersected
            |> Map.update("minItems", idx, fn
              nil -> idx + 1
              min_items -> max(idx + 1, min_items)
            end)}}

        nil ->
          case Intersection.intersection(Map.get(schema, "items", true), contains) do
            {:ok, value} when value != false ->
              updated =
                schema
                |> Map.update("prefixItems", [value], &Enum.concat(&1, [value]))
                |> Map.update("contains", value, fn
                  %{"anyOf" => contains} -> %{"anyOf" => [value | contains]}
                  contains -> %{"anyOf" => [value, contains]}
                end)
                |> ensure_contains_is_generated()

              {:cont, {:ok, updated}}

            _ ->
              {:halt,
               {:error, "no match for contains #{inspect(contains)} in #{inspect(schema)}"}}
          end
      end
    end)
  end

  defp matching_prefix_item(prefix_items, contains) do
    prefix_items
    |> Enum.with_index()
    |> Enum.find_value(fn {prefix_item, idx} ->
      case Intersection.intersection(prefix_item, contains) do
        {:ok, false} -> nil
        {:ok, value} -> {value, idx}
        {:error, _} -> nil
      end
    end)
  end

  defp ensure_contains_is_generated(%{"prefixItems" => prefix_items} = schema) do
    Map.update(schema, "minItems", length(prefix_items), fn
      nil -> length(prefix_items)
      min_items -> max(min_items, length(prefix_items))
    end)
  end
end
