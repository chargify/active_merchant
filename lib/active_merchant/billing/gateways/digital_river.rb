require 'digital_river'

module ActiveMerchant
  module Billing
    class DigitalRiverGateway < Gateway
      def initialize(options = {})
        requires!(options, :token)
        super

        token = options[:token]
        @digital_river_gateway = DigitalRiver::Gateway.new(token)
      end

      def store(payment_method, options = {})
        MultiResponse.new.tap do |r|
          if options[:customer_vault_token]
            r.process do
              check_customer_exists(options[:customer_vault_token])
            end
            return r unless r.responses.last.success?
            r.process do
              add_source_to_customer(payment_method, options[:customer_vault_token])
            end
          else
            r.process do
              create_customer(options)
            end
            return r unless r.responses.last.success?
            r.process do
              add_source_to_customer(payment_method, r.responses.last.authorization)
            end
          end
        end
      end

      def purchase(options)
        MultiResponse.new.tap do |r|
          order_exists = nil
          r.process do
            order_exists = @digital_river_gateway.order.find(options[:order_id])

            return ActiveMerchant::Billing::Response.new(
              order_exists.success?,
              message_from_result(order_exists)
            ) unless order_exists.success?
          end

          if order_exists.value!.state == 'accepted'
            r.process do
              create_fulfillment(options[:order_id], items_from_order(order_exists.value!.items))
            end
            return r unless r.responses.last.success?
            r.process do
              get_charge_capture_id(options[:order_id])
            end
          else
            return ActiveMerchant::Billing::Response.new(
              false,
              "Order not in 'accepted' state",
              {
                order_id: order_exists.value!.id,
                order_state: order_exists.value!.state
              },
              authorization: order_exists.value!.id
            )
          end
        end
      end

      private

      def create_fulfillment(order_id, items)
        fulfillment_params = { order_id: order_id, items: items }
        result = @digital_river_gateway.fulfillment.create(fulfillment_params)
        ActiveMerchant::Billing::Response.new(
          result.success?,
          message_from_result(result),
          fulfillment_params(result)
        )
      end

      def get_charge_capture_id(order_id)
        # we know that the order exists here from previous action
        # so this will always be a success response
        charge = @digital_river_gateway.order.find(order_id).value!.charges.first
        # for now we assume only one charge will be processed at one order

        capture = @digital_river_gateway.charge.find(charge.id).value!.captures.first
        ActiveMerchant::Billing::Response.new(
          true,
          "OK",
          {
            order_id: order_id,
            charge_id: charge.id,
            capture_id: capture.id,
            source_id: charge.source_id
          },
          authorization: capture.id
        )
      end

      def add_source_to_customer(payment_method, customer_id)
        result = @digital_river_gateway
                   .customer
                   .attach_source(
                     customer_id,
                     payment_method
                   )
        ActiveMerchant::Billing::Response.new(
          result.success?,
          message_from_result(result),
          {
            customer_vault_token: (result.value!.customer_id if result.success?),
            payment_profile_token: (result.value!.id if result.success?)
          },
          authorization: (result.value!.customer_id if result.success?)
        )
      end

      def create_customer(options)
        params =
        {
          "email": options[:email],
          "shipping": {
            "name": options[:billing_address][:name],
            "organization": options[:organization],
            "phone": options[:phone],
            "address": {
              "line1": options[:billing_address][:address1],
              "line2": options[:billing_address][:address2],
              "city": options[:billing_address][:city],
              "state": options[:billing_address][:state],
              "postalCode": options[:billing_address][:zip],
              "country": options[:billing_address][:country],
            }
          }
        }
        result = @digital_river_gateway.customer.create(params)
        ActiveMerchant::Billing::Response.new(
          result.success?,
          message_from_result(result),
          {
            customer_vault_token: (result.value!.id if result.success?)
          },
          authorization: (result.value!.id if result.success?)
        )
      end

      def check_customer_exists(customer_vault_id)
        if @digital_river_gateway.customer.find(customer_vault_id).success?
          ActiveMerchant::Billing::Response.new(true, "Customer found", {exists: true}, authorization: customer_vault_id)
        else
          ActiveMerchant::Billing::Response.new(false, "Customer '#{customer_vault_id}' not found", {exists: false})
        end
      end

      def headers(options)
        {
          "Authorization" => "Bearer #{options[:token]}",
          "Content-Type" => "application/json",
        }
      end

      def message_from_result(result)
        if result.success?
          "OK"
        elsif result.failure?
          result.failure[:errors].map { |e| "#{e[:message]} (#{e[:code]})" }.join(" ")
        end
      end

      def fulfillment_params(result)
        { fulfillment_id: result.value!.id } if result.success?
      end

      def items_from_order(items)
        items.map { |item| { itemId: item.id, quantity: item.quantity.to_i, skuId: item.sku_id } }
      end
    end
  end
end