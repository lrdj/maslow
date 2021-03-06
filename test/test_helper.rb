ENV["RAILS_ENV"] = "test"

require File.expand_path('../../config/environment', __FILE__)
require 'rails/test_help'
require 'shoulda/context'
require 'database_cleaner'
require 'mocha/setup'
require 'webmock/test_unit'
require 'gds_api/test_helpers/publishing_api_v2'

WebMock.disable_net_connect!(allow_localhost: true)

DatabaseCleaner.strategy = :truncation
DatabaseCleaner.clean

class ActiveSupport::TestCase
  include FactoryGirl::Syntax::Methods
  include WebMock::API
  include GdsApi::TestHelpers::PublishingApiV2

  teardown do
    DatabaseCleaner.clean
    WebMock.reset!
    Organisation.reset_cache
    Timecop.return
  end

  def stub_user
    @stub_user ||= create(:user)
  end

  def login_as_stub_user
    @stub_user = create(:user)
    login_as @stub_user
  end

  def login_as_stub_editor
    @stub_user = create(:editor)
    login_as @stub_user
  end

  def login_as_stub_admin
    @stub_user = create(:admin)
    login_as @stub_user
  end

  def login_as(user)
    request.env['warden'] = stub(
      authenticate!: true,
      authenticated?: true,
      user: user
    )
  end

  def blank_need_request
    {
      "role" => nil,
      "goal" => nil,
      "benefit" => nil,
      "organisation_ids" => [],
      "impact" => nil,
      "justifications" => [],
      "met_when" => [],
      "other_evidence" => nil,
      "legislation" => nil,
      "yearly_user_contacts" => nil,
      "yearly_site_views" => nil,
      "yearly_need_views" => nil,
      "yearly_searches" => nil,
      "duplicate_of" => nil,
      "status" => {
        "description" => "proposed"
      },
    }
  end
end
