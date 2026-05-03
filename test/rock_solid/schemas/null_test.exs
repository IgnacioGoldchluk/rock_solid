defmodule RockSolid.Schemas.NullTest do
  use ExUnit.Case

  alias RockSolid.Schemas

  describe "new/1" do
    test "creates null schema" do
      assert Schemas.Null.new(%{}) == {:ok, %{"type" => "null"}}
    end
  end
end
