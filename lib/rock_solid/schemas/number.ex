defmodule RockSolid.Schemas.Number do
  @moduledoc """
  Represents a number type
  """
  alias RockSolid.Schemas.{Refinements, Schema}

  @specific_keywords %{
    "type" => Zoi.enum(["number", "integer"]) |> Zoi.default("number"),
    "format" => Zoi.enum(["int64", "int32", "double", "float"]) |> Zoi.optional(),
    "multipleOf" => Zoi.number() |> Zoi.refine(&Refinements.not_zero/1) |> Zoi.optional(),
    "minimum" => Zoi.optional(Zoi.number()),
    "maximum" => Zoi.optional(Zoi.number()),
    "exclusiveMinimum" => Zoi.optional(Zoi.number()),
    "exclusiveMaximum" => Zoi.optional(Zoi.number())
  }

  @schema Zoi.map(Map.merge(Schema.common_keywords(), @specific_keywords))

  def new(attrs), do: schema() |> Zoi.parse(attrs) |> maybe_fixed_number()

  def schema do
    Enum.reduce(extra_validations(), @schema, fn fun, schema -> Zoi.refine(schema, fun) end)
    |> Zoi.transform(&round_ranges/1)
  end

  def min_value(%{"minimum" => num}) when is_number(num), do: num
  def min_value(%{"exclusiveMinimum" => num}) when is_number(num), do: num
  def min_value(_), do: nil

  def max_value(%{"maximum" => num}) when is_number(num), do: num
  def max_value(%{"exclusiveMaximum" => num}) when is_number(num), do: num
  def max_value(_), do: nil

  defp extra_validations do
    [&validate_range/1, &validate_multiple_of_matches_type/1]
  end

  defp validate_range(%{"minimum" => _, "exclusiveMinimum" => _}),
    do: {:error, "provide minimum OR exclusiveMinimum"}

  defp validate_range(%{"maximum" => _, "exclusiveMaximum" => _}),
    do: {:error, "provide maximum OR exclusiveMaximum"}

  defp validate_range(schema) do
    min = min_value(schema)
    max = max_value(schema)

    case {min, max} do
      {nil, _} ->
        :ok

      {_, nil} ->
        :ok

      {val, val} ->
        if Enum.any?(["exclusiveMinimum", "exclusiveMaximum"], &Map.has_key?(schema, &1)) do
          {:error, "minimum = maximum with exclusive range: #{val}"}
        else
          :ok
        end

      {min, max} when min > max ->
        {:error, "minimum > maximum"}

      {min, max} ->
        check_possible_values(min, max, schema)
    end
  end

  defp check_possible_values(min, max, %{"multipleOf" => multiple_of}) do
    normalized_min = min / multiple_of
    normalized_max = max / multiple_of

    if abs(normalized_max - normalized_min) >= 1 do
      :ok
    else
      {:error, "no multipleOf in range"}
    end
  end

  defp check_possible_values(_min, _max, _), do: :ok

  defp round_ranges(%{"type" => "number"} = schema), do: schema

  defp round_ranges(%{"type" => "integer"} = schema) do
    [
      {&round_up/1, "minimum"},
      {&round_up/1, "exclusiveMinimum"},
      {&round_down/1, "maximum"},
      {&round_down/1, "exclusiveMaximum"}
    ]
    |> Enum.filter(fn {_func, key} -> Map.has_key?(schema, key) end)
    |> Enum.reduce(schema, fn {func, key}, schema ->
      Map.update!(schema, key, func)
    end)
  end

  defp round_up(num) when is_integer(num), do: num
  defp round_up(num) when is_float(num), do: num |> :math.ceil() |> trunc()

  defp round_down(num) when is_integer(num), do: num
  defp round_down(num) when is_float(num), do: trunc(num)

  defp validate_multiple_of_matches_type(%{"type" => "integer", "multipleOf" => mo})
       when not is_integer(mo) do
    {:error, "integer specified but multipleOf is not integer: #{mo}"}
  end

  defp validate_multiple_of_matches_type(_), do: :ok

  defp maybe_fixed_number({:ok, %{"minimum" => m, "maximum" => m}}), do: {:ok, %{"enum" => [m]}}
  defp maybe_fixed_number(other), do: other
end
