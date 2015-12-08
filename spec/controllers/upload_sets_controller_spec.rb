require 'spec_helper'

describe UploadSetsController do
  let(:user) { create(:user) }
  let(:other_user) { create(:user) }
  before do
    sign_in user
    allow_any_instance_of(User).to receive(:groups).and_return([])
  end
  describe "#update" do
    let(:upload_set_update_message) { double('upload_set update message') }
    let(:upload_set) { UploadSet.create }
    context "when successful" do
      it "enqueues a upload_set job and redirects to generic_works list with a flash message" do
        expect(UploadSetUpdateJob).to receive(:perform_later).with(user.user_key, upload_set.id, { '1' => 'foo' },
                                                                   { tag: [] }, 'open').once
        post :update, id: upload_set.id, title: { '1' => 'foo' }, visibility: 'open', work: { tag: [""] }
        expect(response).to redirect_to routes.url_helpers.curation_concerns_generic_works_path
        expect(flash[:notice]).to include("Your files are being processed")
      end
    end

    describe "when user has edit permissions on a file" do
      # TODO: all these tests could move to upload_set_update_job_spec.rb
      let!(:work) { create(:generic_work, user: user, upload_set: upload_set) }

      it "they can set public read access" do
        post :update, id: upload_set, visibility: "open", work: { tag: [""] }
        expect(work.reload.read_groups).to eq ['public']
      end

      it "they can set metadata like title" do
        post :update, id: upload_set, work: { tag: ["footag", "bartag"] }, title: { work.id => ["New Title"] }
        work.reload
        expect(work.title).to eq ["New Title"]
        # TODO: is order important?
        expect(work.tag).to include("footag", "bartag")
      end

      it "they cannot set any tags" do
        post :update, id: upload_set, work: { tag: [""] }
        expect(work.reload.tag).to be_empty
      end
    end

    describe "when user does not have edit permissions on a file" do
      # TODO: all these tests could move to upload_set_update_job_spec.rb
      let!(:work) { create(:generic_work, title: ['Original Title'], upload_set: upload_set) }

      it "they cannot modify the object" do
        post :update, id: upload_set, "work" => { "tag" => [""] },
                      "title" => { work.id => "Title Won't Change" }
        work.reload
        expect(work.title).to eq ["Original Title"]
      end
    end
  end

  describe "#edit" do
    let(:us1) { UploadSet.create }
    let!(:work) { create(:generic_work, upload_set: us1, title: ['f1'], user: user) }
    let!(:work2) { create(:generic_work, upload_set: us1, title: ['f2'], user: user) }

    it "sets up attributes for the form" do
      get :edit, id: us1
      expect(assigns[:form]).not_to be_persisted
      expect(assigns[:form].creator[0]).to eq user.user_key
      expect(assigns[:form].title[0]).to eq 'f1'
    end
  end
end
