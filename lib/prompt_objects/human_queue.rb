# frozen_string_literal: true

require "securerandom"

module PromptObjects
  # Represents a pending request for human input
  class HumanRequest
    attr_reader :id, :capability, :question, :options, :created_at
    attr_accessor :response

    def initialize(capability:, question:, options: nil)
      @id = SecureRandom.uuid
      @capability = capability
      @question = question
      @options = options
      @created_at = Time.now
      @response = nil
      @mutex = Mutex.new
      @condition = ConditionVariable.new
    end

    def pending?
      @response.nil?
    end

    def age
      Time.now - @created_at
    end

    def age_string
      seconds = age.to_i
      if seconds < 60
        "#{seconds}s"
      elsif seconds < 3600
        "#{seconds / 60}m"
      else
        "#{seconds / 3600}h"
      end
    end

    # Called by the background thread to wait for response
    def wait_for_response
      @mutex.synchronize do
        @condition.wait(@mutex) while @response.nil?
        @response
      end
    end

    # Called by the UI thread when human responds
    def respond!(value)
      @mutex.synchronize do
        @response = value
        @condition.broadcast
      end
    end
  end

  # Queue for managing pending human requests across all POs
  class HumanQueue
    attr_reader :pending

    def initialize
      @pending = []
      @subscribers = []
      @mutex = Mutex.new
    end

    # Add a request to the queue
    # Returns the HumanRequest object
    def enqueue(capability:, question:, options: nil)
      request = HumanRequest.new(
        capability: capability,
        question: question,
        options: options
      )

      @mutex.synchronize do
        @pending << request
      end

      notify_subscribers(:added, request)
      request
    end

    # Respond to a pending request by ID
    def respond(request_id, value)
      request = nil
      @mutex.synchronize do
        request = @pending.find { |r| r.id == request_id }
        return unless request

        @pending.delete(request)
      end

      notify_subscribers(:resolved, request)
      request.respond!(value)
    end

    # Get pending requests for a specific capability
    def pending_for(capability_name)
      @mutex.synchronize do
        @pending.select { |r| r.capability == capability_name }
      end
    end

    # Get count of pending requests per capability
    def pending_counts
      @mutex.synchronize do
        @pending.group_by(&:capability).transform_values(&:count)
      end
    end

    # Total pending count
    def count
      @mutex.synchronize { @pending.length }
    end

    # Subscribe to queue events
    # Callback receives (event, request) where event is :added or :resolved
    def subscribe(&block)
      @subscribers << block
    end

    def unsubscribe(block)
      @subscribers.delete(block)
    end

    # Get all pending requests (thread-safe copy)
    def all_pending
      @mutex.synchronize { @pending.dup }
    end

    private

    def notify_subscribers(event, request)
      @subscribers.each do |s|
        s.call(event, request)
      rescue StandardError => e
        # Don't let subscriber errors break the queue
        warn "HumanQueue subscriber error: #{e.message}"
      end
    end
  end
end
