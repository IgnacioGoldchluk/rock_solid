defmodule RockSolid.Intersection.AnyOf do
  @moduledoc """
  Computes the intersection between two schemas, where at least
  one of them is an `anyOf` clause
  """
  alias RockSolid.Intersection

  def intersection(%{"anyOf" => s1}, %{"anyOf" => s2}), do: product_intersection(s1, s2)
  def intersection(s1, %{"anyOf" => s2}), do: product_intersection([s1], s2)
  def intersection(%{"anyOf" => s1}, s2), do: product_intersection(s1, [s2])

  defp product_intersection(left, right) do
    intersections =
      for l <- left,
          r <- right,
          intersection = Intersection.safe_intersection(l, r),
          intersection != false,
          do: intersection

    case intersections do
      [] -> {:error, "empty anyOf intersection"}
      [value] -> {:ok, value}
      values when is_list(values) -> {:ok, %{"anyOf" => values}}
    end
  end
end
