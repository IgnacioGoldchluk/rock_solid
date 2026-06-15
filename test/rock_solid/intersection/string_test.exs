defmodule RockSolid.Intersection.StringTest do
  use ExUnit.Case, async: true

  alias RockSolid.Intersection

  describe "intersection/2" do
    test "same string returns itself" do
      schema = %{"type" => "string", "minLength" => 3, "maxLength" => 5, "pattern" => "[A-Z]+"}

      assert {:ok, schema} == Intersection.intersection(schema, schema)
    end

    test "overlapping lengths" do
      s1 = %{"type" => "string", "minLength" => 4, "maxLength" => 10}
      s2 = %{"type" => "string", "minLength" => 6, "maxLength" => 8}

      assert {:ok, schema} = Intersection.intersection(s1, s2)
      assert {:ok, schema2} = Intersection.intersection(s2, s1)
      assert schema == schema2
      assert schema2 == %{"type" => "string", "minLength" => 6, "maxLength" => 8}
    end

    test "same format is valid" do
      s1 = %{"type" => "string", "format" => "ipv4"}
      assert {:ok, s1} == Intersection.intersection(s1, s1)
    end

    test "single format is valid" do
      s1 = %{"type" => "string", "format" => "uri"}
      s2 = %{"type" => "string"}

      assert {:ok, schema} = Intersection.intersection(s1, s2)
      assert {:ok, schema2} = Intersection.intersection(s2, s1)
      assert schema == schema2
      assert schema == s1
    end

    test "multiple format is invalid" do
      s1 = %{"type" => "string", "format" => "ipv4"}
      s2 = %{"type" => "string", "format" => "ipv6"}

      assert {:error, [%Zoi.Error{path: ["format"]}]} = Intersection.intersection(s1, s2)
    end

    test "single pattern is valid" do
      s1 = %{"type" => "string", "pattern" => "[A-Z]+"}
      s2 = %{"type" => "string"}

      assert {:ok, s1} == Intersection.intersection(s1, s2)
    end

    test "overlapping patterns" do
      s1 = %{"type" => "string", "pattern" => "[A-Z]+"}
      s2 = %{"type" => "string", "pattern" => "[a-zA-Z]+"}

      assert {:ok, schema} = Intersection.intersection(s1, s2)
      assert schema == %{"type" => "string", "pattern" => "[A-Z]+"}
    end

    test "non-overlapping patterns is invalid" do
      s1 = %{"type" => "string", "pattern" => "[A-Z]+"}
      s2 = %{"type" => "string", "pattern" => "\d+"}

      assert {:error, :empty_intersection} == Intersection.intersection(s1, s2)
    end
  end
end
