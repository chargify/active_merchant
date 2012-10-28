require 'test_helper'

class WirecardTest < Test::Unit::TestCase
  include CommStub

  TEST_AUTHORIZATION_GUWID = 'C822580121385121429927'
  TEST_PURCHASE_GUWID = 'C865402121385575982910'
  TEST_CAPTURE_GUWID = 'C833707121385268439116'

  def setup
    @gateway = WirecardGateway.new(:login => '', :password => '', :signature => '')
    @credit_card = credit_card('4200000000000000')
    @declined_card = credit_card('4000300011112220')
    @unsupported_card = credit_card('4200000000000000', :brand => :maestro)

    @amount = 111

    @options = {
      :order_id => '1',
      :billing_address => address,
      :description => 'Wirecard Purchase',
      :email => 'soleone@example.com'
    }

    @address_without_state = {
      :name     => 'Jim Smith',
      :address1 => '1234 My Street',
      :company  => 'Widgets Inc',
      :city     => 'Ottawa',
      :zip      => 'K12 P2A',
      :country  => 'CA',
      :state    => nil,
    }
  end

  def test_successful_authorization
    @gateway.expects(:ssl_post).returns(successful_authorization_response)
    assert response = @gateway.authorize(@amount, @credit_card, @options)
    assert_instance_of Response, response

    assert_success response
    assert response.test?
    assert_equal TEST_AUTHORIZATION_GUWID, response.authorization
  end

  def test_successful_purchase
    @gateway.expects(:ssl_post).returns(successful_purchase_response)
    assert response = @gateway.purchase(@amount, @credit_card, @options)
    assert_instance_of Response, response

    assert_success response
    assert response.test?
    assert_equal TEST_PURCHASE_GUWID, response.authorization
  end

  def test_successful_authorization_using_reference_rather_than_card
    @gateway.expects(:ssl_post).returns(successful_authorization_response)
    assert response = @gateway.authorize(@amount, '12345', @options)
    assert_instance_of Response, response

    assert_success response
    assert response.test?
    assert_equal TEST_AUTHORIZATION_GUWID, response.authorization
  end

  def test_successful_purchase_using_reference_rather_than_card
    @gateway.expects(:ssl_post).returns(successful_purchase_response)
    assert response = @gateway.purchase(@amount, '12345', @options)
    assert_instance_of Response, response

    assert_success response
    assert response.test?
    assert_equal TEST_PURCHASE_GUWID, response.authorization
  end

  def test_wrong_credit_card_authorization
    @gateway.expects(:ssl_post).returns(wrong_creditcard_authorization_response)
    assert response = @gateway.authorize(@amount, @declined_card, @options)
    assert_instance_of Response, response

    assert_failure response
    assert response.test?
    assert_equal TEST_AUTHORIZATION_GUWID, response.authorization
    assert response.message[/credit card number not allowed in demo mode/i]
  end

  def test_successful_authorization_and_capture
    @gateway.expects(:ssl_post).returns(successful_authorization_response)
    assert response = @gateway.authorize(@amount, @credit_card, @options)
    assert_success response
    assert_equal TEST_AUTHORIZATION_GUWID, response.authorization

    @gateway.expects(:ssl_post).returns(successful_capture_response)
    assert response = @gateway.capture(@amount, response.authorization, @options)
    assert_success response
    assert response.test?
    assert response.message[/this is a demo/i]
  end

  def test_successful_authorization_and_partial_capture
    @gateway.expects(:ssl_post).returns(successful_authorization_response)
    assert response = @gateway.authorize(@amount, @credit_card, @options)
    assert_success response
    assert_equal TEST_AUTHORIZATION_GUWID, response.authorization

    @gateway.expects(:ssl_post).returns(successful_capture_response)
    assert response = @gateway.capture(@amount - 10, response.authorization, @options)
    assert_success response
    assert response.test?
    assert response.message[/this is a demo/i]
  end

  def test_unauthorized_capture
    @gateway.expects(:ssl_post).returns(unauthorized_capture_response)
    assert response = @gateway.capture(@amount, "1234567890123456789012", @options)

    assert_failure response
    assert_equal TEST_CAPTURE_GUWID, response.authorization
    assert response.message["Could not find referenced transaction for GuWID 1234567890123456789012."]
  end

  def test_no_error_if_no_state_is_provided_in_address
    options = @options.merge(:billing_address => @address_without_state)
    @gateway.expects(:ssl_post).returns(unauthorized_capture_response)
    assert_nothing_raised do
      @gateway.authorize(@amount, @credit_card, options)
    end
  end

  def test_no_error_if_no_address_provided
    @options.delete(:billing_address)
    @gateway.expects(:ssl_post).returns(unauthorized_capture_response)
    assert_nothing_raised do
      @gateway.authorize(@amount, @credit_card, @options)
    end
  end

  def test_description_trucated_to_32_chars_in_authorize
    options = {:description => "32chars-------------------------EXTRA"}

    stub_comms do
      @gateway.authorize(@amount, @credit_card, options)
    end.check_request do |endpoint, data, headers|
      assert_match(/<FunctionID>32chars-------------------------<\/FunctionID>/, data)
    end.respond_with(successful_authorization_response)
  end

  def test_description_trucated_to_32_chars_in_purchase
    options = {:description => "32chars-------------------------EXTRA"}

    stub_comms do
      @gateway.purchase(@amount, @credit_card, options)
    end.check_request do |endpoint, data, headers|
      assert_match(/<FunctionID>32chars-------------------------<\/FunctionID>/, data)
    end.respond_with(successful_purchase_response)
  end

  def test_store_sets_recurring_transaction_type_to_initial
    stub_comms do
      @gateway.store(@credit_card)
    end.check_request do |endpoint, body, headers|
      assert_xml_element_text(body, "//RECURRING_TRANSACTION/Type", "Initial")
    end.respond_with(successful_authorization_response)
  end

  def test_store_sets_amount_to_100_by_default
    stub_comms do
      @gateway.store(@credit_card)
    end.check_request do |endpoint, body, headers|
      assert_xml_element_text(body, "//CC_TRANSACTION/Amount", "100")
    end.respond_with(successful_authorization_response)
  end

  def test_store_sets_amount_to_amount_from_options
    stub_comms do
      @gateway.store(@credit_card, :amount => 120)
    end.check_request do |endpoint, body, headers|
      assert_xml_element_text(body, "//CC_TRANSACTION/Amount", "120")
    end.respond_with(successful_authorization_response)
  end

  def test_authorization_using_reference_sets_proper_elements
    stub_comms do
      @gateway.authorize(@amount, '45678', @options)
    end.check_request do |endpoint, body, headers|
      assert_xml_element_text(body, "//GuWID", '45678')
      assert_no_match(/<CREDIT_CARD_DATA>/, body)
    end.respond_with(successful_authorization_response)
  end

  def test_purchase_using_reference_sets_proper_elements
    stub_comms do
      @gateway.purchase(@amount, '87654', @options)
    end.check_request do |endpoint, body, headers|
      assert_xml_element_text(body, "//GuWID", '87654')
      assert_no_match(/<CREDIT_CARD_DATA>/, body)
    end.respond_with(successful_authorization_response)
  end

  def test_authorization_with_recurring_transaction_type_initial
    stub_comms do
      @gateway.authorize(@amount, @credit_card, @options.merge(:recurring => "Initial"))
    end.check_request do |endpoint, body, headers|
      assert_xml_element_text(body, "//RECURRING_TRANSACTION/Type", 'Initial')
    end.respond_with(successful_authorization_response)
  end

  def test_purchase_using_reference_sets_proper_elements
    stub_comms do
      @gateway.purchase(@amount, @credit_card, @options.merge(:recurring => "Initial"))
    end.check_request do |endpoint, body, headers|
      assert_xml_element_text(body, "//RECURRING_TRANSACTION/Type", 'Initial')
    end.respond_with(successful_authorization_response)
  end

  private

  def assert_xml_element_text(xml, xpath, expected_text)
    root = REXML::Document.new(xml).root
    actual_text = root ? root.get_text(xpath).to_s : nil
    assert_equal expected_text, actual_text, %{Expected to find the text "#{expected_text}" within the XML element with path "#{xpath}", but instead found the text "#{actual_text}" in the following XML:\n#{xml}}
  end

  # Authorization success
  def successful_authorization_response
    <<-XML
    <?xml version="1.0" encoding="UTF-8"?>
    <WIRECARD_BXML xmlns:xsi="http://www.w3.org/1999/XMLSchema-instance" xsi:noNamespaceSchemaLocation="wirecard.xsd">
    <W_RESPONSE>
      <W_JOB>
        <JobID>test dummy data</JobID>
        <FNC_CC_PREAUTHORIZATION>
          <FunctionID>Wirecard remote test purchase</FunctionID>
          <CC_TRANSACTION>
            <TransactionID>1</TransactionID>
            <PROCESSING_STATUS>
              <GuWID>C822580121385121429927</GuWID>
              <AuthorizationCode>709678</AuthorizationCode>
              <Info>THIS IS A DEMO TRANSACTION USING CREDIT CARD NUMBER 420000****0000. NO REAL MONEY WILL BE TRANSFERED.</Info>
              <StatusType>INFO</StatusType>
              <FunctionResult>ACK</FunctionResult>
              <TimeStamp>2008-06-19 06:53:33</TimeStamp>
            </PROCESSING_STATUS>
          </CC_TRANSACTION>
        </FNC_CC_PREAUTHORIZATION>
      </W_JOB>
  </W_RESPONSE>
</WIRECARD_BXML>
    XML
  end

  # Authorization failure
  # TODO: replace with real xml string here (current way seems to complicated)
  def wrong_creditcard_authorization_response
    error = <<-XML
            <ERROR>
              <Type>DATA_ERROR</Type>
              <Number>24997</Number>
              <Message>Credit card number not allowed in demo mode.</Message>
              <Advice>Only demo card number '4200000000000000' is allowed for VISA in demo mode.</Advice>
            </ERROR>
            XML
    result_node = '</FunctionResult>'
    auth = 'AuthorizationCode'
    successful_authorization_response.gsub('ACK', 'NOK') \
      .gsub(result_node, result_node + error) \
      .gsub(/<#{auth}>\w+<\/#{auth}>/, "<#{auth}><\/#{auth}>") \
      .gsub(/<Info>.+<\/Info>/, '')
  end

  # Capture success
  def successful_capture_response
    <<-XML
    <?xml version="1.0" encoding="UTF-8"?>
    <WIRECARD_BXML xmlns:xsi="http://www.w3.org/1999/XMLSchema-instance" xsi:noNamespaceSchemaLocation="wirecard.xsd">
      <W_RESPONSE>
        <W_JOB>
          <JobID>test dummy data</JobID>
          <FNC_CC_CAPTURE>
            <FunctionID>Wirecard remote test purchase</FunctionID>
            <CC_TRANSACTION>
              <TransactionID>1</TransactionID>
              <PROCESSING_STATUS>
                <GuWID>C833707121385268439116</GuWID>
                <AuthorizationCode>915025</AuthorizationCode>
                <Info>THIS IS A DEMO TRANSACTION USING CREDIT CARD NUMBER 420000****0000. NO REAL MONEY WILL BE TRANSFERED.</Info>
                <StatusType>INFO</StatusType>
                <FunctionResult>ACK</FunctionResult>
                <TimeStamp>2008-06-19 07:18:04</TimeStamp>
              </PROCESSING_STATUS>
            </CC_TRANSACTION>
          </FNC_CC_CAPTURE>
        </W_JOB>
      </W_RESPONSE>
    </WIRECARD_BXML>
    XML
  end

  # Capture failure
  def unauthorized_capture_response
    <<-XML
    <?xml version="1.0" encoding="UTF-8"?>
    <WIRECARD_BXML xmlns:xsi="http://www.w3.org/1999/XMLSchema-instance" xsi:noNamespaceSchemaLocation="wirecard.xsd">
      <W_RESPONSE>
        <W_JOB>
          <JobID>test dummy data</JobID>
          <FNC_CC_CAPTURE>
            <FunctionID>Test dummy FunctionID</FunctionID>
            <CC_TRANSACTION>
              <TransactionID>a2783d471ccc98825b8c498f1a62ce8f</TransactionID>
              <PROCESSING_STATUS>
                <GuWID>C833707121385268439116</GuWID>
                <AuthorizationCode></AuthorizationCode>
                <StatusType>INFO</StatusType>
                <FunctionResult>NOK</FunctionResult>
                <ERROR>
                  <Type>DATA_ERROR</Type>
                  <Number>20080</Number>
                  <Message>Could not find referenced transaction for GuWID 1234567890123456789012.</Message>
                </ERROR>
                <TimeStamp>2008-06-19 08:09:20</TimeStamp>
              </PROCESSING_STATUS>
            </CC_TRANSACTION>
          </FNC_CC_CAPTURE>
        </W_JOB>
      </W_RESPONSE>
    </WIRECARD_BXML>
    XML
  end

  # Purchase success
  def successful_purchase_response
    <<-XML
    <?xml version="1.0" encoding="UTF-8"?>
    <WIRECARD_BXML xmlns:xsi="http://www.w3.org/1999/XMLSchema-instance" xsi:noNamespaceSchemaLocation="wirecard.xsd">
      <W_RESPONSE>
        <W_JOB>
          <JobID>test dummy data</JobID>
          <FNC_CC_PURCHASE>
            <FunctionID>Wirecard remote test purchase</FunctionID>
            <CC_TRANSACTION>
              <TransactionID>1</TransactionID>
              <PROCESSING_STATUS>
                <GuWID>C865402121385575982910</GuWID>
                <AuthorizationCode>531750</AuthorizationCode>
                <Info>THIS IS A DEMO TRANSACTION USING CREDIT CARD NUMBER 420000****0000. NO REAL MONEY WILL BE TRANSFERED.</Info>
                <StatusType>INFO</StatusType>
                <FunctionResult>ACK</FunctionResult>
                <TimeStamp>2008-06-19 08:09:19</TimeStamp>
              </PROCESSING_STATUS>
            </CC_TRANSACTION>
          </FNC_CC_PURCHASE>
        </W_JOB>
      </W_RESPONSE>
    </WIRECARD_BXML>
    XML
  end

  # Purchase failure
  def wrong_creditcard_purchase_response
    <<-XML
    <?xml version="1.0" encoding="UTF-8"?>
    <WIRECARD_BXML xmlns:xsi="http://www.w3.org/1999/XMLSchema-instance" xsi:noNamespaceSchemaLocation="wirecard.xsd">
      <W_RESPONSE>
        <W_JOB>
          <JobID>test dummy data</JobID>
          <FNC_CC_PURCHASE>
            <FunctionID>Wirecard remote test purchase</FunctionID>
            <CC_TRANSACTION>
              <TransactionID>1</TransactionID>
              <PROCESSING_STATUS>
                <GuWID>C824697121385153203112</GuWID>
                <AuthorizationCode></AuthorizationCode>
                <StatusType>INFO</StatusType>
                <FunctionResult>NOK</FunctionResult>
                <ERROR>
                  <Type>DATA_ERROR</Type>                                                    <Number>24997</Number>
                  <Message>Credit card number not allowed in demo mode.</Message>
                  <Advice>Only demo card number '4200000000000000' is allowed for VISA in demo mode.</Advice>
                </ERROR>
                <TimeStamp>2008-06-19 06:58:51</TimeStamp>
              </PROCESSING_STATUS>
            </CC_TRANSACTION>
          </FNC_CC_PURCHASE>
        </W_JOB>
      </W_RESPONSE>
    </WIRECARD_BXML>
    XML
  end
end
