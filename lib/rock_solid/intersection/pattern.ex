defmodule RockSolid.Intersection.Pattern do
  @moduledoc """
  Performs the regex intersection between two patterns
  """

  alias RockSolid.Context

  def intersection(r1, r2) when is_binary(r1) and is_binary(r2) do
    case Context.get_intersection(r1, r2) do
      nil ->
        Context.store_intersection(r1, r2, intersect(r1, r2))
        intersection(r1, r2)

      value ->
        value
    end
  end

  def intersect(r1, r2) when is_binary(r1) and is_binary(r2) do
    {result, _globals} =
      Pythonx.eval(
        """
        import greenery.parse

        str(greenery.parse(str(r1)) & greenery.parse(str(r2)))
        """,
        %{"r1" => r1, "r2" => r2}
      )

    result = Pythonx.decode(result)

    case Regex.scan(binary_pattern(), result) do
      [[_, "[]"]] -> {:error, :empty_intersection}
      [[_, group]] -> {:ok, group}
      _ -> {:error, "invalid regex intersection: #{inspect(result)}"}
    end
  rescue
    # For practical purposes we can assume the intersection is empty
    _ -> {:error, :empty_intersection}
  end

  defp binary_pattern, do: ~r/b'(.*)'/
end
