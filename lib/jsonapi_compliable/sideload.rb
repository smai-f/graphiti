module JsonapiCompliable
  # @attr_reader [Symbol] name The name of the sideload
  # @attr_reader [Class] resource_class The corresponding Resource class
  # @attr_reader [Boolean] polymorphic Is this a polymorphic sideload?
  # @attr_reader [Hash] polymorphic_groups The subgroups, when polymorphic
  # @attr_reader [Hash] sideloads The associated sibling sideloads
  # @attr_reader [Proc] scope_proc The configured 'scope' block
  # @attr_reader [Proc] assign_proc The configured 'assign' block
  # @attr_reader [Proc] grouper The configured 'group_by' proc
  # @attr_reader [Symbol] foreign_key The attribute used to match objects - need not be a true database foreign key.
  # @attr_reader [Symbol] primary_key The attribute used to match objects - need not be a true database primary key.
  # @attr_reader [Symbol] type One of :has_many, :belongs_to, etc
  class Sideload
    attr_reader :name,
      :resource_class,
      :polymorphic,
      :polymorphic_groups,
      :sideloads,
      :scope_proc,
      :assign_proc,
      :grouper,
      :foreign_key,
      :primary_key,
      :type

    # NB - the adapter's +#sideloading_module+ is mixed in on instantiation
    #
    # An anonymous Resource will be assigned when none provided.
    #
    # @see Adapters::Abstract#sideloading_module
    def initialize(name, type: nil, resource: nil, polymorphic: false, primary_key: :id, foreign_key: nil)
      @name               = name
      @resource_class     = (resource || Class.new(Resource))
      @sideloads          = {}
      @polymorphic        = !!polymorphic
      @polymorphic_groups = {} if polymorphic?
      @primary_key        = primary_key
      @foreign_key        = foreign_key
      @type               = type

      extend @resource_class.config[:adapter].sideloading_module
    end

    # @see #resource_class
    # @return [Resource] an instance of +#resource_class+
    def resource
      @resource ||= resource_class.new
    end

    # Is this sideload polymorphic?
    #
    # Polymorphic sideloads group the parent objects in some fashion,
    # so different 'types' can be resolved differently. Let's say an
    # +Office+ has a polymorphic +Organization+, which can be either a
    # +Business+ or +Government+:
    #
    #   allow_sideload :organization, :polymorphic: true do
    #     group_by { |record| record.organization_type }
    #
    #     allow_sideload 'Business', resource: BusinessResource do
    #       # ... code ...
    #     end
    #
    #     allow_sideload 'Governemnt', resource: GovernmentResource do
    #       # ... code ...
    #     end
    #   end
    #
    # You probably want to extract this code into an Adapter. For instance,
    # with ActiveRecord:
    #
    #   polymorphic_belongs_to :organization,
    #     group_by: ->(office) { office.organization_type },
    #     groups: {
    #       'Business' => {
    #         scope: -> { Business.all },
    #         resource: BusinessResource,
    #         foreign_key: :organization_id
    #       },
    #       'Government' => {
    #         scope: -> { Government.all },
    #         resource: GovernmentResource,
    #         foreign_key: :organization_id
    #       }
    #     }
    #
    # @see Adapters::ActiveRecordSideloading#polymorphic_belongs_to
    # @return [Boolean] is this sideload polymorphic?
    def polymorphic?
      @polymorphic == true
    end

    # Build a scope that will be used to fetch the related records
    # This scope will be further chained with filtering/sorting/etc
    #
    # You probably want to wrap this logic in an Adapter, instead of
    # specifying in your resource directly.
    #
    # @example Default ActiveRecord
    #   class PostResource < ApplicationResource
    #     # ... code ...
    #     allow_sideload :comments, resource: CommentResource do
    #       scope do |posts|
    #         Comment.where(post_id: posts.map(&:id))
    #       end
    #       # ... code ...
    #     end
    #   end
    #
    # @example Custom Scope
    #   # In this example, our base scope is a Hash
    #   scope do |posts|
    #     { post_ids: posts.map(&:id) }
    #   end
    #
    # @example ActiveRecord via Adapter
    #   class PostResource < ApplicationResource
    #     # ... code ...
    #     has_many :comments,
    #       scope: -> { Comment.all },
    #       resource: CommentResource,
    #       foreign_key: :post_id
    #   end
    #
    # @see Adapters::Abstract
    # @see Adapters::ActiveRecordSideloading#has_many
    # @see #allow_sideload
    # @yieldparam parents - The resolved parent records
    def scope(&blk)
      @scope_proc = blk
    end

    # The proc used to assign the resolved parents and children.
    #
    # You probably want to wrap this logic in an Adapter, instead of
    # specifying in your resource directly.
    #
    # @example Default ActiveRecord
    #   class PostResource < ApplicationResource
    #     # ... code ...
    #     allow_sideload :comments, resource: CommentResource do
    #       # ... code ...
    #       assign do |posts, comments|
    #         posts.each do |post|
    #           relevant_comments = comments.select { |c| c.post_id == post.id }
    #           post.comments = relevant_comments
    #         end
    #       end
    #     end
    #   end
    #
    # @example ActiveRecord via Adapter
    #   class PostResource < ApplicationResource
    #     # ... code ...
    #     has_many :comments,
    #       scope: -> { Comment.all },
    #       resource: CommentResource,
    #       foreign_key: :post_id
    #   end
    #
    # @see Adapters::Abstract
    # @see Adapters::ActiveRecordSideloading#has_many
    # @see #allow_sideload
    # @yieldparam parents - The resolved parent records
    # @yieldparam children - The resolved child records
    def assign(&blk)
      @assign_proc = blk
    end

    # Configure how to associate parent and child records.
    #
    # @example Basic attr_accessor
    #   def associate(parent, child)
    #     if type == :has_many
    #       parent.send(:"#{name}").push(child)
    #     else
    #       child.send(:"#{name}=", parent)
    #     end
    #   end
    #
    # @see #name
    # @see #type
    def associate(parent, child)
      resource_class.config[:adapter].associate(parent, child, name, type)
    end

    # Define a proc that groups the parent records. For instance, with
    # an ActiveRecord polymorphic belongs_to there will be a +parent_id+
    # and +parent_type+. We would want to group on +parent_type+:
    #
    #  allow_sideload :organization, polymorphic: true do
    #    # group parent_type, parent here is 'organization'
    #    group_by ->(office) { office.organization_type }
    #  end
    #
    # @see #polymorphic?
    def group_by(&grouper)
      @grouper = grouper
    end

    # Resolve the sideload.
    #
    # * Uses the 'scope' proc to build a 'base scope'
    # * Chains additional criteria onto that 'base scope'
    # * Resolves that scope (see Scope#resolve)
    # * Assigns the resulting child objects to their corresponding parents
    #
    # @see Scope#resolve
    # @param [Object] parents The resolved parent models
    # @param [Query] query The Query instance
    # @param [Symbol] namespace The current namespace (see Resource#with_context)
    # @see Query
    # @see Resource#with_context
    # @return [void]
    # @api private
    def resolve(parents, query, namespace = nil)
      namespace ||= name

      if polymorphic?
        resolve_polymorphic(parents, query)
      else
        resolve_basic(parents, query, namespace)
      end
    end

    # Configure a relationship between Resource objects
    #
    # You probably want to extract this logic into an adapter
    # rather than using directly
    #
    # @example Default ActiveRecord
    #   # What happens 'under the hood'
    #   class CommentResource < ApplicationResource
    #     # ... code ...
    #     allow_sideload :post, resource: PostResource do
    #       scope do |comments|
    #         Post.where(id: comments.map(&:post_id))
    #       end
    #
    #       assign do |comments, posts|
    #         comments.each do |comment|
    #           relevant_post = posts.find { |p| p.id == comment.post_id }
    #           comment.post = relevant_post
    #         end
    #       end
    #     end
    #   end
    #
    #   # Rather than writing that code directly, go through the adapter:
    #   class CommentResource < ApplicationResource
    #     # ... code ...
    #     use_adapter JsonapiCompliable::Adapters::ActiveRecord
    #
    #     belongs_to :post,
    #       scope: -> { Post.all },
    #       resource: PostResource,
    #       foreign_key: :post_id
    #   end
    #
    # @see Adapters::ActiveRecordSideloading#belongs_to
    # @see #assign
    # @see #scope
    # @return void
    def allow_sideload(name, opts = {}, &blk)
      sideload = Sideload.new(name, opts)
      sideload.instance_eval(&blk) if blk

      if polymorphic?
        @polymorphic_groups[name] = sideload
      else
        @sideloads[name] = sideload
      end
    end

    # Fetch a Sideload object by its name
    # @param [Symbol] name The name of the corresponding sideload
    # @see +allow_sideload
    # @return the corresponding Sideload object
    def sideload(name)
      @sideloads[name]
    end

    # Looks at all nested sideload, and all nested sideloads for the
    # corresponding Resources, and returns an Include Directive hash
    #
    # For instance, this configuration:
    #
    #   class BarResource < ApplicationResource
    #     allow_sideload :baz do
    #     end
    #   end
    #
    #   class PostResource < ApplicationResource
    #     allow_sideload :foo do
    #       allow_sideload :bar, resource: BarResource do
    #       end
    #     end
    #   end
    #
    # +post_resource.sideloading.to_hash+ would return
    #
    #   { base: { foo: { bar: { baz: {} } } } }
    #
    # @return [Hash] The nested include hash
    # @api private
    def to_hash(processed = [])
      return { name => {} } if processed.include?(self)
      processed << self

      result = { name => {} }.tap do |hash|
        @sideloads.each_pair do |key, sideload|
          hash[name][key] = sideload.to_hash(processed)[key] || {}

          if sideload.polymorphic?
            sideload.polymorphic_groups.each_pair do |type, sl|
              hash[name][key].merge!(nested_sideload_hash(sl, processed))
            end
          else
            hash[name][key].merge!(nested_sideload_hash(sideload, processed))
          end
        end
      end
      result
    end

    private

    def nested_sideload_hash(sideload, processed)
      {}.tap do |hash|
        if sideloading = sideload.resource_class.sideloading
          hash.merge!(sideloading.to_hash(processed)[:base])
        end
      end
    end

    def resolve_polymorphic(parents, query)
      parents.group_by(&@grouper).each_pair do |group_type, group_members|
        sideload_for_group = @polymorphic_groups[group_type]
        if sideload_for_group
          sideload_for_group.resolve(group_members, query, name)
        end
      end
    end

    def resolve_basic(parents, query, namespace)
      sideload_scope   = scope_proc.call(parents)
      sideload_scope   = Scope.new(sideload_scope, resource_class.new, query, default_paginate: false, namespace: namespace)
      sideload_results = sideload_scope.resolve
      assign_proc.call(parents, sideload_results)
    end
  end
end
