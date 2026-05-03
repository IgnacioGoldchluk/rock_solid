defmodule RockSolid.Intersection.EnumTest do
  use ExUnit.Case, async: true

  alias RockSolid.Intersection

  describe "intersection/2" do
    test "const and enum returns matching" do
      s1 = %{"const" => 123}
      s2 = %{"enum" => [12, 123, 1234]}

      assert {:ok, %{"enum" => [123]}} == Intersection.intersection(s1, s2)
      assert {:ok, %{"enum" => [123]}} == Intersection.intersection(s2, s1)
    end

    test "two enums returns matching" do
      s1 = %{"enum" => [1, "a", "b", "d"]}
      s2 = %{"enum" => [2, "a", "c", "d"]}

      assert {:ok, %{"enum" => ["a", "d"]}} == Intersection.intersection(s1, s2)
    end

    test "enum and schema returns matching" do
      s1 = %{"enum" => [1, 2, 3, 4, 5, 6]}
      s2 = %{"type" => "integer", "multipleOf" => 2}

      assert {:ok, %{"enum" => [2, 4, 6]}} == Intersection.intersection(s1, s2)
    end

    test "non-matching enums is invalid" do
      s1 = %{"enum" => [1, 2, 3, 4]}
      s2 = %{"type" => "number", "minimum" => 10}

      assert {:error, "no matching values" <> _} = Intersection.intersection(s1, s2)
    end

    test "non-overlapping enums returns false" do
      s1 = %{"enum" => [1, 6, "a", nil]}
      s2 = %{"enum" => [5, 2, "b", false]}

      assert {:error, "no matching values" <> _} = Intersection.intersection(s1, s2)
    end
  end
end
