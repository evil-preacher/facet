class AddResponseModelToModelCalls < ActiveRecord::Migration[8.1]
  def change
    add_column :model_calls, :response_model, :string
  end
end
