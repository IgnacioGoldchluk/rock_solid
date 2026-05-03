defmodule RockSolid.Schemas.Refinements do
  @moduledoc false
  def not_zero(0), do: {:error, "cannot be 0"}
  def not_zero(_), do: :ok

  def compile_regex(regex) do
    case Regex.compile(regex) do
      {:ok, _} -> :ok
      {:error, {err, _}} -> {:error, "invalid regex: #{to_string(err)}"}
    end
  end
end
