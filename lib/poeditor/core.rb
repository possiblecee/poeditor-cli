require "json"
require "net/http"

module POEditor
  class Core
    # @return [POEditor::Configuration] The configuration for export
    attr_accessor :configuration

    # @param configuration [POEditor::Configuration]
    def initialize(configuration)
      unless configuration.is_a? Configuration
        raise POEditor::Exception.new \
          "`configuration` should be an `Configuration`"
      end
      @configuration = configuration
    end

    # Request POEditor API
    #
    # @param action [String]
    # @param api_token [String]
    # @param options [Hash{Sting => Object}]
    #
    # @return [Net::HTTPResponse] The response object of API request
    #
    # @see https://poeditor.com/api_reference/ POEditor API Reference
    def api(action, api_token, options={})
      uri = URI("https://api.poeditor.com/v2/#{action}")
      options["api_token"] = api_token
      return Net::HTTP.post_form(uri, options)
    end

    # Pull translations
    def pull()
      UI.puts "\nExport translations"
      for language in @configuration.languages
        UI.puts "  - Exporting '#{language}'"
        content = self.export(:api_key => @configuration.api_key,
                              :project_id => @configuration.project_id,
                              :language => language,
                              :type => @configuration.type,
                              :filters => @configuration.filters,
                              :tags => @configuration.tags)
        write(language, content)

        for alias_to, alias_from in @configuration.language_alias
          if language == alias_from
            write(alias_to, content)
          end
        end
      end
    end

    # Pull translations for untranslated check
    def check_untranslated()
      UI.puts "\nExport untranslated terms"
      for language in @configuration.languages
        UI.puts "  - Checking '#{language}'"
        content = self.export(:api_key => @configuration.api_key,
                              :project_id => @configuration.project_id,
                              :language => language,
                              :type => @configuration.type,
                              :filters => ["untranslated"],
                              :tags => @configuration.tags)
        if content.length < 2
          UI.puts "  #{"\xe2\x9c\x93".green} OK!\n".green
        else
          UI.puts "  #{"\xe2\x9c\x98 Untranslated found!".bold.red}\n#{content.red}"
        end
      end
    end

    # Export translation for specific language
    #
    # @param api_key [String]
    # @param project_jd [String]
    # @param language [String]
    # @param type [String]
    # @param filters [Array<String>]
    # @param tags [Array<String>]
    #
    # @return Downloaded translation content
    def export(api_key:, project_id:, language:, type:, filters:nil, tags:nil)
      options = {
        "id" => project_id,
        "language" => convert_to_poeditor_language(language),
        "type" => type,
        "filters" => (filters || []).join(","),
        "tags" => (tags || []).join(","),
      }
      response = self.api("projects/export", api_key, options)
      data = JSON(response.body)
      unless data["response"]["status"] == "success"
        code = data["response"]["code"]
        message = data["response"]["message"]
        raise POEditor::Exception.new "#{message} (#{code})"
      end

      download_uri = URI(data["result"]["url"])
      content = Net::HTTP.get(download_uri)

      case type
      when "apple_strings"
        content.gsub!(/(%(\d+\$)?)s/, '\1@')  # %s -> %@
      when "android_strings"
        content.gsub!(/(%(\d+\$)?)@/, '\1s')  # %@ -> %s
      end

      unless content.end_with? "\n"
        content += "\n"
      end
      return content
    end

    def convert_to_poeditor_language(language)
      if language.downcase.match(/zh.+(hans|cn)/)
        'zh-CN'
      elsif language.downcase.match(/zh.+(hant|tw)/)
        'zh-TW'
      else
        language
      end
    end

    # Write translation file
    def write(language, content)
      path = path_for_language(language)
      unless File.exist?(path)
        raise POEditor::Exception.new "#{path} doesn't exist"
      end
      File.write(path, content)
      UI.puts "      #{"\xe2\x9c\x93".green} Saved at '#{path}'"
    end

    def path_for_language(language)
      if @configuration.path_replace[language]
        @configuration.path_replace[language]
      else
        @configuration.path.gsub("{LANGUAGE}", language)
      end
    end

  end
end
