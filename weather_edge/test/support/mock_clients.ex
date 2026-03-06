defmodule WeatherEdge.Test.MockDataClient do
  @moduledoc false

  def get_balance(_opts \\ []) do
    case Process.get(:mock_balance) do
      nil -> {:ok, 100.0}
      balance -> {:ok, balance}
    end
  end
end

defmodule WeatherEdge.Test.MockClobClient do
  @moduledoc false

  def place_order(_token_id, _side, _price, _size, _type \\ "GTC") do
    case Process.get(:mock_place_order) do
      nil -> {:ok, %{"orderID" => "mock-order-#{System.unique_integer([:positive])}"}}
      response -> response
    end
  end

  def get_open_orders do
    case Process.get(:mock_open_orders) do
      nil -> {:ok, []}
      orders -> {:ok, orders}
    end
  end
end
