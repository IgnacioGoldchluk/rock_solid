defmodule RockSolid.Intersection.Pattern do
  @moduledoc """
  Performs the regex intersection between two patterns
  """

  # Can't believe it returns empty here
  @catchalls [".", "^.+$", "^.*$", ".*", ".+", "^(.*)$"]

  def intersection(r1, r2) when r1 in @catchalls, do: {:ok, r2}
  def intersection(r1, r2) when r2 in @catchalls, do: {:ok, r1}

  def intersection(r1, r2) do
    case RegexSolver.intersect(r1, r2) do
      {:error, _} = error -> error
      {:ok, value} -> {:ok, maybe_add_anchors(value, r1, r2)}
    end
  end

  defp maybe_add_anchors(value, r1, r2) do
    anchor_start? = String.starts_with?(r1, "^") or String.starts_with?(r2, "^")
    anchor_end? = String.ends_with?(r1, "$") or String.ends_with?(r2, "$")

    value |> anchor_start(anchor_start?) |> anchor_end(anchor_end?)
  end

  defp anchor_start(value, false), do: value
  defp anchor_start("^" <> _ = value, _), do: value
  defp anchor_start(value, true), do: "^" <> value

  defp anchor_end(value, false), do: value

  defp anchor_end(value, true) do
    if String.ends_with?(value, "$"), do: value, else: value <> "$"
  end
end
