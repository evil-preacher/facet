module Admin
  class UsersController < ApplicationController
    def show
      @budget = Ai::SpendingBudget.snapshot(user: requested_resource)
      super
    end
  end
end
