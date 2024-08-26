# frozen_string_literal: true
namespace :sirenia do
  task "tests_mass_work_fileset_creation_performance", [:number_of_works] => :environment do |_cmd, args|
    require 'mass_work_generation_performance_test'
    number_of_works = args[:number_of_works]&.to_i

    if number_of_works.zero?
      warn "Please specify a number of works to be generated by the rake task (preferably a multiple of 5)."
    else
      MassWorkGenerationPerformanceTest.new(number_of_works:).process
    end
  end
end
