# frozen_string_literal: true

module PromptObjects
  module Primitives
    class LoadArcTask < Primitive
      def name
        "load_arc_task"
      end

      def description
        "Load an ARC-AGI task from a JSON file. Returns training pairs and test inputs with grid dimensions."
      end

      def parameters
        {
          type: "object",
          properties: {
            path: {
              type: "string",
              description: "Path to the ARC task JSON file"
            }
          },
          required: ["path"]
        }
      end

      def receive(message, context:)
        path = message[:path] || message["path"]
        return "Error: path is required" unless path

        expanded = File.expand_path(path)
        return "Error: File not found: #{path}" unless File.exist?(expanded)

        data = JSON.parse(File.read(expanded, encoding: "UTF-8"))
        train = data["train"] || []
        test = data["test"] || []

        result = {
          task_id: File.basename(expanded, ".json"),
          training_pairs: train.length,
          test_inputs: test.length,
          train: train.map.with_index { |pair, i|
            {
              pair: i,
              input: pair["input"],
              output: pair["output"],
              input_size: "#{pair["input"].length}x#{pair["input"][0].length}",
              output_size: "#{pair["output"].length}x#{pair["output"][0].length}"
            }
          },
          test: test.map.with_index { |t, i|
            {
              test: i,
              input: t["input"],
              input_size: "#{t["input"].length}x#{t["input"][0].length}"
            }
          }
        }

        JSON.pretty_generate(result)
      rescue JSON::ParserError => e
        "Error: Invalid JSON - #{e.message}"
      rescue StandardError => e
        "Error loading task: #{e.message}"
      end
    end
  end
end
