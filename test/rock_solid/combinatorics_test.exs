defmodule RockSolid.CombinatoricsTest do
  use RockSolid.TestCase, async: true

  alias RockSolid.Combinatorics

  describe "power_set/1" do
    test "empty enumerable returns empty set" do
      assert [[]] = Combinatorics.power_set([])
    end

    test "single element only contains empty set and itself" do
      assert uequals?(Combinatorics.power_set([:x]), [[], [:x]])
    end

    test "returns all subsets of enumerable" do
      elements = ~w(x y z)a

      result = Combinatorics.power_set(elements)

      expected = [
        [],
        [:x],
        [:y],
        [:z],
        [:x, :y],
        [:x, :z],
        [:y, :z],
        [:x, :y, :z]
      ]

      uequals?(result, expected)
    end
  end
end
