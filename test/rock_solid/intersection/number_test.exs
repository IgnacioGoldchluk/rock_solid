defmodule RockSolid.Intersection.NumberTest do
  use ExUnit.Case, async: true

  alias RockSolid.Intersection

  describe "intersection/2" do
    test "integers with overlapping range" do
      i1 = %{"type" => "integer", "exclusiveMinimum" => 10, "multipleOf" => 2}
      i2 = %{"type" => "integer", "minimum" => 6, "maximum" => 300, "multipleOf" => 3}

      {:ok, schema} = Intersection.intersection(i1, i2)
      {:ok, s2} = Intersection.intersection(i2, i1)

      assert s2 == schema

      assert schema == %{
               "type" => "integer",
               "exclusiveMinimum" => 10,
               "maximum" => 300,
               "multipleOf" => 6
             }
    end

    test "non-overlapping range is invalid" do
      i1 = %{"type" => "number", "minimum" => 1, "maximum" => 255}
      i2 = %{"type" => "number", "minimum" => 1_000, "maximum" => 10_000}

      assert {:error, [%Zoi.Error{message: msg}]} = Intersection.intersection(i1, i2)

      assert msg == "minimum > maximum"
    end

    test "open maximum range does not include key for open side" do
      i1 = %{"type" => "integer", "maximum" => 10}
      i2 = %{"type" => "number", "maximum" => 0}

      assert {:ok, schema} = Intersection.intersection(i1, i2)
      {:ok, s2} = Intersection.intersection(i2, i1)

      assert s2 == schema

      assert schema == %{"type" => "integer", "maximum" => 0}
    end

    test "open minimum range does not include key for open side" do
      i1 = %{"type" => "integer", "minimum" => 10}
      i2 = %{"type" => "number"}

      assert {:ok, schema} = Intersection.intersection(i1, i2)
      {:ok, s2} = Intersection.intersection(i2, i1)

      assert s2 == schema

      assert schema == %{"type" => "integer", "minimum" => 10}
    end

    test "only one multipleOf keeps it" do
      i1 = %{"type" => "number", "multipleOf" => 2}
      i2 = %{"type" => "number"}

      assert {:ok, schema} = Intersection.intersection(i1, i2)
      assert {:ok, s2} = Intersection.intersection(i2, i1)

      assert s2 == schema

      assert schema == %{"type" => "number", "multipleOf" => 2}
    end

    test "exclusiveMaximum as maximum" do
      i1 = %{"type" => "number", "maximum" => 10}
      i2 = %{"type" => "number", "exclusiveMaximum" => 10}

      assert {:ok, schema} = Intersection.intersection(i1, i2)

      assert schema == %{"type" => "number", "exclusiveMaximum" => 10}
    end

    test "multipleOf supports floats" do
      i1 = %{"type" => "number", "multipleOf" => 2}
      i2 = %{"type" => "number", "multipleOf" => 2.5}

      assert {:ok, schema} = Intersection.intersection(i1, i2)

      assert schema == %{"type" => "number", "multipleOf" => 10}
    end

    test "overlapping range but no multipleOf is invalid" do
      i1 = %{"type" => "number", "minimum" => 1, "maximum" => 20, "multipleOf" => 5}
      i2 = %{"type" => "number", "minimum" => 6, "maximum" => 30, "multipleOf" => 7}

      assert {:error, [%Zoi.Error{message: msg}]} = Intersection.intersection(i1, i2)

      assert msg == "no multipleOf in range"
    end
  end
end
