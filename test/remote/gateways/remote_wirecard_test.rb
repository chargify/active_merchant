require 'test_helper'

class RemoteWirecardTest < Test::Unit::TestCase
  def setup
    test_account = fixtures(:wirecard)
    test_account[:signature] = test_account[:login]
    @gateway = WirecardGateway.new(test_account)

    @amount = 100
    @credit_card = credit_card('4200000000000000')
    @declined_card = credit_card('4000300011112220')

    @options = {
      :order_id => 1,
      :billing_address => address,
      :description => 'Wirecard remote test purchase',
      :email => 'soleone@example.com'
    }

    @german_address = {
      :name     => 'Jim Deutsch',
      :address1 => '1234 Meine Street',
      :company  => 'Widgets Inc',
      :city     => 'Koblenz',
      :state    => 'Rheinland-Pfalz',
      :zip      => '56070',
      :country  => 'DE',
      :phone    => '0261 12345 23',
      :fax      => '0261 12345 23-4'
    }
  end

  # Success tested
  def test_successful_authorization
    assert response = @gateway.authorize(@amount, @credit_card, @options)
    assert_success response
    assert response.test?
    assert response.message[/THIS IS A DEMO/]
    assert response.authorization
  end

  def test_successful_authorize_and_capture
    amount = @amount
    assert auth = @gateway.authorize(amount, @credit_card, @options)
    assert_success auth
    assert auth.message[/THIS IS A DEMO/]
    assert auth.authorization
    assert capture = @gateway.capture(amount, auth.authorization, @options)
    assert_success capture
  end

  def test_successful_authorize_and_partial_capture
    assert auth = @gateway.authorize(@amount, @credit_card, @options)
    assert_success auth
    assert auth.message[/THIS IS A DEMO/]
    assert auth.authorization

    #Capture some of the authorized amount
    assert capture = @gateway.capture(@amount - 10, auth.authorization, @options)
    assert_success capture
  end

  def test_successful_purchase
    assert response = @gateway.purchase(@amount, @credit_card, @options)
    # puts response.message
    assert_success response
    assert response.message[/THIS IS A DEMO/]
  end

  def test_successful_purchase_with_german_address_german_state_and_german_phone
    assert response = @gateway.purchase(@amount, @credit_card, @options.merge(:billing_address => @german_address))

    assert_success response
    assert response.message[/THIS IS A DEMO/]
  end

  def test_successful_purchase_with_german_address_no_state_and_invalid_phone
    assert response = @gateway.purchase(@amount, @credit_card, @options.merge(:billing_address => @german_address.merge({:state => nil, :phone => '1234'})))

    assert_success response
    assert response.message[/THIS IS A DEMO/]
  end

  def test_successful_purchase_with_german_address_and_valid_phone
    assert response = @gateway.purchase(@amount, @credit_card, @options.merge(:billing_address => @german_address.merge({:phone => '+049-261-1234-123'})))

    assert_success response
    assert response.message[/THIS IS A DEMO/]
  end

  def test_successful_store
    assert response = @gateway.store(@credit_card)
    assert_success response
    assert response.authorization
  end

  def test_successful_store_then_purchase_by_reference
    assert auth = @gateway.store(@credit_card, @options)
    assert_success auth
    assert auth.authorization
    assert purchase = @gateway.purchase(@amount, auth.authorization, @options)
    assert_success purchase
  end

  def test_successful_authorization_as_recurring_transaction_type_initial
    assert response = @gateway.authorize(@amount, @credit_card, @options.merge(:recurring => "Initial"))
    assert_success response
    assert response.authorization
  end

  def test_successful_purchase_as_recurring_transaction_type_initial
    assert response = @gateway.purchase(@amount, @credit_card, @options.merge(:recurring => "Initial"))
    assert_success response
    assert response.authorization
  end

  # Failure tested

  def test_wrong_creditcard_authorization
    assert response = @gateway.authorize(@amount, @declined_card, @options)
    assert_failure response
    assert response.test?
    assert response.message[/credit card number not allowed in demo mode/i]
  end

  def test_wrong_creditcard_purchase
    assert response = @gateway.purchase(@amount, @declined_card, @options)
    assert response.test?
    assert_failure response
    assert response.message[ /Credit card number not allowed in demo mode/ ], "Got wrong response message"
  end

  def test_wrong_creditcard_store
    assert response = @gateway.store(@declined_card, @options)
    assert response.test?
    assert_failure response
    assert response.message[ /Credit card number not allowed in demo mode/ ], "Got wrong response message"
  end

  def test_unauthorized_capture
    assert response = @gateway.capture(@amount, "1234567890123456789012")
    assert_failure response
    assert_equal "Could not find referenced transaction for GuWID 1234567890123456789012.", response.message
  end

  def test_unauthorized_purchase
    assert response = @gateway.purchase(@amount, "1234567890123456789012")
    assert_failure response
    assert_equal "Could not find referenced transaction for GuWID 1234567890123456789012.", response.message
  end

  def test_invalid_login
    gateway = WirecardGateway.new(:login => '', :password => '', :signature => '')
    assert response = gateway.purchase(@amount, @credit_card, @options)
    assert_failure response
    assert_equal "Invalid Login", response.message
  end
end
