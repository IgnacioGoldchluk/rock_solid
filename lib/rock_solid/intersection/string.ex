defmodule RockSolid.Intersection.String do
  @moduledoc """
  Performs string intersection
  """
  alias RockSolid.Intersection
  alias RockSolid.Schemas
  alias RockSolid.Schemas.Schema

  alias RockSolid.Types

  @spec intersection(Types.schema(), Types.schema()) :: {:error, Types.error_list()}
  def intersection(s1, s2) do
    schema =
      %{
        "format" => format_intersection(s1["format"], s2["format"]),
        "minLength" => Intersection.Number.minimum_intersection(s1["minLength"], s2["minLength"]),
        "maxLength" => Intersection.Number.maximum_intersection(s1["maxLength"], s2["maxLength"]),
        "pattern" => pattern_intersection(s1["pattern"], s2["pattern"])
      }

    case pattern_intersection(s1["pattern"], s2["pattern"]) do
      {:ok, pattern} ->
        Map.put(schema, "pattern", pattern) |> Schema.discard_nulls() |> Schemas.String.new()

      {:error, _reason} = e ->
        e
    end
  end

  defp format_intersection(nil, f1), do: f1
  defp format_intersection(f1, nil), do: f1
  defp format_intersection(f1, f1), do: f1
  defp format_intersection(_, _), do: :MISMATCHED_FORMAT

  defp pattern_intersection(nil, p1), do: {:ok, p1}
  defp pattern_intersection(p1, nil), do: {:ok, p1}
  defp pattern_intersection(p1, p1), do: {:ok, p1}

  defp pattern_intersection(p1, p2), do: Intersection.Pattern.intersection(p1, p2)
end
