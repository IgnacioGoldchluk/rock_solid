defmodule RockSolid.Intersection.Number do
  @moduledoc """
  Performs number intersections
  """

  alias RockSolid.Schemas.{Number, Schema}

  def intersection(num1, num2) do
    %{
      "multipleOf" => lcm(num1["multipleOf"], num2["multipleOf"]),
      "type" => type_intersection(num1["type"], num2["type"]),
      "format" => format_intersection(num1["format"], num2["format"])
    }
    |> Map.merge(ranges_intersection(num1, num2))
    |> Schema.discard_nulls()
    |> Number.new()
  end

  defp type_intersection("integer", _), do: "integer"
  defp type_intersection(_, "integer"), do: "integer"
  defp type_intersection(_, _), do: "number"

  defp format_intersection(f1, f2) do
    priority = ["int32", "int64", "float", "double"]
    formats = [f1, f2]

    Enum.find(priority, fn format -> Enum.member?(formats, format) end)
  end

  defp lcm(m1, nil), do: m1
  defp lcm(nil, m2), do: m2

  defp lcm(m1, m2) when is_integer(m1) and is_integer(m2) do
    div(m1 * m2, Integer.gcd(m1, m2))
  end

  defp lcm(m1, m2) do
    {num_m1, den_m1} = to_fraction(m1)
    {num_m2, den_m2} = to_fraction(m2)

    num = lcm(num_m1, num_m2) / Integer.gcd(den_m1, den_m2)
    if(trunc(num) == num, do: trunc(num), else: num)
  end

  defp to_fraction(num) when is_integer(num), do: {num, 1}

  defp to_fraction(num) when is_float(num) do
    decimal_places = to_string(num) |> String.split(".") |> Enum.at(-1) |> String.length()
    factor = 10 ** decimal_places
    numerator = trunc(num * factor)
    gcd = Integer.gcd(numerator, factor)

    {div(numerator, gcd), div(factor, gcd)}
  end

  defp ranges_intersection(num1, num2) do
    minimum =
      minimum_intersection(
        num1["exclusiveMinimum"] || num1["minimum"],
        num2["exclusiveMinimum"] || num2["minimum"]
      )

    maximum =
      maximum_intersection(
        num1["exclusiveMaximum"] || num1["maximum"],
        num2["exclusiveMaximum"] || num2["maximum"]
      )

    min_key =
      if(minimum in [num1["exclusiveMinimum"], num2["exclusiveMinimum"]],
        do: "exclusiveMinimum",
        else: "minimum"
      )

    max_key =
      if(maximum in [num1["exclusiveMaximum"], num2["exclusiveMaximum"]],
        do: "exclusiveMaximum",
        else: "maximum"
      )

    %{min_key => minimum, max_key => maximum}
  end

  def minimum_intersection(nil, n), do: n
  def minimum_intersection(n, nil), do: n
  def minimum_intersection(n1, n2), do: max(n1, n2)

  def maximum_intersection(nil, n), do: n
  def maximum_intersection(n, nil), do: n
  def maximum_intersection(n1, n2), do: min(n1, n2)
end
