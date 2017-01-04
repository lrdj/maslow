require "active_model"

class Need
  extend ActiveModel::Naming
  include ActiveModel::Validations
  include ActiveModel::Conversion
  include ActiveModel::Serialization

  class NotFound < StandardError
    attr_reader :need_id

    def initialize(need_id)
      super("Need with ID #{need_id} not found")
      @need_id = need_id
    end
  end

  # Allow us to convert the API response to a list of Need objects, but still
  # retain the pagination information
  class PaginatedList < Array
    PAGINATION_PARAMS = [:pages, :total, :page_size, :current_page, :start_index]
    attr_reader *PAGINATION_PARAMS

    def initialize(needs, pagination_info)
      super(needs)

      @pages = pagination_info["pages"]
      @total = pagination_info["total"]
      @page_size = pagination_info["page_size"]
      @current_page = pagination_info["current_page"]
      @start_index = pagination_info["start_index"]
    end

    def inspect
      pagination_params = Hash[
        PAGINATION_PARAMS.map { |param_name| [param_name, send(param_name)] }
      ]
      "#<#{self.class} #{super}, #{pagination_params}>"
    end
  end

  JUSTIFICATIONS = [
    "It's something only government does",
    "The government is legally obliged to provide it",
    "It's inherent to a person's or an organisation's rights and obligations",
    "It's something that people can do or it's something people need to know before they can do something that's regulated by/related to government",
    "There is clear demand for it from users",
    "It's something the government provides/does/pays for",
    "It's straightforward advice that helps people to comply with their statutory obligations"
  ]
  IMPACT = [
    "No impact",
    "Noticed only by an expert audience",
    "Noticed by the average member of the public",
    "Has consequences for the majority of your users",
    "Has serious consequences for your users and/or their customers",
    "Endangers people"
  ]

  NUMERIC_FIELDS = %w(yearly_user_contacts yearly_site_views yearly_need_views yearly_searches)
  MASS_ASSIGNABLE_FIELDS = %w(id  status applies_to_all_organisations role goal benefit organisation_ids impact justifications met_when
                              other_evidence legislation) + NUMERIC_FIELDS

  # fields which should not be updated through mass-assignment.
  # this is equivalent to using ActiveModel's attr_protected
  PROTECTED_FIELDS = %w(duplicate_of)

  # fields which we should create read and write accessors for
  # and which we should send back to the Need API
  WRITABLE_FIELDS = MASS_ASSIGNABLE_FIELDS + PROTECTED_FIELDS

  # non-writable fields returned from the API which we want to make accessible
  # but which we don't want to send back to the Need API
  READ_ONLY_FIELDS = %w(revisions organisations)

  attr_accessor *WRITABLE_FIELDS
  attr_reader *READ_ONLY_FIELDS

  alias_method :need_id, :id

  validates_presence_of %w(role goal benefit)
  validates :impact, inclusion: { in: IMPACT }, allow_blank: true
  validates_each :justifications do |record, attr, value|
    record.errors.add(attr, "must contain a known value") unless value.nil? || value.all? { |v| JUSTIFICATIONS.include? v }
  end
  NUMERIC_FIELDS.each do |field|
    validates_numericality_of field, only_integer: true, allow_blank: true, greater_than_or_equal_to: 0
  end

  # Retrieve a list of needs from the Publishing API
  #
  def self.list(options = {})
    options = default_options.merge(options)
    response = Maslow.publishing_api_v2.get_content_items(options)
    need_objects = build_needs(response["results"])
    PaginatedList.new(need_objects, response)
  end

  # Retrieve a list of needs matching an array of ids
  #
  # Note that this returns the entire set of matching ids and not a
  # PaginatedList
  def self.by_ids(*ids)
    response = Maslow.need_api.needs_by_id(ids.flatten)

    response.with_subsequent_pages.map { |need| self.new(need, true) }
  end

  # Retrieve a need from the Need API, or raise NotFound if it doesn't exist.
  #
  # This works in roughly the same way as an ActiveRecord-style `find` method,
  # just with a different exception type.
  def self.find(need_id)
    need_response = Maslow.need_api.need(need_id)
    self.new(need_response.to_hash, true)
  rescue GdsApi::HTTPNotFound
    raise NotFound, need_id
  end

  def initialize(attrs, existing = false)
    @existing = existing

    if existing
      assign_read_only_and_protected_attributes(attrs)

      # discard all the read-only fields and anything else from the API which
      # we don't understand, before calling the update method below
      #
      # we only do this for initializing an existing need from the API so that
      # we can raise an error when invalid fields are submitted through the
      # Maslow forms.
      attrs = filtered_attributes(attrs)
    end

    # assign all the writable attributes
    update(attrs)
  end

  def add_more_criteria
    @met_when << ""
  end

  def remove_criteria(index)
    @met_when.delete_at(index)
  end

  def duplicate?
    duplicate_of.present?
  end

  def update(attrs)
    strip_newline_from_textareas(attrs)

    unless (attrs.keys - MASS_ASSIGNABLE_FIELDS).empty?
      p (attrs.keys - MASS_ASSIGNABLE_FIELDS)
      raise(ArgumentError, "Unrecognised attributes present in: #{attrs.keys}")
    end

    attrs.keys.each do |f|
      send("#{f}=", attrs[f])
    end

    @met_when ||= []
    @justifications ||= []
    @organisation_ids ||= []
  end

  def artefacts
    @artefacts ||= Maslow.content_api.for_need(@id)
  rescue GdsApi::BaseError
    []
  end

  def as_json(options = {})
    # Build up the hash manually, as ActiveModel::Serialization's default
    # behaviour serialises all attributes, including @errors and
    # @validation_context.
    remove_blank_met_when_criteria
    res = (WRITABLE_FIELDS).each_with_object({}) do |field, hash|
      value = send(field)
      if value.present?
        # if this is a numeric field, force the value we send to the API to be an
        # integer
        value = Integer(value) if NUMERIC_FIELDS.include?(field)
      end

      # catch empty text fields and send them as null values instead for consistency
      # with updates on other fields
      value = nil if value == ""

      hash[field] = value.as_json
    end
  end

  def save
    raise("The save_as method must be used when persisting a need, providing details about the author.")
  end

  def close_as(author)
    duplicate_atts = {
      "duplicate_of" => @duplicate_of,
      "author" => author_atts(author)
    }
    Maslow.need_api.close(@id, duplicate_atts)
    true
  rescue GdsApi::HTTPErrorResponse => err
    false
  end

  def reopen_as(author)
    Maslow.need_api.reopen(@id, "author" => author_atts(author))
    true
  rescue GdsApi::HTTPErrorResponse => err
    false
  end

  def save_as(author)
    atts = as_json.merge("author" => author_atts(author))

    if persisted?
      Maslow.need_api.update_need(@id, atts)
    else
      response_hash = Maslow.need_api.create_need(atts).to_hash
      @existing = true

      assign_read_only_and_protected_attributes(response_hash)
      update(filtered_attributes(response_hash))
    end
    true
  rescue GdsApi::HTTPErrorResponse => err
    false
  end

  def persisted?
    @existing
  end

  def has_invalid_status?
    status.description == "not valid"
  end

private

  def self.build_needs(response)
    needs = []
    response.each do |need|
      need_status = Need.map_to_status(need["publication_state"])
      needs << Need.new(
        {
          "id" => need["need_ids"][0],
          "applies_to_all_organisations" => need["applies_to_all_organisations"],
          "benefit" => need["details"]["benefit"],
          "goal" => need["details"]["goal"],
          "role" => need["details"]["role"],
          "status" => need_status
        }
      )
    end
    needs
  end

  def author_atts(author)
    {
      "name" => author.name,
      "email" => author.email,
      "uid" => author.uid
    }
  end

  def assign_read_only_and_protected_attributes(attrs)
    # map the read only and protected fields from the API to instance
    # variables of the same name
    (READ_ONLY_FIELDS + PROTECTED_FIELDS).map(&:to_s).each do |field|
      value = attrs[field]
      prepared_value = case field
                       when 'revisions'
                         prepare_revisions(value)
                       when 'organisations'
                         prepare_organisations(value)
                       when 'status'
                         prepare_status(value)
                       else
                         value
                       end

      instance_variable_set("@#{field}", prepared_value)
    end
  end

  def filtered_attributes(original_attrs)
    # Discard fields from the API we don't understand. Coupling the fields
    # this app understands to the fields it expects from clients is fine, but
    # we don't want to couple that with the fields we can use in the API.
    original_attrs.slice(*MASS_ASSIGNABLE_FIELDS)
    binding.pry
  end

  def prepare_organisations(organisations)
    return [] unless organisations.present?
    organisations
  end

  def prepare_status(status)
    return nil unless status.present?
    NeedStatus.new(status)
  end

  def prepare_revisions(revisions)
    return [] unless revisions.present?

    revisions.each_with_index do |revision, i|
      revision["changes"] = revisions[i]["changes"]
    end
  end

  def remove_blank_met_when_criteria
    met_when.delete_if(&:empty?) if met_when
  end

  def strip_newline_from_textareas(attrs)
    # Rails prepends a newline character into the textarea fields in the form.
    # Strip these so that we don't send them to the Need API.
    %w(legislation other_evidence).each do |field|
      attrs[field].sub!(/\A\n/, "") if attrs[field].present?
    end
  end

  def self.default_options
    {
      document_type: 'need',
      page: 1,
      per_page: 50,
      publishing_app: 'need-api',
      fields: ['content_id', 'need_ids', 'details', 'publication_state'],
      locale: 'en',
      order: '-public_updated_at'
    }
  end

  def self.map_to_status(state)
    case state
    when "published"
      "Valid"
    when "draft"
      "Proposed"
    when "unpublished"
      "Duplicate"
    else
      "Status not recognised: #{state}"
    end
  end
end
