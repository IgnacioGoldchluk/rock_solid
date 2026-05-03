defmodule RockSolid.Schemas.Schema do
  @moduledoc """
  Base schema that defines common keys for every other schema
  """

  @type t :: map() | boolean()

  def base_types, do: type().values |> Enum.map(&elem(&1, 0)) |> Enum.reject(&(&1 == "integer"))

  def type do
    Zoi.enum(["number", "string", "object", "array", "boolean", "null", "integer"])
  end

  defp optional, do: Zoi.optional(Zoi.json())

  def common_keywords do
    %{
      "type" => Zoi.optional(type()),
      "not" => optional(),
      "anyOf" => Zoi.list(optional()) |> Zoi.optional(),
      "allOf" => Zoi.list(optional()) |> Zoi.optional(),
      "oneOf" => Zoi.list(optional()) |> Zoi.optional(),
      "$defs" => optional(),
      "definitions" => optional(),
      "$anchor" => Zoi.optional(Zoi.string()),
      "writeOnly" => Zoi.optional(Zoi.boolean()),
      "readOnly" => Zoi.optional(Zoi.boolean()),
      "id" => Zoi.optional(Zoi.string()),
      "$id" => Zoi.optional(Zoi.string()),
      "$ref" => Zoi.optional(Zoi.string()),
      "if" => optional(),
      "then" => optional(),
      "else" => optional(),
      "enum" => Zoi.optional(Zoi.list()),
      "const" => Zoi.optional(Zoi.any())
    }
  end

  def discard_nulls(map) when is_map(map), do: Map.reject(map, fn {_k, v} -> is_nil(v) end)

  def fields(schema), do: Enum.map(schema.schema().fields, fn {field, _} -> field end)

  def formats(module) do
    module.schema().fields
    |> Enum.find(fn {field_name, _values} -> field_name == "format" end)
    |> case do
      {"format", enums} -> Enum.map(enums.values, &elem(&1, 0))
      nil -> []
    end
  end
end
