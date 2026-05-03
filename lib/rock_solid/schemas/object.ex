defmodule RockSolid.Schemas.Object do
  @moduledoc """
  Object type
  """
  alias RockSolid.Context
  alias RockSolid.Intersection
  alias RockSolid.Intersection.Pattern
  alias RockSolid.Schemas.Schema

  @specific_keywords %{
    "type" => Zoi.literal("object") |> Zoi.default("object"),
    "properties" => Zoi.union([Zoi.boolean(), Zoi.map()]) |> Zoi.optional(),
    # Not true but we'll roll with it for now, should be
    # Zoi.map(Zoi.string(), Zoi.lazy(fn -> Zoi.json() end))
    # otherwise it won't be compiled as module attribute
    "patternProperties" => Zoi.map(Zoi.string(), Zoi.any()) |> Zoi.optional(),
    "additionalProperties" => Zoi.union([Zoi.boolean(), Zoi.map()]) |> Zoi.optional(),
    "required" => Zoi.array(Zoi.string()) |> Zoi.optional(),
    "unevaluatedProperties" => Zoi.literal(false) |> Zoi.optional(),
    "propertyNames" => Zoi.map() |> Zoi.optional(),
    "minProperties" => Zoi.integer(gte: 0) |> Zoi.optional(),
    "maxProperties" => Zoi.integer(gte: 0) |> Zoi.optional(),
    "dependentRequired" => Zoi.map(Zoi.string(), Zoi.list(Zoi.string())) |> Zoi.optional()
  }

  @schema Zoi.map(Map.merge(Schema.common_keywords(), @specific_keywords))

  # A bit out of place here but we cannot drop it anywhere else
  def new(attrs), do: schema() |> Zoi.parse(attrs) |> maybe_empty_object()

  def schema do
    with_transformations =
      Enum.reduce(transformations(), @schema, fn fun, schema -> Zoi.transform(schema, fun) end)

    Enum.reduce(extra_validations(), with_transformations, fn fun, schema ->
      Zoi.refine(schema, fun)
    end)
  end

  defp extra_validations do
    [
      &max_properties_and_required/1,
      &min_properties_max_properties/1,
      &validate_required_properties/1,
      &validate_non_overlapping_pattern_properties/1,
      &min_properties_possible/1
    ]
  end

  defp transformations do
    [
      &maybe_ignore_required/1,
      &set_required_properties/1,
      &properties_and_pattern_properties/1,
      &min_properties_required/1,
      &enforce_property_names_type/1,
      &catchall_pattern_properties/1
    ]
  end

  defp min_properties_max_properties(%{"minProperties" => min, "maxProperties" => max})
       when min > max do
    {:error, "minProperties > maxProperties"}
  end

  defp min_properties_max_properties(_), do: :ok

  defp max_properties_and_required(%{"maxProperties" => mp, "required" => req})
       when mp < length(req) do
    {:error, "required > maxProperties"}
  end

  defp max_properties_and_required(_), do: :ok

  defp set_required_properties(%{"required" => req} = schema) do
    props = Map.get(schema, "properties", %{})

    new_props =
      req
      |> Enum.reject(fn prop -> Map.has_key?(props, prop) end)
      |> Enum.map(fn prop -> try_possible_property(prop, schema) end)
      |> Enum.reject(&is_nil/1)
      |> Map.new()

    Map.update(schema, "properties", new_props, &Map.merge(&1, new_props))
  end

  defp set_required_properties(schema), do: schema

  defp maybe_ignore_required(%{"required" => []} = schema), do: Map.delete(schema, "required")
  defp maybe_ignore_required(schema), do: schema

  defp enforce_property_names_type(%{"propertyNames" => prop_names} = schema) do
    case Intersection.intersection(prop_names, %{"type" => "string"}) do
      {:ok, val} -> Map.put(schema, "propertyNames", val)
      _ -> Map.delete(schema, "propertyNames")
    end
  end

  defp enforce_property_names_type(schema), do: schema

  defp min_properties_required(%{"minProperties" => min_props, "required" => req} = schema) do
    if min_props <= length(req) do
      Map.delete(schema, "minProperties")
    else
      schema
    end
  end

  defp min_properties_required(schema), do: schema

  defp properties_and_pattern_properties(schema) do
    case Map.get(schema, "patternProperties") do
      nil -> schema
      pattern_props when is_map(pattern_props) -> intersect_properties(schema)
    end
  end

  defp intersect_properties(
         %{"properties" => props, "patternProperties" => pattern_props} = schema
       ) do
    new_props =
      Enum.reduce(pattern_props, props, fn {pattern, subschema}, properties ->
        re = Regex.compile!(pattern)

        Enum.reduce(properties, Map.new(), fn {prop_name, prop_schema}, acc ->
          if Regex.match?(re, prop_name) do
            Map.put(acc, prop_name, Intersection.safe_intersection(subschema, prop_schema))
          else
            Map.put(acc, prop_name, prop_schema)
          end
        end)
      end)

    Map.put(schema, "properties", new_props)
  end

  defp intersect_properties(schema), do: schema

  defp try_possible_property(property_name, schema) do
    # Try with patternProperties or with propertyNames + additionalProperties
    pattern_properties = Map.get(schema, "patternProperties", Map.new())

    pattern_properties
    |> Enum.find(fn {regex, _subschema} ->
      Regex.match?(Regex.compile!(regex), property_name)
    end)
    |> case do
      nil -> try_property_names(property_name, schema)
      {_, subschema} -> {property_name, subschema}
    end
  end

  defp try_property_names(_, %{"additionalProperties" => false}), do: nil

  defp try_property_names(property_name, schema) do
    property_names = Map.get(schema, "propertyNames", %{"type" => "string"})
    additional_properties = Map.get(schema, "additionalProperties", true)

    case JSV.validate(property_name, Context.build!(property_names)) do
      {:ok, ^property_name} -> {property_name, additional_properties}
      _ -> nil
    end
  end

  defp validate_required_properties(%{"properties" => props, "required" => req}) do
    Enum.reduce_while(req, :ok, fn required_property, _ ->
      if Map.has_key?(props, required_property) and props[required_property] != false do
        {:cont, :ok}
      else
        {:halt, {:error, "#{required_property} missing from properties"}}
      end
    end)
  end

  defp validate_required_properties(_), do: :ok

  defp validate_non_overlapping_pattern_properties(%{"patternProperties" => pattern_props}) do
    keys = Map.keys(pattern_props)

    combs = for k1 <- keys, k2 <- keys, k1 != k2, do: {k1, k2}

    Enum.reduce_while(combs, :ok, fn {k1, k2}, _ ->
      case Pattern.intersection(k1, k2) do
        {:ok, _} -> {:halt, {:error, "non-empty intersection patternProperties: #{k1}, #{k2}"}}
        _ -> {:cont, :ok}
      end
    end)
  end

  defp validate_non_overlapping_pattern_properties(_), do: :ok

  defp min_properties_possible(%{"minProperties" => min_props} = schema) do
    cond do
      Map.get(schema, "propertyNames") != false and
          Map.get(schema, "additionalProperties") != false ->
        :ok

      Map.get(schema, "patternProperties", %{}) != %{} ->
        :ok

      length(possible_properties(schema)) >= min_props ->
        :ok

      true ->
        {:error, "cannot generate minProperties #{min_props} from schema"}
    end
  end

  defp min_properties_possible(_schema), do: :ok

  defp empty_pattern_properties?(schema) do
    Map.get(schema, "patternProperties", %{}) |> Map.values() |> Enum.all?(&(&1 == false))
  end

  # Some people man...
  defp catchall_pattern_properties(schema) do
    pattern_props = Map.get(schema, "patternProperties", %{})
    catch_all_props = [".", "^.+$", "^.*$", ".*", ".+", "^(.*)$"]

    if Enum.any?(catch_all_props, &Map.has_key?(pattern_props, &1)) do
      schema |> Map.put("additionalProperties", false) |> Map.delete("propertyNames")
    else
      schema
    end
  end

  defp maybe_empty_object({:error, _} = error), do: error

  defp maybe_empty_object({:ok, schema}) do
    case {empty_object?(schema), Map.get(schema, "minProperties", 0)} do
      {false, _} -> {:ok, schema}
      {true, 0} -> {:ok, %{"enum" => [%{}]}}
    end
  end

  defp empty_object?(schema) do
    properties = Map.get(schema, "properties", %{})

    Enum.all?([
      Map.get(schema, "additionalProperties", true) == false,
      properties == false or Enum.all?(Map.values(properties), &(&1 == false)),
      empty_pattern_properties?(schema)
    ])
  end

  def possible_properties(schema) do
    schema
    |> Map.get("properties", %{})
    |> Enum.reject(fn {_key, value} -> value == false end)
    |> Enum.map(fn {key, _value} -> key end)
  end
end
