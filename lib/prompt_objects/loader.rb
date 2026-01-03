# frozen_string_literal: true

module PromptObjects
  # Loads and parses prompt object markdown files.
  # Extracts YAML frontmatter (config) and markdown body (soul).
  class Loader
    # Load a prompt object from a markdown file.
    # @param path [String] Path to the .md file
    # @return [Hash] Parsed data with :config, :body, and :path
    def self.load(path)
      raise Error, "File not found: #{path}" unless File.exist?(path)

      content = File.read(path, encoding: "UTF-8")
      parsed = FrontMatterParser::Parser.new(:md).call(content)

      {
        config: parsed.front_matter || {},
        body: parsed.content.strip,
        path: path
      }
    end

    # Load all prompt objects from a directory.
    # @param dir [String] Directory path
    # @return [Array<Hash>] Array of parsed prompt objects
    def self.load_all(dir)
      raise Error, "Directory not found: #{dir}" unless Dir.exist?(dir)

      Dir.glob(File.join(dir, "*.md")).map { |path| load(path) }
    end
  end
end
