require_relative '../test_helper'
require 'gds_api/test_helpers/need_api'
require 'gds_api/test_helpers/publishing_api_v2'


class NeedTest < ActiveSupport::TestCase
  include GdsApi::TestHelpers::NeedApi
  include GdsApi::TestHelpers::PublishingApiV2

  context "saving need data to the Need API" do
    setup do
      @atts = {
        "role" => "user",
        "goal" => "do stuff",
        "benefit" => "get stuff",
        "organisation_ids" => ["ministry-of-justice"],
        "impact" => "Endangers people",
        "justifications" => ["It's something only government does", "The government is legally obliged to provide it"],
        "met_when" => ["Winning", "Winning More"],
        "other_evidence" => "Ministerial priority",
        "legislation" => "Vehicle Excise and Registration Act 1994, schedule 4",
        "yearly_user_contacts" => 500,
        "yearly_site_views" => 70000,
        "yearly_need_views" => 15000,
        "yearly_searches" => 2000
      }
    end

    context "given valid attributes" do
      should "make a request to the need API with an author" do
        need = Need.new(@atts)
        author = User.new(name: "O'Brien", email: "obrien@alphagov.co.uk", uid: "user-1234")

        request = @atts.merge(
          "duplicate_of" => nil,
          "status" => nil,
          "author" => {
            "name" => "O'Brien",
            "email" => "obrien@alphagov.co.uk",
            "uid" => "user-1234"
          })
        response = @atts.merge(
          "_response_info" => {
            "status" => "created"
          },
          "id" => "123456"
        )

        GdsApi::NeedApi.any_instance.expects(:create_need).with(request).returns(response)

        assert need.save_as(author)
        assert need.persisted?
        assert_equal "123456", need.need_id
      end

      should "set the 'met_when', 'justifications' and 'organisation_ids' fields to be empty arrays if not present" do
        assert_equal [], Need.new({}).met_when
        assert_equal [], Need.new({ "met_when" => nil }).met_when

        assert_equal [], Need.new({}).justifications
        assert_equal [], Need.new({ "justifications" => nil }).justifications

        assert_equal [], Need.new({}).organisation_ids
        assert_equal [], Need.new({ "organisation_ids" => nil }).organisation_ids
      end

      should "be able to add blank criteria" do
        need = Need.new({})

        need.add_more_criteria
        assert_equal [""], need.met_when

        need.add_more_criteria
        assert_equal ["", ""], need.met_when
      end

      should "be able to delete criteria" do
        need = Need.new({ "met_when" => %w(0 1 2) })

        need.remove_criteria(0)
        assert_equal %w(1 2), need.met_when

        need.remove_criteria(1)
        assert_equal ["1"], need.met_when

        need.remove_criteria(0)
        assert_equal [], need.met_when
      end

      context "preparing a need as json" do
        should "present attributes as json" do
          json = Need.new(@atts).as_json

          # include protected fields in the list of keys to expect
          expected_keys = (@atts.keys + %w(duplicate_of status)).sort

          assert_equal expected_keys, json.keys.sort
          assert_equal "user", json["role"]
          assert_equal "do stuff", json["goal"]
          assert_equal "get stuff", json["benefit"]
          assert_equal ["ministry-of-justice"], json["organisation_ids"]
          assert_equal "Endangers people", json["impact"]
          assert_equal ["It's something only government does", "The government is legally obliged to provide it"], json["justifications"]
          assert_equal ["Winning", "Winning More"], json["met_when"]
        end

        should "remove empty values from met_when when converted to json" do
          @atts.merge!({ "met_when" => ["", "Winning", ""] })
          json = Need.new(@atts).as_json

          assert_equal ["Winning"], json["met_when"]
        end

        should "clear met_when if no values set when converted to json" do
          @atts.merge!({ "met_when" => ["", "", ""] })
          json = Need.new(@atts).as_json

          assert json.has_key?("met_when")
          assert_equal [], json["met_when"]
        end

        should "ignore the errors attribute" do
          need = Need.new(@atts)
          need.valid? # invoking this sets the errors attribute

          json = need.as_json

          assert json.has_key?("role")
          refute json.has_key?("errors")
        end

        should "strip leading newlines from textarea fields" do
          need = Need.new("legislation" => "\nNew Line Act 2013", "other_evidence" => "\nNew line characters everywhere")

          assert_equal "New Line Act 2013", need.as_json["legislation"]
          assert_equal "New line characters everywhere", need.as_json["other_evidence"]
        end

        should "return nil values in the hash" do
          need = Need.new("role" => nil, "goal" => nil, "benefit" => nil)

          assert need.as_json.has_key?("role")
          assert need.as_json.has_key?("goal")
          assert need.as_json.has_key?("benefit")
        end

        should "return empty strings as nil in the hash" do
          need = Need.new("role" => "", "goal" => "", "benefit" => "")

          assert_equal nil, need.as_json["role"]
          assert_equal nil, need.as_json["goal"]
          assert_equal nil, need.as_json["benefit"]
        end
      end
    end

    should "raise an exception when non-whitelisted fields are present" do
      assert_raises(ArgumentError) do
        Need.new(@atts.merge("foo" => "bar", "bar" => "baz"))
      end
    end

    should "raise an exception when protected fields are present" do
      assert_raises ArgumentError do
        Need.new(@atts.merge("duplicate_of" => "foo"))
      end
    end

    should "be invalid when role is blank" do
      need = Need.new(@atts.merge("role" => ""))

      refute need.valid?
      assert need.errors.has_key?(:role)
    end

    should "be invalid when goal is blank" do
      need = Need.new(@atts.merge("goal" => ""))

      refute need.valid?
      assert need.errors.has_key?(:goal)
    end

    should "be invalid when benefit is blank" do
      need = Need.new(@atts.merge("benefit" => ""))

      refute need.valid?
      assert need.errors.has_key?(:benefit)
    end

    should "be invalid when justifications are not in the list" do
      need = Need.new(@atts.merge("justifications" => ["something else"]))

      refute need.valid?
      assert need.errors.has_key?(:justifications)
    end

    should "be invalid when impact is not in the list" do
      need = Need.new(@atts.merge("impact" => "something else"))

      refute need.valid?
      assert need.errors.has_key?(:impact)
    end

    should "be invalid with a non-numeric value for yearly_user_contacts" do
      need = Need.new(@atts.merge("yearly_user_contacts" => "foo"))

      refute need.valid?
      assert need.errors.has_key?(:yearly_user_contacts)
    end

    should "be invalid with a non-numeric value for yearly_site_views" do
      need = Need.new(@atts.merge("yearly_site_views" => "foo"))

      refute need.valid?
      assert need.errors.has_key?(:yearly_site_views)
    end

    should "be invalid with a non-numeric value for yearly_need_views" do
      need = Need.new(@atts.merge("yearly_need_views" => "foo"))

      refute need.valid?
      assert need.errors.has_key?(:yearly_need_views)
    end

    should "be invalid with a non-numeric value for yearly_searches" do
      need = Need.new(@atts.merge("yearly_searches" => "foo"))

      refute need.valid?
      assert need.errors.has_key?(:yearly_searches)
    end

    should "be valid with a blank value for yearly_user_contacts" do
      need = Need.new(@atts.merge("yearly_user_contacts" => ""))

      assert need.valid?
    end

    should "be valid with a blank value for yearly_site_views" do
      need = Need.new(@atts.merge("yearly_site_views" => ""))

      assert need.valid?
    end

    should "be valid with a blank value for yearly_need_views" do
      need = Need.new(@atts.merge("yearly_need_views" => ""))

      assert need.valid?
    end

    should "be valid with a blank value for yearly_searches" do
      need = Need.new(@atts.merge("yearly_searches" => ""))

      assert need.valid?
    end

    should "report a problem if unable to save the need" do
      need = Need.new(@atts)
      GdsApi::NeedApi.any_instance.expects(:create_need).raises(
        GdsApi::HTTPErrorResponse.new(422, ["error"])
      )

      assert_equal false, need.save_as(stub_user)
    end

    should "report new needs as not persisted" do
      refute Need.new({}).persisted?
    end
  end

  def stub_need_response
    {
      "results" => [{ "id" => 100001 }],
      "pages" => 2,
      "total" => 60,
      "page_size" => 50,
      "current_page" => 1,
      "start_index" => 1,
    }
  end

  def stub_publishing_api_response
    {
      "total"=>3,
      "pages"=>1,
      "current_page"=>1, "links"=>[
        {
          "href"=>"http://publishing-api.dev.gov.uk/v2/content?document_type=need&fields%5B%5D=need_ids&fields%5B%5D=content_id&fields%5B%5D=details&locale=en&order=-public_updated_at&per_page=50&publishing_app=need-api&page=2",
          "rel"=>"next"
        },
        {
          "href"=>"http://publishing-api.dev.gov.uk/v2/content?document_type=need&fields%5B%5D=need_ids&fields%5B%5D=content_id&fields%5B%5D=details&locale=en&order=-public_updated_at&per_page=50&publishing_app=need-api&page=1", "rel"=>"self"
        }
      ],
      "results"=>[
        {
          "need_ids"=>["100523"],
          "content_id"=>"0001c0c6-2dd3-4b56-87f1-815efe32c155",
          "details"=>{
            "applies_to_all_organisations"=>false,
            "benefit"=>"I can make sure I'm getting what I'm entitled to",
            "goal"=>"know what my rights are after a crime",
            "role"=>"citizen"
          }
        },
        {
          "need_ids"=>["100522"],
          "content_id"=>"c867e5f7-2d68-42ad-bedb-20638b3bf58e",
          "details"=>{
            "applies_to_all_organisations"=>false,
            "benefit"=>"I can improve their services or stop them from operating",
            "goal"=>"complain about a legal adviser",
            "role"=>"citizen"
          }
        },
        {
          "need_ids"=>["100521"],
          "content_id"=>"0925fd2b-6b59-4120-a849-96ab19b9c7df",
          "details"=>{
            "applies_to_all_organisations"=>false,
            "role"=>"citizen",
            "goal"=>"take my tax appeal to a tribunal",
            "benefit"=>"I can have my case heard again and get the decision reversed"
          }
        }
      ]
    }
  end

  def need_attributes_1
    {
      "content_id"=>"0001c0c6-2dd3-4b56-87f1-815efe32c155",
      "need_id" => 100523,
      "details"=>{
        "benefit"=>"I can make sure I'm getting what I'm entitled to",
        "goal"=>"know what my rights are after a crime",
        "role"=>"citizen"
      }
    }
  end

  def need_attributes_2
    {
      "content_id"=>"c867e5f7-2d68-42ad-bedb-20638b3bf58e",
      "need_id" => 100522,
      "details"=>{
        "benefit"=>"I can improve their services or stop them from operating",
        "goal"=>"complain about a legal adviser",
        "role"=>"citizen"
      }
    }
  end

  def need_attributes_3
    {
      "content_id"=>"0925fd2b-6b59-4120-a849-96ab19b9c7df",
      "need_id" => 100521,
      "details"=>{
        "role"=>"citizen",
        "goal"=>"take my tax appeal to a tribunal",
        "benefit"=>"I can have my case heard again and get the decision reversed"
      }
    }
  end


  context "listing needs" do
    should "call the Publishing API adapter and return needs" do
      request_params = {
        document_type: 'need',
        page: 1,
        per_page: 50,
        publishing_app: 'need-api',
        fields: ['content_id', 'need_ids', 'details'],
        locale: 'en',
        order: '-public_updated_at'
      }
      needs = [
        Need.new(need_attributes_1["details"]),
        Need.new(need_attributes_2["details"]),
        Need.new(need_attributes_3["details"])
      ]
      publishing_api_has_content(
        needs,
        document_type: 'need',
        page: 1,
        per_page: 50,
        publishing_app: 'need-api',
        fields: ['content_id', 'need_ids', 'details'],
        locale: 'en',
        order: '-public_updated_at'
      )

      GdsApi::PublishingApiV2.any_instance.expects(:get_content_items)
        .with(request_params)
        .returns(stub_publishing_api_response)

      Need.list
    end

    should "pass parameters to the API adapter" do
      GdsApi::NeedApi.any_instance.expects(:needs)
        .with({page: 2})
        .returns(stub_need_response)

      Need.list(page: 2)
    end

    should "return a list of Need objects" do
      GdsApi::NeedApi.any_instance.expects(:needs).once.returns(stub_need_response)
      need_list = Need.list
      assert_equal 1, need_list.length
      assert need_list.all? { |need| need.is_a? Need }
    end

    should "report each need as existing" do
      GdsApi::NeedApi.any_instance.expects(:needs).once.returns(stub_need_response)
      assert Need.list.all?(&:persisted?)
    end

    should "retain pagination info" do
      GdsApi::NeedApi.any_instance.expects(:needs).once.returns(stub_need_response)
      need_list = Need.list

      assert_equal 2, need_list.pages
      assert_equal 60, need_list.total
      assert_equal 50, need_list.page_size
      assert_equal 1, need_list.current_page
      assert_equal 1, need_list.start_index
    end
  end

  context "requesting needs by IDs" do
    setup do
      @need1 = {
        "id" => "10001",
        "role" => "parent",
        "goal" => "apply for a primary school place",
        "benefit" => "my child can start school" }

      @need2 = {
        "id" => "10002",
        "role" => "person",
        "goal" => "do stuff",
        "benefit" => "get stuff done" }

      need_api_has_need_ids([@need1, @need2])
    end

    should "return an array of matching Need objects" do
      needs = Need.by_ids(10001, 10002)

      assert_equal 2, needs.size
      assert_equal %w(10001 10002), needs.map(&:id)
      assert_equal %w(parent person), needs.map(&:role)
    end
  end

  def stub_response(additional_atts = {})
    response_hash = {
      "_response_info" => { "status" => "ok" },
      "id" => 100001,
      "role" => "person",
      "goal" => "do things",
      "benefit" => "good things"
    }.merge(additional_atts)
    stub("response", to_hash: response_hash)
  end

  context "loading needs" do
    should "construct a need from an API response" do
      GdsApi::NeedApi.any_instance.expects(:need).once.with(100001).returns(stub_response)

      need = Need.find(100001)

      assert_equal 100001, need.need_id
      assert_equal "person", need.role
      assert_equal "do things", need.goal
      assert_equal "good things", need.benefit
      assert need.persisted?
    end

    should "return organisations for a need" do
      response = stub_response(
        "organisations" => [
          {
            "id" => "ministry-of-joy",
            "name" => "Ministry of Joy"
          },
          {
            "id" => "ministry-of-plenty",
            "name" => "Ministry of Plenty"
          }
        ]
      )
      GdsApi::NeedApi.any_instance.expects(:need).once.with(100001).returns(response)

      need = Need.find(100001)
      assert_equal 2, need.organisations.count

      first_organisation = need.organisations.first

      assert_equal "ministry-of-joy", first_organisation["id"]
      assert_equal "Ministry of Joy", first_organisation["name"]
    end

    should "return revisions for a need" do
      response = stub_response(
        "revisions" => [
          {
            "action_type" => "update",
            "author" => {
              "name" => "Jack Bauer",
              "email" => "jack.bauer@test.com"
            },
            "changes" => {
              "goal" => ["apply for a secondary school place", "apply for a primary school place"],
              "role" => [nil, "parent"]
            },
            "created_at" => "2013-05-01T00:00:00+00:00"
          },
          {
            "action_type" => "create",
            "author" => {
              "name" => "Jack Sparrow",
              "email" => "jack.sparrow@test.com",
            },
            "changes" => {
              "goal" => ["apply for a school place", "apply for a secondary school place"],
              "role" => ["grandparent", nil]
            },
            "created_at" => "2013-01-01T00:00:00+00:00"
          }
        ]
      )
      GdsApi::NeedApi.any_instance.expects(:need).once.with(100001).returns(response)

      need = Need.find(100001)

      assert_equal 2, need.revisions.count

      first_revision = need.revisions.first

      assert_equal "update", first_revision["action_type"]
      assert_equal "Jack Bauer", first_revision["author"]["name"]
      assert_equal "jack.bauer@test.com", first_revision["author"]["email"]

      assert_nil first_revision["author"]["uid"]

      assert_equal %w(goal role), first_revision["changes"].keys
      assert_equal ["apply for a secondary school place", "apply for a primary school place"], first_revision["changes"]["goal"]
      assert_equal [nil, "parent"], first_revision["changes"]["role"]

      assert_equal "2013-05-01T00:00:00+00:00", first_revision["created_at"]
    end

    should "correctly assign protected fields" do
      response = stub_response(
        "status" => { "description" => "some status" }
      )
      GdsApi::NeedApi.any_instance.expects(:need).once.with(100001).returns(response)

      need = Need.find(100001)
      assert_equal "some status", need.status.description
    end

    context "returning artefacts for a need" do
      setup do
        GdsApi::NeedApi.any_instance.expects(:need).once.with(100001).returns(stub_response)
        @need = Need.find(100001)
      end

      should "fetch artefacts from the content api" do
        artefacts = [
          OpenStruct.new(
            id: "http://contentapi.dev.gov.uk/pay-council-tax",
            web_url: "http://www.dev.gov.uk/pay-council-tax",
            title: "Pay your council tax",
            format: "transaction"
          ),
          OpenStruct.new(
            id: "http://contentapi.dev.gov.uk/council-tax",
            web_url: "http://www.dev.gov.uk/council-tax",
            title: "Council tax",
            format: "guide"
          )
        ]
        GdsApi::ContentApi.any_instance.expects(:for_need).once.with(100001).returns(artefacts)

        assert_equal 2, @need.artefacts.count
        assert_equal "http://contentapi.dev.gov.uk/pay-council-tax", @need.artefacts[0].id
        assert_equal "http://www.dev.gov.uk/pay-council-tax", @need.artefacts[0].web_url
        assert_equal "Pay your council tax", @need.artefacts[0].title
        assert_equal "transaction", @need.artefacts[0].format
      end

      should "be an empty array if there are any api errors" do
        GdsApi::ContentApi.any_instance.expects(:for_need).once
          .with(100001)
          .raises(GdsApi::HTTPErrorResponse.new(500))

        assert_equal [], @need.artefacts
      end
    end

    should "raise an error when need not found" do
      GdsApi::NeedApi.any_instance.expects(:need).once
        .with(100001)
        .raises(GdsApi::HTTPNotFound.new(404))

      assert_raises Need::NotFound do
        Need.find(100001)
      end
    end
  end

  context "updating needs" do
    setup do
      need_hash = {
        "id" => 100001,
        "role" => "person",
        "goal" => "do things",
        "benefit" => "good things"
      }
      @need = Need.new(need_hash, existing = true)
    end

    context "updating fields" do
      should "update fields" do
        @need.update(
          "impact" => "Endangers people",
          "yearly_searches" => 50000
        )

        assert_equal "person", @need.role
        assert_equal "do things", @need.goal
        assert_equal "good things", @need.benefit
        assert_equal "Endangers people", @need.impact
        assert_equal 50000, @need.yearly_searches
      end

      should "strip leading newline characters from textareas" do
        @need.update(
          "legislation" => "\nRemove the newline from legislation",
          "other_evidence" => "\nRemove the newline from other_evidence"
        )
        assert_equal "Remove the newline from legislation", @need.legislation
        assert_equal "Remove the newline from other_evidence", @need.other_evidence
      end

      should "reject unrecognised fields" do
        assert_raises ArgumentError do
          @need.update("cheese" => "obstinate")
        end
      end

      should "reject a protected field" do
        assert_raises ArgumentError do
          @need.update("duplicate_of" => "foo")
        end
      end

      should "create an accessor to update the protected field" do
        @need.status = NeedStatus.new("description" => "some status")
        assert_equal "some status", @need.status.description
      end
    end

    should "call the need API" do
      author = User.new(name: "O'Brien", email: "obrien@alphagov.co.uk", uid: "user-1234")
      update_hash = {
        "role" => "person",
        "goal" => "do things",
        "benefit" => "excellent things",
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
        "status" => nil,
        "author" => {
          "name" => "O'Brien", "email" => "obrien@alphagov.co.uk", "uid" => "user-1234"
        }
      }
      GdsApi::NeedApi.any_instance.expects(:update_need).once.with(100001, update_hash)
      @need.update("benefit" => "excellent things")
      @need.save_as(author)
    end
  end

  should "return whether a need state is 'valid' or not" do
    need = Need.new({ "status" => { "description" => "not valid" } }, true)
    assert need.has_invalid_status?

    need = Need.new({ "status" => { "description" => "proposed" } }, true)
    refute need.has_invalid_status?
  end

  context "closing needs as duplicates" do
    setup do
      need_hash = {
        "id" => 100002,
        "role" => "person",
        "goal" => "do things",
        "benefit" => "good things"
      }
      @need = Need.new(need_hash, existing = true)
    end

    should "call Need API with the correct values" do
      author = User.new(name: "O'Brien", email: "obrien@alphagov.co.uk", uid: "user-1234")
      duplicate_atts = {
        "duplicate_of" => 100001,
        "author" => {
          "name" => "O'Brien",
          "email" => "obrien@alphagov.co.uk",
          "uid" => "user-1234"
        }
      }
      GdsApi::NeedApi.any_instance.expects(:close).once.with(100002, duplicate_atts)
      @need.duplicate_of = 100001
      @need.close_as(author)
      assert @need.duplicate?
    end
  end

  context "reopening needs" do
    setup do
      need_hash = {
        "id" => 100002,
        "role" => "person",
        "goal" => "do things",
        "benefit" => "good things",
        "duplicate_of" => 100001
      }
      @need = Need.new(need_hash, existing = true)
    end

    should "call Need API with the correct values" do
      author = User.new(name: "O'Brien", email: "obrien@alphagov.co.uk", uid: "user-1234")
      GdsApi::NeedApi.any_instance.expects(:reopen).once
        .with(100002, {
          "author" => {
            "name" => "O'Brien",
            "email" => "obrien@alphagov.co.uk",
            "uid" => "user-1234"
          }
        })
      @need.reopen_as(author)
    end
  end
end
