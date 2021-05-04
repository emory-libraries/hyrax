# frozen_string_literal: true

RSpec.describe Hyrax::PcdmMemberPresenterFactory, index_adapter: :solr_index, valkyrie_adapter: :test_adapter do
  subject(:factory) { described_class.new(solr_doc, ability) }
  let(:ability)     { :FAKE_ABILITY }
  let(:ids)         { [] }
  let(:solr_doc)    { SolrDocument.new(member_ids_ssim: ids) }

  RSpec::Matchers.define :be_presenter_for do |expected|
    match do |actual|
      (actual.solr_document['has_model_ssim'].first == expected.model_name.name) &&
        actual.id == expected.id
    end
  end

  shared_context 'with members' do
    let(:ids) { works.map(&:id) + file_sets.map(&:id) }

    let(:file_sets) do
      [FactoryBot.valkyrie_create(:hyrax_file_set),
       FactoryBot.valkyrie_create(:hyrax_file_set)]
    end

    let(:works) do
      [FactoryBot.valkyrie_create(:monograph),
       FactoryBot.valkyrie_create(:monograph)]
    end

    before do
      file_sets.each { |fs| Hyrax.index_adapter.save(resource: fs) }
      works.each     { |work| Hyrax.index_adapter.save(resource: work) }
    end
  end

  describe '#file_set_presenters' do
    it 'is empty' do
      expect(factory.file_set_presenters.to_a).to be_empty
    end

    context 'with members' do
      include_context 'with members'

      it 'builds only file_set presenters' do
        expect(factory.file_set_presenters)
          .to contain_exactly(*file_sets.map { |fs| be_presenter_for(fs) })
      end
    end
  end

  describe '#member_presenters' do
    it 'is empty' do
      expect(factory.member_presenters.to_a).to be_empty
    end

    context 'with members' do
      include_context 'with members'

      it 'builds all member presenters' do
        members = file_sets + works

        expect(factory.member_presenters)
          .to contain_exactly(*members.map { |fs| be_presenter_for(fs) })
      end

      it 'builds member presenters with appropriate classes' do
        expect(factory.member_presenters)
          .to contain_exactly(an_instance_of(Hyrax::WorkShowPresenter),
                              an_instance_of(Hyrax::WorkShowPresenter),
                              an_instance_of(Hyrax::FileSetPresenter),
                              an_instance_of(Hyrax::FileSetPresenter))
      end
    end
  end

  describe '#work_presenters' do
    it 'is empty' do
      expect(factory.work_presenters.to_a).to be_empty
    end

    context 'with members' do
      include_context 'with members'

      it 'builds only work presenters' do
        expect(factory.work_presenters)
          .to contain_exactly(*works.map { |fs| be_presenter_for(fs) })
      end
    end
  end
end
