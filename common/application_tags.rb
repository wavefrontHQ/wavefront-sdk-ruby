# Metadata about your application represented as tags in Wavefront.
#
# @author Yogesh Prasad Kurmi (ykurmi@vmware.com)

require_relative 'constants'

module Wavefront
  class ApplicationTags

    attr_reader :application, :service, :cluster, :shard, :custom_tags

    # Construct ApplicationTags.
    #
    # @param application [String] Application Name
    # @param service [String] Service Name
    # @param cluster [String] Cluster Name
    # @param shard [String] Shard Name
    # @param custom_tags [List<Hash>] List of pairs of custom tags
    def initialize(application, service, cluster: nil, shard: nil, custom_tags: nil)

      if application.nil?
        raise ArgumentError, 'Missing "application" parameter in ApplicationTags!'
      end

      if service.nil?
        raise ArgumentError, 'Missing "service" parameter in ApplicationTags!'
      end

      @application = application
      @service = service
      @cluster = cluster
      @shard = shard
      @custom_tags = custom_tags

    end

    # Get all tags as a list
    #
    # @return tags [List<Hash>] List of tags
    def get_as_list
      tags = [{APPLICATION_TAG_KEY => application},
              {SERVICE_TAG_KEY => service},
              {CLUSTER_TAG_KEY => cluster},
              {SHARD_TAG_KEY => shard}]

      tags.push(custom_tags)
    end
  end
end