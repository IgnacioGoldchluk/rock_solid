defmodule RockSolid.Exceptions do
  @moduledoc false
  defmodule InvalidSchema do
    defexception [:reason, :schema]

    def message(%{reason: :additional_properties, schema: {left, right}}) do
      "Cannot apply #{inf_inspect(right)} to #{inf_inspect(left)} because it does not support additionalProperties"
    end

    def message(%{reason: :empty_simplification, schema: schema} = _exception) do
      "No values can be generated from #{inf_inspect(schema)}"
    end

    defp inf_inspect(value), do: inspect(value, limit: :infinity)
  end

  defmodule InvalidKeyword do
    defexception [:keyword, :path, :value]

    def message(%{keyword: keyword, path: path, value: nil}) do
      "Unsupported keyword '#{keyword}' in #{path}"
    end

    def message(%{keyword: keyword, path: path, value: value}) do
      "Unsupported keyword-value pair {'#{keyword}', #{inspect(value)}} in #{path}"
    end
  end
end
