module Spree
  module Promo
    class Engine < Rails::Engine
      isolate_namespace Spree
      engine_name 'spree_promo'

      def self.activate
        Dir.glob(File.join(File.dirname(__FILE__), '../../../app/**/*_decorator*.rb')) do |c|
          Rails.configuration.cache_classes ? require(c) : load(c)
        end

        Spree::StoreController.class_eval do
          # Include list of visited paths in notification payload hash
          def default_notification_payload
            { :user => try_spree_current_user, :order => current_order, :visited_paths => session[:visited_paths] }
          end
        end
      end

      config.autoload_paths += %W(#{config.root}/lib)
      config.to_prepare &method(:activate).to_proc

      # We need to define promotions rules here so extensions and existing apps
      # can add their custom classes on their initializer files
      initializer 'spree.promo.environment', :after => 'spree.environment' do |app|
        app.config.spree.add_class('promotions')
        app.config.spree.promotions = Spree::Promo::Environment.new
        app.config.spree.promotions.rules = []
      end

      initializer 'spree.promo.register.promotion.calculators' do |app|
        app.config.spree.calculators.add_class('promotion_actions_create_adjustments')
        app.config.spree.calculators.promotion_actions_create_adjustments = [
          Spree::Calculator::FlatPercentItemTotal,
          Spree::Calculator::FlatRate,
          Spree::Calculator::FlexiRate,
          Spree::Calculator::PerItem,
          Spree::Calculator::PercentPerItem,
          Spree::Calculator::FreeShipping
        ]
      end

      # Promotion rules need to be evaluated on after initialize otherwise
      # Spree.user_class would be nil and users might experience errors related
      # to malformed model associations (Spree.user_class is only defined on
      # the app initializer)
      config.after_initialize do
        Rails.application.config.spree.promotions.rules.concat [
          Spree::Promotion::Rules::ItemTotal,
          Spree::Promotion::Rules::Product,
          Spree::Promotion::Rules::User,
          Spree::Promotion::Rules::FirstOrder,
          Spree::Promotion::Rules::UserLoggedIn]
      end

      initializer 'spree.promo.register.promotions.actions' do |app|
        app.config.spree.promotions.actions = [Spree::Promotion::Actions::CreateAdjustment,
          Spree::Promotion::Actions::CreateLineItems]
      end

    end
  end
end
