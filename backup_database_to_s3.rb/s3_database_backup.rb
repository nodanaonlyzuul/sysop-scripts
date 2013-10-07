module CronScripts

  class S3DatabaseBackup < CronScripts::Base
    require 'aws/s3'
    MAXIMUM_BACKUPS = 10

    def do_action
      dump_and_zip
      upload_to_s3
      remove_local_dump
      cleanup_s3
    end

    def log_name
      "db_backup.log"
    end

    private

    def dump_and_zip
      @dbconfig = YAML::load_file(Rails.root.to_s + "/config/database.yml")
      rails_env = Rails.env
      time      = Time.now.strftime("%Y-%m-%d-%H:%M")

      @file_name = "#{@dbconfig[rails_env]['database']}_#{rails_env}_#{time}.sql"
      @dump_path = "/tmp/#{@file_name}"

      @dump_command  =  "mysqldump"
      @dump_command << " --user=#{@dbconfig[rails_env]['username']}"
      @dump_command << " --password=#{@dbconfig[rails_env]['password']}"
      @dump_command << " --result-file=#{@dump_path}"
      @dump_command << " --single-transaction"
      @dump_command << " --quick"
      @dump_command << " #{@dbconfig[rails_env]['database']}"

      log "dumping with: #{@dump_command}"
      `#{@dump_command}`

      log "gzipping..."
      gzip_command = "gzip -9 #{@dump_path}"
      `#{gzip_command}`
    end

    def upload_to_s3
      AWS::S3::Base.establish_connection!(
        :access_key_id     => 'FILL THIS OUT',
        :secret_access_key => 'AND PARTY'
      )

      log("Begininning upload to S3...")

      if AWS::S3::S3Object.store(@file_name+".gz", open(@dump_path+".gz"), bucket_name)
        log("uploaded to S3")
      else
        log("UPLOAD FAILED")
      end
    end

    def remove_local_dump
      log "Deleting local file #{@dump_path}.gz"
      `rm #{@dump_path}.gz`
    end

    def cleanup_s3
      if AWS::S3::Bucket.find(bucket_name).size >= MAXIMUM_BACKUPS
        oldest = AWS::S3::Bucket.find(bucket_name).objects.first
        log "Removing oldest backup: #{oldest.key}"
        oldest.delete
      else
        log "No need to remove old backups"
      end
    end

    def bucket_name
      "APPNAME-dbbackups-#{Rails.env}"
    end
  end
end
