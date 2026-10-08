module Ai
  class DynamicStateDecayJob < ApplicationJob
    queue_as :maintenance

    def perform
      Personality.where(dynamic_state_enabled: true).find_each do |personality|
        Dynamics::Advance.call(personality: personality)
      end
    end
  end
end
