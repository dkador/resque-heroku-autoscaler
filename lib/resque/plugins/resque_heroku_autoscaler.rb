require 'resque/plugins/heroku_autoscaler/config'

module Resque
  module Plugins
    module HerokuAutoscaler
      @@heroku_client = nil

      def after_enqueue_scale_workers_up(*args)
        puts "after_enqueue_scale_workers_up"
        scaling_disabled = Resque::Plugins::HerokuAutoscaler::Config.scaling_disabled?
        puts "scaling_disabled #{scaling_disabled}"
        info = Resque.info
        puts "resque #{Resque}"
        puts "resque info #{info}"
        count = Resque::Plugins::HerokuAutoscaler::Config.new_worker_count(Resque.info[:pending])
        puts "count #{count}"
        set_workers(1)
        Resque.redis.set('last_scaled', Time.now)
      end

      def after_perform_scale_workers(*args)
        puts "after_perform_scale_workers"
        calculate_and_set_workers
      end

      def on_failure_scale_workers(*args)
        puts "on_failure_scale_workers"
        calculate_and_set_workers
      end

      def set_workers(number_of_workers)
        puts "set_workers with #{number_of_workers}"
        puts "current_workers #{current_workers}"
        if number_of_workers != current_workers
          #heroku_client.set_workers(Resque::Plugins::HerokuAutoscaler::Config.heroku_app, number_of_workers)
          heroku_client.ps_scale(Resque::Plugins::HerokuAutoscaler::Config.heroku_app, :type => "worker", :qty => number_of_workers)
        end
      end

      def current_workers
        ps_result = heroku_client.ps(Resque::Plugins::HerokuAutoscaler::Config.heroku_app)
        puts "ps_result #{ps_result}"
        ps_result.each do |ps_info|
          if ps_info["process"] == "worker.1"
            return 1
          end
        end
        return 0
      end

      def heroku_client
        @@heroku_client || @@heroku_client = Heroku::Client.new(Resque::Plugins::HerokuAutoscaler::Config.heroku_user,
                                                                Resque::Plugins::HerokuAutoscaler::Config.heroku_pass)
      end

      def self.config
        yield Resque::Plugins::HerokuAutoscaler::Config
      end

      def calculate_and_set_workers
        unless Resque::Plugins::HerokuAutoscaler::Config.scaling_disabled?
          wait_for_task_or_scale
          if time_to_scale?
            scale
          end
        end
      end

      private

      def scale
        puts "scale"
        new_count = Resque::Plugins::HerokuAutoscaler::Config.new_worker_count(Resque.info[:pending])
        puts "new_count #{new_count}"
        set_workers(new_count) if new_count == 0 || new_count > current_workers
        Resque.redis.set('last_scaled', Time.now)
      end

      def wait_for_task_or_scale
        until Resque.info[:pending] > 0 || time_to_scale?
          Kernel.sleep(0.5)
        end
      end

      def time_to_scale?
        (Time.now - Time.parse(Resque.redis.get('last_scaled'))) >=  Resque::Plugins::HerokuAutoscaler::Config.wait_time
      end

      def log(message)
        if defined?(Rails)
          Rails.logger.info(message)
        else
          puts message
        end
      end
    end
  end
end