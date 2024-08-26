# frozen_string_literal: true
class MassWorkGenerationPerformanceTest
  def initialize(number_of_works:)
    @number_of_works = number_of_works
    @user = User.find_by_user_key('admin@example.com')
    @date_times_array = []
    @seconds_array = []
  end

  def process
    create_collection
    create_works_in_collection
    report_performance
  end

  private

  def create_collection
    create_transaction_requirements_for_collection
    @persisted_collection = @collection_transaction.with_step_args(
      'change_set.set_user_as_depositor' => { user: @user },
      'collection_resource.apply_collection_type_permissions' => { user: @user }
    ).call(@coll_change_set).value_or {}
    apply_open_visibility(resource: @persisted_collection)
  end

  def create_works_in_collection
    @date_times_array = [DateTime.current]
    for i in 1..@number_of_works do
      create_uploaded_file(i)
      create_transaction_requirements_for_work(i)
      persisted_work = @work_tx.with_step_args(
        'work_resource.add_file_sets' => { uploaded_files: [@uploaded_file] },
        'change_set.set_user_as_depositor' => { user: @user },
        'work_resource.change_depositor' => { user: @user },
        'work_resource.save_acl' => { permissions_params: {} }
      ).call(@work_change_set).value_or {}
      @file.unlink
      apply_open_visibility(resource: persisted_work)
      report_current_time if i.multiple_of?(5)
    end
  end

  def create_transaction_requirements_for_collection
    collection_type = Hyrax::CollectionType.find_or_create_default_collection_type
    testing_collection = Collection.new(title: ["Non-Pair-Tree Testing Collection"],
                                        creator: ["A Testing User"],
                                        collection_type_gid: collection_type.to_global_id.to_s)
    @coll_change_set = Hyrax::ChangeSet.for(testing_collection)
    @collection_transaction = Hyrax::Transactions::Container['change_set.create_collection']
  end

  def create_transaction_requirements_for_work(ind)
    testing_work = GenericWork.new(title: ["Non-Pair-Tree Testing Work #{ind}"],
                                   creator: ["A Testing User"],
                                   member_of_collection_ids: [@persisted_collection.id])
    @work_change_set = Hyrax::ChangeSet.for(testing_work)
    @work_tx = Hyrax::Transactions::Container['change_set.create_work']
  end

  def create_uploaded_file(ind)
    @file = Tempfile.new("text_file_#{ind}")
    @file.write("Text for #{ind}")
    @uploaded_file = Hyrax::UploadedFile.create(file: @file, user: @user)
  end

  def apply_open_visibility(resource:)
    resource.visibility = 'open'
    persist_and_reindex(resource:)
  end

  def persist_and_reindex(resource:)
    Hyrax.persister.save(resource:)
    Hyrax.index_adapter.save(resource:)
  end

  def report_current_time
    current_time = DateTime.current
    @seconds_array += [((current_time - @date_times_array.last) * 24 * 60 * 60).to_i]
    @date_times_array += [current_time]
  end

  def report_performance
    puts "Adding works to collection started at #{@date_times_array.first}."
    puts "Adding works to collection ended at #{@date_times_array.last}."
    puts "Fastest time (in seconds) that it took to process 5 works: #{@seconds_array.min}."
    puts "Longest time (in seconds) that it took to process 5 works: #{@seconds_array.max}."
    puts "Average time (in seconds) that it took to process 5 works: #{@seconds_array.sum.to_f/@seconds_array.size.to_f}."
  end
end
