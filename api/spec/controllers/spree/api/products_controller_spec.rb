require 'spec_helper'
require 'shared_examples/protect_product_actions'

module Spree
  describe Spree::Api::ProductsController do
    render_views

    let!(:product) { create(:product) }
    let!(:inactive_product) { create(:product, :available_on => Time.now.tomorrow, :name => "inactive") }
    let(:attributes) { [:id, :name, :description, :price, :available_on, :permalink, :count_on_hand, :meta_description, :meta_keywords, :taxon_ids] }
    let(:product_hash) do
      { :name => "The Other Product",
        :price => 19.99 }
    end
    let(:attributes_for_variant) do
      h = attributes_for(:variant).except(:is_master, :product)
      h.delete(:option_values)
      h.merge({
        options: [
          { name: "size", value: "small" },
          { name: "color", value: "black" }
        ]
      })
    end

    before do
      stub_authentication!
    end

    context "as a normal user" do
      it "retrieves a list of products" do
        api_get :index
        json_response["products"].first.should have_attributes(attributes)
        json_response["count"].should == 1
        json_response["current_page"].should == 1
        json_response["pages"].should == 1
      end

      it "does not list unavailable products" do
        api_get :index
        json_response["products"].first["name"].should_not eq("inactive")
      end

      context "pagination" do

        it "can select the next page of products" do
          second_product = create(:product)
          api_get :index, :page => 2, :per_page => 1
          json_response["products"].first.should have_attributes(attributes)
          json_response["total_count"].should == 2
          json_response["current_page"].should == 2
          json_response["pages"].should == 2
        end

        it 'can control the page size through a parameter' do
          create(:product)
          api_get :index, :per_page => 1
          json_response['count'].should == 1
          json_response['total_count'].should == 2
          json_response['current_page'].should == 1
          json_response['pages'].should == 2
        end
      end

      context "jsonp" do
        it "retrieves a list of products of jsonp" do
          api_get :index, {:callback => 'callback'}
          response.body.should =~ /^callback\(.*\)$/
          response.header['Content-Type'].should include('application/javascript')
        end
      end

      it "can search for products" do
        create(:product, :name => "The best product in the world")
        api_get :index, :q => { :name_cont => "best" }
        json_response["products"].first.should have_attributes(attributes)
        json_response["count"].should == 1
      end

      it "gets a single product" do
        product.master.images.create!(:attachment => image("thinking-cat.jpg"))
        product.variants.create!
        product.variants.first.images.create!(:attachment => image("thinking-cat.jpg"))
        product.set_property("spree", "rocks")
        api_get :show, :id => product.to_param
        json_response.should have_attributes(attributes)
        json_response['variants'].first.should have_attributes([:name,
                                                              :is_master,
                                                              :count_on_hand,
                                                              :price,
                                                              :images])

        json_response['variants'].first['images'].first.should have_attributes([:attachment_file_name,
                                                                                :attachment_width,
                                                                                :attachment_height,
                                                                                :attachment_content_type,
                                                                                :attachment_url])

        json_response["product_properties"].first.should have_attributes([:value,
                                                                         :product_id,
                                                                         :property_name])
      end


      context "finds a product by permalink first then by id" do
        let!(:other_product) { create(:product, :permalink => "these-are-not-the-droids-you-are-looking-for") }

        before do
          product.update_attribute(:permalink, "#{other_product.id}-and-1-ways")
        end

        specify do
          api_get :show, :id => product.to_param
          json_response["permalink"].should =~ /and-1-ways/
          product.destroy

          api_get :show, :id => other_product.id
          json_response["permalink"].should =~ /droids/
        end
      end

      it "cannot see inactive products" do
        api_get :show, :id => inactive_product.to_param
        json_response["error"].should == "The resource you were looking for could not be found."
        response.status.should == 404
      end

      it "returns a 404 error when it cannot find a product" do
        api_get :show, :id => "non-existant"
        json_response["error"].should == "The resource you were looking for could not be found."
        response.status.should == 404
      end

      it "can learn how to create a new product" do
        api_get :new
        json_response["attributes"].should == attributes.map(&:to_s)
        required_attributes = json_response["required_attributes"]
        required_attributes.should include("name")
        required_attributes.should include("price")
      end

      it_behaves_like "modifying product actions are restricted"
    end

    context "as an admin" do
      sign_in_as_admin!

      it "can see all products" do
        api_get :index
        json_response["products"].count.should == 2
        json_response["count"].should == 2
        json_response["current_page"].should == 1
        json_response["pages"].should == 1
      end

      # Regression test for #1626
      context "deleted products" do
        before do
          create(:product, :deleted_at => 1.day.ago)
        end

        it "does not include deleted products" do
          api_get :index
          json_response["products"].count.should == 2
        end

        it "can include deleted products" do
          api_get :index, :show_deleted => 1
          json_response["products"].count.should == 3
        end
      end

      it "can create a new product" do
        api_post :create, :product => product_hash
        json_response.should have_attributes(attributes)
        response.status.should == 201
      end

      describe "creating products with" do
        it "embedded variants" do
          attributes = product_hash

          attributes.merge!({
            shipping_category_id: 1,

            option_types: ['size', 'color'],

            variants_attributes: [
              attributes_for_variant,
              attributes_for_variant
            ]
          })

          api_post :create, :product => attributes

          expect(json_response['variants'].count).to eq(3) # 1 master + 2 variants
          expect(json_response['variants'][1]['option_values'][0]['name']).to eq('small')
          expect(json_response['variants'][1]['option_values'][0]['option_type_name']).to eq('size')

          expect(json_response['option_types'].count).to eq(2) # size, color
        end

        it "embedded product_properties" do
          attributes = product_hash

          attributes.merge!({
            shipping_category_id: 1,

            product_properties_attributes: [{
              property_name: "fabric",
              value: "cotton"
            }]
          })

          api_post :create, :product => attributes

          expect(json_response['product_properties'][0]['property_name']).to eq('fabric')
          expect(json_response['product_properties'][0]['value']).to eq('cotton')
        end

        it "option_types even if without variants" do
          attributes = product_hash

          attributes.merge!({
            shipping_category_id: 1,

            option_types: ['size', 'color']
          })

          api_post :create, :product => attributes

          expect(json_response['option_types'].count).to eq(2)
        end
      end

      # Regression test for #2140
      context "with authentication_required set to false" do
        before do
          Spree::Api::Config.requires_authentication = false
        end

        after do
          Spree::Api::Config.requires_authentication = true
        end

        it "can still create a product" do
          api_post :create, :product => { :name => "The Other Product",
                                          :price => 19.99 },
                            :token => "fake"
          json_response.should have_attributes(attributes)
          response.status.should == 201
        end
      end

      it "cannot create a new product with invalid attributes" do
        api_post :create, :product => {}
        response.status.should == 422
        json_response["error"].should == "Invalid resource. Please fix errors and try again."
        errors = json_response["errors"]
        errors.delete("permalink") # Don't care about this one.
        errors.keys.should =~ ["name", "price"]
      end

      it "can update a product" do
        api_put :update, :id => product.to_param, :product => { :name => "New and Improved Product!" }
        response.status.should == 200
      end

      it "cannot update a product with an invalid attribute" do
        api_put :update, :id => product.to_param, :product => { :name => "" }
        response.status.should == 422
        json_response["error"].should == "Invalid resource. Please fix errors and try again."
        json_response["errors"]["name"].should == ["can't be blank"]
      end

      it "can delete a product" do
        product.deleted_at.should be_nil
        api_delete :destroy, :id => product.to_param
        response.status.should == 204
        product.reload.deleted_at.should_not be_nil
      end

      context "updating products with" do
        it "embedded option types" do
          api_put :update, :id => product.to_param, :product => { :option_types => ['shape', 'color'] }
          json_response['option_types'].count.should eq(2)
        end

        it "embedded new variants" do
          api_put :update, :id => product.to_param, :product => { :variants_attributes => [attributes_for_variant, attributes_for_variant] }
          response.status.should == 200
          json_response['variants'].count.should == 3 # 1 master + 2 variants

          variants = json_response['variants'].select { |v| !v['is_master'] }
          variants.last['option_values'][0]['name'].should == 'small'
          variants.last['option_values'][0]['option_type_name'].should == 'size'

          json_response['option_types'].count.should == 2 # size, color
        end

        it "embedded existing variant" do
          variant_hash = {
            :sku => '123', :price => 19.99, :options => [{:name => "size", :value => "small"}]
          }
          variant = product.variants.new
          variant.update_attributes(variant_hash)

          api_put :update, :id => product.to_param, :product => { :variants_attributes => [variant_hash.merge(:id => variant.id.to_s, :sku => '456', :options => [{:name => "size", :value => "large" }])] }

          json_response['variants'].count.should == 2 # 1 master + 2 variants
          variants = json_response['variants'].select { |v| !v['is_master'] }
          variants.last['option_values'][0]['name'].should == 'large'
          variants.last['sku'].should == '456'
          variants.count.should == 1
        end
      end
    end
  end
end
