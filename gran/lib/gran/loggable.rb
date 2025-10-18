module Gran
  module Loggable
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      def logger
        @logger ||= Gran.logger
      end

      def logger=(logger)
        @logger = logger
      end
    end

    def logger
      @logger ||= self.class.logger
    end

    def logger=(logger)
      @logger = logger
    end
  end
end
