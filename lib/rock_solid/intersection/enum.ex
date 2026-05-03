defmodule RockSolid.Intersection.Enum do
  @moduledoc """
  "enum" type intersection with another schema
  """

  alias RockSolid.Context

  @doc """
  Computes the intersection between a list of enum `values` and a `schema`
  """
  @spec intersection(list(), map()) :: {:ok, map() | boolean()} | {:error, list()}
  def intersection(values, schema) when is_list(values) do
    json_schema = Context.build!(schema)

    values
    |> Enum.filter(fn value ->
      case JSV.validate(value, json_schema) do
        {:ok, _} -> true
        _ -> false
      end
    end)
    |> case do
      [] -> {:error, "no matching values in #{inspect(values)} for #{inspect(schema)}"}
      matching_vals -> {:ok, %{"enum" => matching_vals}}
    end
  end
end
