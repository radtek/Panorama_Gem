# desc "Explaining what the task does"
# task :panorama_gem do
#   # Task goes here
# end


=begin
desc "Run tests"
task :test do
  require 'bundler/gem_tasks'

  require 'rake/testtask'

  Rake::TestTask.new(:test) do |t|
    t.libs << 'lib'
    t.libs << 'test'
    t.pattern = 'test/**/*_test.rb'
    t.verbose = false
  end
end
=end


# Remove database tasks for nulldb-adapter
Rake::TaskManager.class_eval do
  def delete_task(task_name)
    @tasks.delete(task_name.to_s)
  end

  Rake.application.delete_task("db:test:load")
  Rake.application.delete_task("db:test:purge")
  Rake.application.delete_task("db:abort_if_pending_migrations")

  puts "Environment entry DB_VERSION = #{ENV['DB_VERSION']}"
end

namespace :db do
  namespace :test do
    task :load do
      puts 'Task db:test:load removed by lib/tasks/panorama_gem_tasks.rake !'
    end
    task :purge do
      puts 'Task db:test:purge removed by lib/tasks/panorama_gem_tasks.rake !'
    end
  end
  task :abort_if_pending_migrations do
    puts 'Task db:db:abort_if_pending_migrations removed by lib/tasks/panorama_gem_tasks.rake !'
  end
end
