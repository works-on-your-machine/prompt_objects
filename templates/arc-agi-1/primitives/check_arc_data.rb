# frozen_string_literal: true

module PromptObjects
  module Primitives
    class CheckArcData < Primitive
      DATA_DIR = File.expand_path("~/.prompt_objects/data/arc-agi-1")
      TRAINING_DIR = File.join(DATA_DIR, "data", "training")
      EVALUATION_DIR = File.join(DATA_DIR, "data", "evaluation")
      REPO_URL = "https://github.com/fchollet/ARC-AGI.git"

      def name
        "check_arc_data"
      end

      def description
        "Check if ARC-AGI-1 dataset is available locally. Returns status, paths, and setup instructions if missing."
      end

      def parameters
        {
          type: "object",
          properties: {},
          required: []
        }
      end

      def receive(message, context:)
        exists = Dir.exist?(TRAINING_DIR)

        if exists
          training_count = Dir.glob(File.join(TRAINING_DIR, "*.json")).length
          eval_count = Dir.glob(File.join(EVALUATION_DIR, "*.json")).length

          JSON.pretty_generate({
            status: "available",
            path: DATA_DIR,
            training_tasks: training_count,
            evaluation_tasks: eval_count,
            training_dir: TRAINING_DIR,
            evaluation_dir: EVALUATION_DIR
          })
        else
          JSON.pretty_generate({
            status: "missing",
            expected_path: DATA_DIR,
            setup_command: "git clone #{REPO_URL} #{DATA_DIR}",
            message: "ARC-AGI-1 dataset not found. Run the setup command to download it, or ask the human to do so."
          })
        end
      end
    end
  end
end
