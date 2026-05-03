defmodule RockSolid.Intersection do
  @moduledoc """
  Computes intersections
  """
  alias RockSolid.Context
  alias RockSolid.Intersection
  alias RockSolid.Schemas.Schema
  alias RockSolid.Transformation

  @number_types ["integer", "number"]

  @doc """
  Performs the intersection between two schemas.
  """
  @spec intersection(Schema.t(), Schema.t()) :: {:ok, Schema.t()} | {:error, any()}
  def intersection(schema1, schema2)

  # true/false cases first
  def intersection(true, schema), do: {:ok, schema}
  def intersection(schema, true), do: {:ok, schema}
  def intersection(false, _), do: {:ok, false}
  def intersection(_, false), do: {:ok, false}

  # Contains not clauses
  def intersection(schema1, schema2) do
    {not1, s1} = Map.pop(schema1, "not")
    {not2, s2} = Map.pop(schema2, "not")
    not_clauses = Enum.flat_map([not1, not2], &not_clauses/1)

    with {:ok, result} when result != false <- do_intersection(s1, s2),
         value when value != false <- Intersection.Not.add_clauses(result, not_clauses) do
      {:ok, value}
    else
      false ->
        {:error,
         "empty intersection with 'not' clauses: #{inspect(schema1)}, #{inspect(schema2)}"}

      {:ok, false} ->
        {:error, "empty intersection #{inspect(schema1)}, #{inspect(schema2)}"}

      {:error, _} = e ->
        e
    end
  end

  # Same reference
  defp do_intersection(%{"$ref" => r1}, %{"$ref" => r1}), do: {:ok, %{"$ref" => r1}}

  # Different reference
  defp do_intersection(%{"$ref" => _} = s1, s2), do: with_ref(s1, s2)
  defp do_intersection(s1, %{"$ref" => _} = s2), do: with_ref(s1, s2)

  # enum or const
  defp do_intersection(%{"const" => val}, schema), do: intersection(%{"enum" => [val]}, schema)
  defp do_intersection(schema, %{"const" => val}), do: intersection(%{"enum" => [val]}, schema)
  defp do_intersection(%{"enum" => val}, schema), do: Intersection.Enum.intersection(val, schema)
  defp do_intersection(schema, %{"enum" => val}), do: Intersection.Enum.intersection(val, schema)

  defp do_intersection(%{"anyOf" => _} = s1, s2) when map_size(s1) == 1,
    do: Intersection.AnyOf.intersection(s1, s2)

  defp do_intersection(s1, %{"anyOf" => _} = s2) when map_size(s2) == 1,
    do: Intersection.AnyOf.intersection(s1, s2)

  defp do_intersection(s1, %{"anyOf" => any_of} = s2) do
    case Intersection.AnyOf.intersection(Map.delete(s2, "anyOf"), %{"anyOf" => any_of}) do
      {:ok, value} -> intersection(s1, value)
      error -> error
    end
  end

  defp do_intersection(%{"anyOf" => any_of} = s1, s2) do
    case Intersection.AnyOf.intersection(Map.delete(s1, "anyOf"), %{"anyOf" => any_of}) do
      {:ok, value} -> intersection(s2, value)
      error -> error
    end
  end

  ## Concrete types
  # String
  defp do_intersection(%{"type" => "string"} = s1, %{"type" => "string"} = s2) do
    Intersection.String.intersection(s1, s2)
  end

  # Number (number or integer)
  defp do_intersection(%{"type" => t1} = s1, %{"type" => t2} = s2)
       when t1 in @number_types and t2 in @number_types do
    Intersection.Number.intersection(s1, s2)
  end

  # Null and boolean. Since they don't have extra keywords we can
  # simply return the value
  defp do_intersection(%{"type" => t} = s, %{"type" => t}) when t in ["boolean", "null"] do
    {:ok, s}
  end

  # Array
  defp do_intersection(%{"type" => "array"} = s1, %{"type" => "array"} = s2) do
    Intersection.Array.intersection(s1, s2)
  end

  defp do_intersection(%{"type" => "object"} = s1, %{"type" => "object"} = s2) do
    Intersection.Object.intersection(s1, s2)
  end

  # Mismatched type
  defp do_intersection(%{"type" => t1}, %{"type" => t2})
       when is_binary(t1) and is_binary(t2) and t1 != t2 do
    {:error, "mismatched types #{t1} vs #{t2}"}
  end

  # Type is either a list or not present, convert to list and intersect
  defp do_intersection(schema1, schema2) do
    intersection(schema2, Transformation.to_any_of(schema1))
  end

  defp with_ref(schema1, schema2) do
    # We don't care about types in this case
    schema1 = sanitize_ref(schema1)
    schema2 = sanitize_ref(schema2)
    key = {schema1, schema2}

    case Context.get(key) do
      "#/PLACEHOLDER_" <> _ = placeholder ->
        {:ok, %{"$ref" => placeholder}}

      nil ->
        placeholder_name = Context.put_placeholder(key)

        value =
          case do_intersection(expand(schema1), expand(schema2)) do
            {:ok, value} -> value
            {:error, _} -> false
          end

        Context.put(key, value)
        Context.add_on_the_fly_def(key, placeholder_name)
        {:ok, Context.get(key)}

      other ->
        {:ok, other}
    end
  end

  defp expand(%{"$ref" => ptr}), do: Context.get_ref(ptr)
  defp expand(schema), do: schema

  @doc """
  Same as `intersection/2` but returns the value or `false` when the intersection
  is empty
  """
  @spec safe_intersection(Schema.t(), Schema.t()) :: Schema.t()
  def safe_intersection(schema1, schema2) do
    case intersection(schema1, schema2) do
      {:ok, value} -> value
      {:error, _} -> false
    end
  end

  @doc """
  Returns true if two schemas are mutually exclusive
  """
  @spec mutually_exclusive?(Schema.t(), Schema.t()) :: boolean()
  def mutually_exclusive?(s1, s2), do: safe_intersection(s1, s2) == false

  @doc """
  Returns true if a schema contains a "not" clause that always
  succeeds when the rest of the schema succeeds
  """
  @spec impossible?(Schema.t()) :: boolean()
  def impossible?(schema) when is_map(schema) do
    case Map.pop(schema, "not") do
      {nil, _} ->
        false

      {%{"anyOf" => clauses}, s} ->
        Enum.any?(clauses, &(safe_intersection(&1, s) == s))

      {not_, %{"const" => value}} ->
        match?({:ok, _}, JSV.validate(value, Context.build!(not_)))

      {not_, %{"enum" => values}} ->
        jsv_schema = Context.build!(not_)
        Enum.all?(values, fn value -> match?({:ok, _}, JSV.validate(value, jsv_schema)) end)

      {not_, s} ->
        safe_intersection(not_, s) == s
    end
  end

  def impossible?(false), do: true
  def impossible?(true), do: false

  defp not_clauses(nil), do: []
  defp not_clauses(%{"anyOf" => clauses}), do: clauses
  defp not_clauses(clause), do: [clause]

  defp sanitize_ref(%{"$ref" => _} = schema), do: Map.take(schema, ["$ref"])
  defp sanitize_ref(schema), do: schema
end
