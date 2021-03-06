# Fat Free CRM
# Copyright (C) 2008-2009 by Michael Dvorkin
# 
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
# 
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <http:#www.gnu.org/licenses/>.
#------------------------------------------------------------------------------

namespace :crm do

  namespace :settings do
    desc "Load default application settings"
    task :load => :environment do
      ActiveRecord::Base.establish_connection(Rails.env)
      if ActiveRecord::Base.connection.adapter_name.downcase == "mysql"
        ActiveRecord::Base.connection.execute("TRUNCATE settings")
      else
        ActiveRecord::Base.connection.execute("DELETE FROM settings")
      end
      settings = YAML.load_file("#{RAILS_ROOT}/config/settings.yml")
      settings.keys.each do |key|
        sql = [ "INSERT INTO settings (name, default_value) VALUES(?, ?)", key.to_s, Base64.encode64(Marshal.dump(settings[key])) ]
        sql = if Rails::VERSION::STRING < "2.3.3"
          ActiveRecord::Base.send(:sanitize_sql, sql)
        else
          ActiveRecord::Base.send(:sanitize_sql, sql, nil) # Rails 2.3.3 introduces extra "table_name" parameter.
        end
        ActiveRecord::Base.connection.execute(sql)
      end
    end
  end

  desc "Prepare the database and load default application settings"
  task :setup => :environment do
    Rake::Task["db:migrate:reset"].invoke
    Rake::Task["crm:settings:load"].invoke
    Rake::Task["crm:setup:admin"].invoke
  end

  namespace :setup do
    desc "Create admin user"
    task :admin => :environment do
      require "highline/import"

      puts "\nTo create the admin user you will be prompted to enter username, password,"
      puts "and email address. You might also specify the username of existing user.\n"

      username = password = email = nil
      loop do
        username = ask("\nUsername [system]: ", String) do |s|
          s.validate = /^\S{0,32}$/
          s.whitespace = :strip
        end
        username = "system" if username.blank?

        password = ask("Password [manager]: ", String) do |s|
          s.echo = false unless defined?(::JRuby)
          s.validate = /^\S{0,64}$/
        end
        password = "manager" if password.blank?

        email = ask("Email: ", String) do |s|
          s.validate = /^\S{0,64}$/
        end
        puts "\nThe admin user will be created with the following credentials:\n\n"
        puts "  Username: #{username}"
        puts "  Password: #{'*' * password.length}"
        puts "     Email: #{email}\n"
        continue = ask("\nContinue [yes/no/exit]: ")
        break if continue =~ /y(?:es)*/i
        retry if continue =~ /no*/i
        puts "No admin user was created."
        exit
      end
      user = User.find_by_username(username) || User.new
      user.update_attributes(:username => username, :password => password, :email => email, :admin => true)
      puts "Admin user has been created."
    end
  end

  namespace :demo do
    desc "Load demo data and default application settings"
    task :load => :environment do
      Rake::Task["spec:db:fixtures:load"].invoke      # loading fixtures truncates settings!
      Rake::Task["crm:settings:load"].invoke

      # Simulate random user activities.
      $stdout.sync = true
      puts "Generating user activities..."
      %w(Account Campaign Contact Lead Opportunity Task).inject([]) do |assets, model|
        assets << model.constantize.send(:find, :all)
      end.flatten.shuffle.each do |subject|
        info = subject.respond_to?(:full_name) ? subject.full_name : subject.name
        Activity.create(:action => "created", :created_at => subject.updated_at, :user => subject.user, :subject => subject, :info => info)
        Activity.create(:action => "updated", :created_at => subject.updated_at, :user => subject.user, :subject => subject, :info => info)
        unless subject.is_a?(Task)
          time = subject.updated_at + rand(12 * 60).minutes
          Activity.create(:action => "viewed", :created_at => time, :user => subject.user, :subject => subject, :info => info)
          comments = Comment.find(:all, :conditions => [ "commentable_id=? AND commentable_type=?", subject.id, subject.class.name ])
          comments.each_with_index do |comment, i|
            time = subject.created_at + rand(12 * 60 * i).minutes
            if time > Time.now
              time = subject.created_at + rand(600).minutes
            end
            comment.update_attribute(:created_at, time)
            Activity.create(:action => "commented", :created_at => time, :user => comment.user, :subject => subject, :info => info)
          end
        end
        print "." if subject.id % 10 == 0
      end
      puts
    end

    desc "Reset the database and reload demo data along with default application settings"
    task :reload => :environment do
      Rake::Task["db:migrate:reset"].invoke
      Rake::Task["crm:demo:load"].invoke
    end
  end
end
