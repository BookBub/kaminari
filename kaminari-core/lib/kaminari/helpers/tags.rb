# frozen_string_literal: true

module Kaminari
  module Helpers
    PARAM_KEY_EXCEPT_LIST = [:authenticity_token, :commit, :utf8, :_method, :script_name, :original_script_name].freeze

    # A tag stands for an HTML tag inside the paginator.
    # Basically, a tag has its own partial template file, so every tag can be
    # rendered into String using its partial template.
    #
    # The template file should be placed in your app/views/kaminari/ directory
    # with underscored class name (besides the "Tag" class. Tag is an abstract
    # class, so _tag partial is not needed).
    #   e.g.)  PrevLink  ->  app/views/kaminari/_prev_link.html.erb
    #
    # When no matching templates were found in your app, the engine's pre
    # installed template will be used.
    #   e.g.)  Paginator  ->  $GEM_HOME/kaminari-x.x.x/app/views/kaminari/_paginator.html.erb
    class Tag
      def initialize(template, params: nil, param_name: nil, theme: nil, views_prefix: nil, internal_params: nil, **options) #:nodoc:
        @template, @theme, @views_prefix, @options = template, theme, views_prefix, options
        @param_name = param_name || Kaminari.config.param_name

        if internal_params
          @params = internal_params
        else
          @params = template.params
          # @params in Rails 5 no longer inherits from Hash
          @params = if @params.respond_to?(:to_unsafe_h)
            @params.to_unsafe_h
          else
            @params.with_indifferent_access
          end
          @params.except!(*PARAM_KEY_EXCEPT_LIST)
          @params.merge! params if params
        end
      end

      def to_s(locals = {}) #:nodoc:
        formats = @template.respond_to?(:formats) ? @template.formats : Array(@template.params[:format])
        formats += [:html] unless formats.include? :html
        @template.render partial: partial_path, locals: @options.merge(locals), formats: formats
      end

      def page_url_for(page)
        params = params_for(page)
        params[:only_path] = true

        # kaminari is having a difficult time with our efforts to move code out of the engine back into the main app. The issue is the url_for reverse lookup from controller/action to path when the engine and main app share the same initial part of the path (engine_mount/app/controllers/... vs app/controllers/engine_mount/...) - it's only searching the engine routes.
        # The begin/rescue block below will catch this case and call the main app url_for which correctly resolves the main app route. This is a temporary measure while we're moving controllers out of the engine. Most pagination will use the default logic, but the engine controllers that we're moving back to the main app will fall into the rescue block.
        begin
          @template.url_for params
        rescue ActionController::UrlGenerationError => e
          Rails.application.routes.url_helpers.url_for params
        end
      end

      private

      def params_for(page)
        if (@param_name == :page) || !@param_name.include?('[')
          page_val = !Kaminari.config.params_on_first_page && (page <= 1) ? nil : page
          @params[@param_name] = page_val
          @params
        else
          page_params = Rack::Utils.parse_nested_query("#{@param_name}=#{page}")
          page_params = @params.deep_merge(page_params)

          if !Kaminari.config.params_on_first_page && (page <= 1)
            # This converts a hash:
            #   from: {other: "params", page: 1}
            #     to: {other: "params", page: nil}
            #   (when @param_name == "page")
            #
            #   from: {other: "params", user: {name: "yuki", page: 1}}
            #     to: {other: "params", user: {name: "yuki", page: nil}}
            #   (when @param_name == "user[page]")
            @param_name.to_s.scan(/[\w\.]+/)[0..-2].inject(page_params){|h, k| h[k] }[$&] = nil
          end

          page_params
        end
      end

      def partial_path
        "#{@views_prefix}/kaminari/#{@theme}/#{self.class.name.demodulize.underscore}".gsub('//', '/')
      end
    end

    # Tag that contains a link
    module Link
      # target page number
      def page
        raise 'Override page with the actual page value to be a Page.'
      end
      # the link's href
      def url
        page_url_for page
      end
      def to_s(locals = {}) #:nodoc:
        locals[:url] = url
        super locals
      end
    end

    # A page
    class Page < Tag
      include Link
      # target page number
      def page
        @options[:page]
      end
      def to_s(locals = {}) #:nodoc:
        locals[:page] = page
        super locals
      end
    end

    # Link with page number that appears at the leftmost
    class FirstPage < Tag
      include Link
      def page #:nodoc:
        1
      end
    end

    # Link with page number that appears at the rightmost
    class LastPage < Tag
      include Link
      def page #:nodoc:
        @options[:total_pages]
      end
    end

    # The "previous" page of the current page
    class PrevPage < Tag
      include Link

      # TODO: Remove this initializer before 1.3.0.
      def initialize(template, params: {}, param_name: nil, theme: nil, views_prefix: nil, **options) #:nodoc:
        # params in Rails 5 may not be a Hash either,
        # so it must be converted to a Hash to be merged into @params
        if params && params.respond_to?(:to_unsafe_h)
          ActiveSupport::Deprecation.warn 'Explicitly passing params to helpers could be omitted.'
          params = params.to_unsafe_h
        end

        super(template, params: params, param_name: param_name, theme: theme, views_prefix: views_prefix, **options)
      end

      def page #:nodoc:
        @options[:current_page] - 1
      end
    end

    # The "next" page of the current page
    class NextPage < Tag
      include Link

      # TODO: Remove this initializer before 1.3.0.
      def initialize(template, params: {}, param_name: nil, theme: nil, views_prefix: nil, **options) #:nodoc:
        # params in Rails 5 may not be a Hash either,
        # so it must be converted to a Hash to be merged into @params
        if params && params.respond_to?(:to_unsafe_h)
          ActiveSupport::Deprecation.warn 'Explicitly passing params to helpers could be omitted.'
          params = params.to_unsafe_h
        end

        super(template, params: params, param_name: param_name, theme: theme, views_prefix: views_prefix, **options)
      end

      def page #:nodoc:
        @options[:current_page] + 1
      end
    end

    # Non-link tag that stands for skipped pages...
    class Gap < Tag
    end
  end
end
