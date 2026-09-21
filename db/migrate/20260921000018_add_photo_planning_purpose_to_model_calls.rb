class AddPhotoPlanningPurposeToModelCalls < ActiveRecord::Migration[8.1]
  def change
    remove_check_constraint :model_calls, name: "model_calls_purpose"
    add_check_constraint :model_calls,
                         "purpose IN ('conversation', 'memory_extraction', " \
                           "'memory_consolidation', 'thread_summary', 'initiative', " \
                           "'photo_planning')",
                         name: "model_calls_purpose"
  end
end
