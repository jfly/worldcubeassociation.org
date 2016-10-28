# frozen_string_literal: true
module Admin
  class CheckResultsController < AdminController
    def index
      check_params = params[:check_results] ? params.require(:check_results).permit(:competition_id, :event_id, :what) : {}
      @check_results = CheckResults.new(check_params)
      if params[:commit]
        @warnings = @check_results.warnings
      end
    end
  end
end
