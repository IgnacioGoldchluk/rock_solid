defmodule RockSolid.TestCase do
  @moduledoc """
  Test case for JSON schema tests
  """
  use ExUnit.CaseTemplate

  using do
    quote do
      import RockSolid.TestCase
    end
  end

  def schema_id, do: "https://example#{System.unique_integer([:positive])}.com"

  @doc """
  Returns whether two lists are equal when the order does not matter
  """
  def equals?(result, expected) when is_list(result) and is_list(expected) do
    assert length(result) == length(expected)
    Enum.each(expected, fn s -> assert s in result end)
  end

  @doc """
  Same as `equals?/2` but for lists of lists where the order of each element
  does not matter either
  """
  def uequals?(result, expected) when is_list(result) and is_list(expected) do
    assert length(result) == length(expected)

    assert MapSet.equal?(MapSet.new(result, &MapSet.new/1), MapSet.new(expected, &MapSet.new/1))
  end
end
