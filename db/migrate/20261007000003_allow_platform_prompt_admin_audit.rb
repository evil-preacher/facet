class AllowPlatformPromptAdminAudit < ActiveRecord::Migration[8.1]
  def change
    remove_check_constraint :admin_audit_events, name: "admin_audit_events_action"
    add_check_constraint :admin_audit_events,
                         "action IN ('index', 'show', 'disable_initiative', 'retry_pending', 'publish_prompt', 'publish_platform_prompt')",
                         name: "admin_audit_events_action"
  end
end
