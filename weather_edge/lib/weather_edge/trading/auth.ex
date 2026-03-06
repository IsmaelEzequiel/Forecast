defmodule WeatherEdge.Trading.Auth do
  @moduledoc """
  Authentication for Polymarket CLOB API.

  L1: EIP-712 typed data signatures for order signing (on-chain).
  L2: HMAC-SHA256 signatures for API request authentication (off-chain).
  """

  # Polymarket CTF Exchange on Polygon mainnet
  @exchange_address "0x4bFb41d5B3570DeFd03C39a9A4D8dE6Bd8B8982E"

  # EIP-712 domain separator components
  @domain_name "Polymarket CTF Exchange"
  @domain_version "1"

  # EIP-712 type hashes (precomputed keccak256 of type strings)
  @eip712_domain_type "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
  @order_type "Order(uint256 salt,address maker,address signer,address taker,uint256 tokenId,uint256 makerAmount,uint256 takerAmount,uint256 expiration,uint256 nonce,uint256 feeRateBps,uint8 side,uint8 signatureType)"

  # --- L1: EIP-712 Order Signing ---

  @doc """
  Signs an order using EIP-712 typed data signature.

  Order map keys:
    - salt, token_id, maker_amount, taker_amount, expiration, nonce, fee_rate_bps: integers
    - maker, signer, taker: hex address strings
    - side: 0 (BUY) or 1 (SELL)
    - signature_type: 0 (EOA) or 1 (POLY_PROXY) or 2 (POLY_GNOSIS_SAFE)

  Returns `{:ok, signature_hex}` or `{:error, reason}`.
  """
  @spec sign_order(map()) :: {:ok, String.t()} | {:error, term()}
  def sign_order(order) do
    private_key = get_private_key()

    if is_nil(private_key) do
      {:error, :missing_private_key}
    else
      chain_id = get_chain_id()
      domain_hash = compute_domain_separator(chain_id)
      struct_hash = compute_order_struct_hash(order)

      # EIP-712: "\x19\x01" ++ domainSeparator ++ structHash
      message =
        <<0x19, 0x01>> <>
          domain_hash <>
          struct_hash

      digest = keccak256(message)
      sign_digest(digest, private_key)
    end
  end

  @doc """
  Computes the EIP-712 domain separator for Polymarket exchange.
  """
  @spec compute_domain_separator(integer()) :: binary()
  def compute_domain_separator(chain_id) do
    type_hash = keccak256(@eip712_domain_type)
    name_hash = keccak256(@domain_name)
    version_hash = keccak256(@domain_version)

    encoded =
      type_hash <>
        name_hash <>
        version_hash <>
        encode_uint256(chain_id) <>
        encode_address(@exchange_address)

    keccak256(encoded)
  end

  @doc """
  Computes the EIP-712 struct hash for an order.
  """
  @spec compute_order_struct_hash(map()) :: binary()
  def compute_order_struct_hash(order) do
    type_hash = keccak256(@order_type)

    encoded =
      type_hash <>
        encode_uint256(order[:salt] || order["salt"]) <>
        encode_address(order[:maker] || order["maker"]) <>
        encode_address(order[:signer] || order["signer"]) <>
        encode_address(order[:taker] || order["taker"]) <>
        encode_uint256(order[:token_id] || order["token_id"]) <>
        encode_uint256(order[:maker_amount] || order["maker_amount"]) <>
        encode_uint256(order[:taker_amount] || order["taker_amount"]) <>
        encode_uint256(order[:expiration] || order["expiration"]) <>
        encode_uint256(order[:nonce] || order["nonce"]) <>
        encode_uint256(order[:fee_rate_bps] || order["fee_rate_bps"]) <>
        encode_uint8(order[:side] || order["side"]) <>
        encode_uint8(order[:signature_type] || order["signature_type"])

    keccak256(encoded)
  end

  # --- L2: HMAC-SHA256 API Authentication ---

  @doc """
  Signs an API request using HMAC-SHA256 and returns auth headers.

  Returns a map of headers:
    - POLY-ADDRESS
    - POLY-SIGNATURE
    - POLY-TIMESTAMP
    - POLY-NONCE
    - POLY-API-KEY
    - POLY-PASSPHRASE
  """
  @spec sign_request(String.t(), String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def sign_request(method, path, body \\ "") do
    config = polymarket_config()
    api_key = config[:api_key]
    api_secret = config[:api_secret]
    api_passphrase = config[:api_passphrase]
    wallet_address = config[:wallet_address]

    cond do
      is_nil(api_key) -> {:error, :missing_api_key}
      is_nil(api_secret) -> {:error, :missing_api_secret}
      is_nil(api_passphrase) -> {:error, :missing_api_passphrase}
      is_nil(wallet_address) -> {:error, :missing_wallet_address}
      true ->
        timestamp = to_string(System.system_time(:second))
        nonce = generate_nonce()

        message = timestamp <> "\n" <> String.upcase(method) <> "\n" <> path <> "\n" <> body

        secret_bytes = Base.decode64!(api_secret)
        signature = :crypto.mac(:hmac, :sha256, secret_bytes, message) |> Base.encode64()

        headers = %{
          "POLY-ADDRESS" => wallet_address,
          "POLY-SIGNATURE" => signature,
          "POLY-TIMESTAMP" => timestamp,
          "POLY-NONCE" => nonce,
          "POLY-API-KEY" => api_key,
          "POLY-PASSPHRASE" => api_passphrase
        }

        {:ok, headers}
    end
  end

  # --- Private Helpers ---

  defp sign_digest(digest, private_key_hex) do
    private_key_bytes = decode_hex(private_key_hex)

    case ExSecp256k1.sign(digest, private_key_bytes) do
      {:ok, {r, s, v}} ->
        # EIP-712 signature: r (32 bytes) + s (32 bytes) + v (1 byte, 27 or 28)
        v_byte = if v < 27, do: v + 27, else: v
        signature = r <> s <> <<v_byte::8>>
        {:ok, "0x" <> Base.encode16(signature, case: :lower)}

      {:error, reason} ->
        {:error, {:signing_failed, reason}}
    end
  end

  defp keccak256(data) when is_binary(data) do
    ExKeccak.hash_256(data)
  end

  defp encode_uint256(value) when is_integer(value) do
    <<value::unsigned-big-integer-size(256)>>
  end

  defp encode_uint8(value) when is_integer(value) do
    <<0::unsigned-big-integer-size(248), value::unsigned-big-integer-size(8)>>
  end

  defp encode_address(hex_address) when is_binary(hex_address) do
    address_bytes = decode_hex(hex_address)
    # Pad to 32 bytes (left-padded with zeros)
    padding_size = 32 - byte_size(address_bytes)
    <<0::size(padding_size * 8)>> <> address_bytes
  end

  defp decode_hex("0x" <> hex), do: Base.decode16!(hex, case: :mixed)
  defp decode_hex(hex), do: Base.decode16!(hex, case: :mixed)

  defp generate_nonce do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  defp get_private_key do
    polymarket_config()[:private_key]
  end

  defp get_chain_id do
    polymarket_config()[:chain_id] || 137
  end

  defp polymarket_config do
    Application.get_env(:weather_edge, :polymarket, [])
  end
end
