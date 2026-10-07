module Accounts
  class Destroy
    def self.call(user:)
      User.transaction do
        user.lock!
        user.personalities.find_each { |personality| Personalities::Destroy.call(user: user, personality: personality) }
        ModelCall.where(user_id: user.id).delete_all
        AdminAuditEvent.where(actor_user_id: user.id).delete_all
        AdminAuditEvent.where(target_type: "User", target_id: user.id).delete_all
        user.login_challenges.delete_all
        user.profile&.delete
        user.delete
      end
    end
  end
end
