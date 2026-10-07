module Admin
  class PersonalitiesController < ApplicationController
    def disable_initiative
      personality = Personality.find(params[:id])
      Personality.transaction do
        Personalities::DisableInitiative.call(personality: personality)
        AdminAuditEvent.create!(actor_user_id: current_admin.id, action: "disable_initiative",
                                target_type: "Personality", target_id: personality.id)
      end
      redirect_to admin_personality_path(personality), notice: t("admin.flash.initiative_disabled"), status: :see_other
    end
  end
end
