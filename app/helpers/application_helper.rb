module ApplicationHelper
  def gender_options
    Profile::GENDERS.map { |gender| [ t("app.genders.#{gender}"), gender ] }
  end
end
