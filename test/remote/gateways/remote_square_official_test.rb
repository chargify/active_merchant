require "test_helper"

class RemoteSquareOfficialTest < Test::Unit::TestCase
  def setup
    @gateway = SquareOfficialGateway.new(fixtures(:square_official))

    @amount = 200
    @refund_amount = 100

    @card_nonce = "cnon:card-nonce-ok"
    @declined_card_nonce = "cnon:card-nonce-declined"

    @options = {
      email: "customer@example.com",
      billing_address: address
    }
  end

  def test_successful_purchase
    @options[:idempotency_key] = SecureRandom.hex(10)

    assert purchase = @gateway.purchase(@amount, @card_nonce, @options)

    assert_success purchase
    assert_equal @amount, purchase.params["payment"]["amount_money"]["amount"]
    assert_equal @gateway.default_currency.downcase, purchase.params["payment"]["amount_money"]["currency"].downcase
    assert_equal "COMPLETED", purchase.params["payment"]["status"]
  end

  def test_unsuccessful_purchase
    @options[:idempotency_key] = SecureRandom.hex(10)

    assert purchase = @gateway.purchase(@amount, @declined_card_nonce, @options)

    assert_failure purchase
    assert_equal "FAILED", purchase.params["payment"]["status"]
  end

  def test_successful_purchase_then_refund
    @options[:idempotency_key] = SecureRandom.hex(10)

    assert purchase = @gateway.purchase(@amount, @card_nonce, @options)

    assert_success purchase
    assert_equal "COMPLETED", purchase.params["payment"]["status"]

    sleep 2

    @options[:idempotency_key] = SecureRandom.hex(10)
    assert refund = @gateway.refund(@refund_amount, purchase.authorization, @options)

    assert_success refund
    assert_equal @refund_amount, refund.params["refund"]["amount_money"]["amount"]
    assert_equal @gateway.default_currency.downcase, refund.params["refund"]["amount_money"]["currency"].downcase
    assert_equal "PENDING", refund.params["refund"]["status"]
  end

  def test_successful_store
    @options[:idempotency_key] = SecureRandom.hex(10)

    assert store = @gateway.store(@card_nonce, @options)

    assert_instance_of MultiResponse, store
    assert_success store
    assert_equal 2, store.responses.size

    customer_response = store.responses[0]
    assert_not_nil customer_response.params["customer"]["id"]
    assert_equal @options[:email], customer_response.params["customer"]["email_address"]
    assert_equal @options[:billing_address][:name].split(" ")[0], customer_response.params["customer"]["given_name"]

    card_response = store.responses[1]
    assert_not_nil card_response.params["card"]["id"]

    assert store.test?
  end

  def test_unsuccessful_store_invalid_card
    @options[:idempotency_key] = SecureRandom.hex(10)

    assert store = @gateway.store(@declined_card_nonce, @options)

    assert_failure store
    assert_equal "INVALID_CARD", store.params["errors"][0]["code"]
  end

  def test_successful_store_then_unstore
    @options[:idempotency_key] = SecureRandom.hex(10)

    assert store = @gateway.store(@card_nonce, @options)

    assert_success store
    customer_response = store.responses[0]

    assert unstore = @gateway.unstore(customer_response.params["customer"]["id"])

    assert_success unstore
    assert_empty unstore.params
  end

  def test_successful_store_then_update
    @options[:idempotency_key] = SecureRandom.hex(10)

    assert store = @gateway.store(@card_nonce, @options)
    customer_response = store.responses[0]

    assert_equal @options[:billing_address][:name].split(" ")[0], customer_response.params["customer"]["given_name"]

    @options[:billing_address][:name] = "Tom Smith"
    assert update = @gateway.update_customer(customer_response.params["customer"]["id"], @options)

    assert_equal "Tom", update.params["customer"]["given_name"]
    assert_equal "Smith", update.params["customer"]["family_name"]
  end
end
