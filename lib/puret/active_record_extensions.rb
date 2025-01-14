module Puret
  module ActiveRecordExtensions
    module ClassMethods
      # Configure translation model dependency.
      # Eg:
      #   class PostTranslation < ActiveRecord::Base
      #     puret_for :post
      #   end
      def puret_for(model)
        belongs_to model
        validates_presence_of model, :locale
        validates_uniqueness_of :locale, :scope => "#{model}_id"
      end

      # Configure translated attributes.
      # Eg:
      #   class Post < ActiveRecord::Base
      #     puret :title, :description
      #   end
      def puret(*attributes)
        make_it_puret! unless included_modules.include?(InstanceMethods)

        attributes.each do |attribute|
          # attribute setter
          define_method "#{attribute}=" do |value|
            puret_attributes[I18n.locale][attribute] = value
          end

          # attribute getter
          define_method attribute do
            # return previously setted attributes if present
            return puret_attributes[I18n.locale][attribute] if puret_attributes[I18n.locale][attribute]
            return if new_record?

            # Lookup chain:
            # if translation not present in current locale,
            # use default locale, if present.
            # Otherwise use first translation
            translation = translations.detect { |t| t.locale.to_sym == I18n.locale && t[attribute] } ||
              translations.detect { |t| t.locale.to_sym == puret_default_locale && t[attribute] } ||
              translations.first

            translation ? translation[attribute] : nil
          end

          define_method "#{attribute}_before_type_cast" do
            self.send(attribute)
          end

          #per locale attribute getter and setter
          I18n.available_locales.each do |locale|

            # setter
            define_method "#{locale.to_s}_#{attribute}=" do |value|
              puret_attributes[locale][attribute] = value
            end

            # getter
            define_method "#{locale.to_s}_#{attribute}" do
              # return previously setted attributes if present
              return puret_attributes[I18n.locale][attribute] if puret_attributes[I18n.locale][attribute]
              return if new_record?

              # else lookup only in givel locale
              translation = translations.detect { |t| t.locale.to_sym == locale && t[attribute] }
              translation ? translation[attribute] : nil
            end
          end

        end

        # mass atribute getter
        define_method :all_puret_attributes do
          t_hash = Hash[translations.map { |t| [t.locale.to_sym, t] }]

          Hash[I18n.available_locales.map do |l|
            [l, Hash[attributes.map { |a| [a, t_hash[l].try(a)] }]]
          end]
        end
      end

      private

      # configure model
      def make_it_puret!
        include InstanceMethods

        has_many :translations, :class_name => "#{self.to_s}Translation", :dependent => :destroy, :order => "created_at DESC"
        after_save :update_translations!
      end
    end

    module InstanceMethods
      attr_writer :puret_attributes

      def puret_default_locale
        return default_locale.to_sym if respond_to?(:default_locale)
        return self.class.default_locale.to_sym if self.class.respond_to?(:default_locale)
        I18n.default_locale
      end

      # attributes are stored in @puret_attributes instance variable via setter
      def puret_attributes
        @puret_attributes ||= Hash.new { |hash, key| hash[key] = {} }
      end

      # called after save
      def update_translations!
        return if puret_attributes.blank?
        puret_attributes.each do |locale, attributes|
          translation = translations.find_or_initialize_by_locale(locale.to_s)
          translation.attributes = translation.attributes.merge(attributes)
          translation.save!
        end
      end
    end
  end
end

ActiveRecord::Base.extend Puret::ActiveRecordExtensions::ClassMethods
