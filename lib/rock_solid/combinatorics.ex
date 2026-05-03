defmodule RockSolid.Combinatorics do
  @moduledoc """
  Utilities for combinatorics
  """
  @doc """
  Returns the power set of the given enumerable. Assumes the elements are unique
  """
  @spec power_set(Enum.t()) :: [Enum.t()]
  def power_set(enumerable) do
    # Start with empty set, then for each element concatenate the current list
    # of sets and the current list of sets + the new element
    Enum.reduce(enumerable, [[]], fn elem, acc -> acc ++ Enum.map(acc, &[elem | &1]) end)
  end
end
