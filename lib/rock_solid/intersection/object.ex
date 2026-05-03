defmodule RockSolid.Intersection.Object do
  @moduledoc """
  Intersection between two objects
  """
  alias RockSolid.Context
  alias RockSolid.Intersection
  alias RockSolid.Intersection.{Number, Pattern}
  alias RockSolid.Schemas.{Object, Schema}

  def intersection(s1, s2) do
    schema = %{
      "required" => required_intersection(s1, s2),
      "minProperties" => Number.minimum_intersection(s1["minProperties"], s2["minProperties"]),
      "maxProperties" => Number.maximum_intersection(s1["maxProperties"], s2["maxProperties"]),
      "patternProperties" => pattern_properties_intersection(s1, s2),
      "dependentRequired" => dependent_required(s1["dependentRequired"], s2["dependentRequired"])
    }

    with {:ok, common_props} <- common_properties_intersection(schema, s1, s2),
         {:ok, distinct_props} <- distinct_properties_intersection(common_props, s1, s2),
         {:ok, additional_props} <- additional_properties_intersection(distinct_props, s1, s2) do
      additional_props |> discard_defaults() |> Schema.discard_nulls() |> Object.new()
    end
  end

  defp defaults do
    %{
      "propertyNames" => %{"type" => "string"},
      "properties" => %{},
      "patternProperties" => %{},
      "additionalProperties" => true,
      "dependentRequired" => nil
    }
  end

  defp discard_defaults(schema) do
    Enum.reduce(defaults(), schema, fn {key, val}, acc ->
      if(acc[key] == val, do: Map.delete(acc, key), else: acc)
    end)
  end

  defp required_intersection(%{"required" => r1}, %{"required" => r2}),
    do: Enum.uniq(Enum.concat(r1, r2))

  defp required_intersection(%{"required" => r1}, _), do: r1
  defp required_intersection(_, %{"required" => r2}), do: r2
  defp required_intersection(_, _), do: nil

  defp distinct_properties_intersection(schema, s1, s2) do
    new_props =
      Map.merge(
        distinct_properties_intersection(s1, s2),
        distinct_properties_intersection(s2, s1)
      )

    {:ok,
     Map.update(schema, "properties", new_props, fn props -> Map.merge(props, new_props) end)}
  end

  defp distinct_properties_intersection(source, to_compare) do
    other_props = property_names(to_compare)

    # Properties that are `false` for any of the 2 and add them. We have to do this in a separate
    # Map.merge step because when matching vs patternProperties or additionalProperties they
    # return false and the algorithm incorrectly assumes that they should be discarded
    impossible_props =
      Map.from_keys(impossible_properties(source) ++ impossible_properties(to_compare), false)

    source
    |> property_names()
    |> Enum.reject(fn prop_name -> Enum.member?(other_props, prop_name) end)
    |> Enum.reduce(Map.new(), fn prop_name, acc ->
      case match_property({prop_name, source["properties"][prop_name]}, to_compare) do
        nil -> acc
        {^prop_name, value} -> Map.put(acc, prop_name, value)
      end
    end)
    |> Map.merge(impossible_props)
  end

  defp match_property({property_name, property_schema}, other_schema) do
    # Match patternProperties
    case matching_pattern_property(property_name, other_schema) do
      {_regex, value} ->
        case Intersection.intersection(property_schema, value) do
          {:ok, value} when value != false -> {property_name, value}
          _ -> nil
        end

      nil ->
        # Try with propertyNames + additionalProperties
        match_property_names(property_name, property_schema, other_schema)
    end
  end

  defp match_property_names(_, _, %{"additionalProperties" => false}), do: nil

  defp match_property_names(prop_name, prop_schema, to_compare) do
    additional_properties = Map.get(to_compare, "additionalProperties", true)
    property_names = Map.get(to_compare, "propertyNames", %{"type" => "string"})

    with {:ok, _} <- JSV.validate(prop_name, Context.build!(property_names)),
         {:ok, value} when value != false <-
           Intersection.intersection(prop_schema, additional_properties) do
      {prop_name, value}
    else
      _ -> nil
    end
  end

  defp matching_pattern_property(name, other_schema) do
    other_schema
    |> Map.get("patternProperties", %{})
    |> Enum.find(fn {regex, _} -> Regex.match?(Regex.compile!(regex), name) end)
  end

  defp common_properties_intersection(schema, s1, s2) do
    required = schema["required"] || []
    p1 = Map.get(s1, "properties", %{})
    p2 = Map.get(s2, "properties", %{})

    common_props =
      MapSet.intersection(MapSet.new(property_names(s1)), MapSet.new(property_names(s2)))

    Enum.reduce_while(common_props, {:ok, schema}, fn prop, {:ok, schema} ->
      intersection = Intersection.safe_intersection(p1[prop], p2[prop])

      if intersection == false and Enum.member?(required, prop) do
        {:halt, {:error, "#{prop} cannot match"}}
      else
        {:cont,
         {:ok,
          Map.update(
            schema,
            "properties",
            %{prop => intersection},
            &Map.put(&1, prop, intersection)
          )}}
      end
    end)
  end

  defp additional_properties_intersection(schema, s1, s2) do
    additional_properties =
      Intersection.safe_intersection(
        Map.get(s1, "additionalProperties", true),
        Map.get(s2, "additionalProperties", true)
      )

    property_names = property_names_intersection(s1, s2)

    finals =
      case {property_names, additional_properties} do
        {_, false} -> %{"additionalProperties" => false}
        {false, _} -> %{"additionalProperties" => false, "propertyNames" => false}
        {p, a} -> %{"propertyNames" => p, "additionalProperties" => a}
      end

    {:ok, Map.merge(schema, finals, fn _k, v1, v2 -> Intersection.safe_intersection(v1, v2) end)}
  end

  defp property_names_intersection(%{"propertyNames" => p1}, %{"propertyNames" => p2}) do
    Intersection.safe_intersection(p1, p2)
  end

  defp property_names_intersection(%{"propertyNames" => p1}, _), do: p1
  defp property_names_intersection(_, %{"propertyNames" => p2}), do: p2
  defp property_names_intersection(_, _), do: %{"type" => "string"}

  defp property_names(schema), do: Map.get(schema, "properties", %{}) |> Map.keys()

  defp pattern_properties_intersection(%{"patternProperties" => p1}, %{"patternProperties" => p2})
       when is_map(p1) and is_map(p2) do
    for {pat1, schema1} <- p1, {pat2, schema2} <- p2, reduce: %{} do
      acc ->
        with {:ok, new_pattern} <- Pattern.intersection(pat1, pat2),
             {:ok, value} when value != false <- Intersection.intersection(schema1, schema2) do
          Map.put(acc, new_pattern, value)
        else
          _ -> acc
        end
    end
  end

  defp pattern_properties_intersection(%{"patternProperties" => p1}, other) do
    pattern_properties_vs_schema(p1, other)
  end

  defp pattern_properties_intersection(other, %{"patternProperties" => p1}) do
    pattern_properties_vs_schema(p1, other)
  end

  defp pattern_properties_intersection(_, _), do: nil

  defp pattern_properties_vs_schema(pattern_properties, schema) do
    additional_properties = Map.get(schema, "additionalProperties", true)
    prop_names = Map.get(schema, "propertyNames", %{"type" => "string"})

    pattern_properties
    |> Enum.map(fn {pattern, schema} -> {to_schema(pattern), schema} end)
    |> Enum.map(fn {name_schema, value_schema} ->
      case {Intersection.intersection(name_schema, prop_names),
            Intersection.intersection(value_schema, additional_properties)} do
        {{:error, _}, _} -> nil
        {{:ok, false}, _} -> nil
        {_, {:error, _}} -> nil
        {_, {:ok, false}} -> nil
        # This assumes the match will always be a regex
        # There is also the possibility that the match is an enum, in which case
        # we have to make sure that only one of the propertyPatterns matches, and we
        # replace additionalProperties + propertyNames with the intersection, but
        # it is an edge case and we won't consider it for now
        {{:ok, %{"pattern" => k}}, {:ok, v}} -> {k, v}
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Map.new()
  end

  defp to_schema(pattern) when is_binary(pattern), do: %{"type" => "string", "pattern" => pattern}

  defp dependent_required(nil, dr), do: dr
  defp dependent_required(dr, nil), do: dr

  defp dependent_required(dr1, dr2) when is_map(dr1) and is_map(dr2) do
    Map.merge(dr1, dr2, fn _k, v1, v2 -> Enum.concat(v1, v2) |> Enum.uniq() end)
  end

  defp impossible_properties(%{"properties" => props}) do
    Enum.filter(props, fn {_k, v} -> v == false end) |> Enum.map(fn {k, _} -> k end)
  end

  defp impossible_properties(_), do: []
end
