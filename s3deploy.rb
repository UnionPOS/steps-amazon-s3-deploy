# --------------------------
# --- Gems
# --------------------------
require 'bundler/inline'

gemfile do
  source 'https://rubygems.org'
  gem 'ipa_install_plist_generator'
end

puts 'Gems installed and loaded!'

# --------------------------
# --- Constants & Variables
# --------------------------

@this_script_path = File.expand_path(File.dirname(__FILE__))

# --------------------------
# --- Functions
# --------------------------

def log_fail(message)
  puts
  puts "\e[31m#{message}\e[0m"
  exit(1)
end

def log_warn(message)
  puts "\e[33m#{message}\e[0m"
end

def log_info(message)
  puts
  puts "\e[34m#{message}\e[0m"
end

def log_details(message)
  puts "  #{message}"
end

def log_done(message)
  puts "  \e[32m#{message}\e[0m"
end

def s3_object_uri_for_bucket_and_path(bucket_name, path_in_bucket)
  return "s3://#{bucket_name}/#{path_in_bucket}".gsub(" ", "+")
end

def public_url_for_bucket_and_path(bucket_name, bucket_region, path_in_bucket)
  if bucket_region.to_s == '' || bucket_region.to_s == 'us-east-1'
    return "https://s3.amazonaws.com/#{bucket_name}/#{path_in_bucket}".gsub(" ", "_")
  end

  return "https://s3-#{bucket_region}.amazonaws.com/#{bucket_name}/#{path_in_bucket}".gsub(" ", "+")
end

def export_output(out_key, out_value)
  IO.popen("envman add --key #{out_key.to_s}", 'r+') { |f|
    f.write(out_value.to_s)
    f.close_write
    f.read
  }
end

def do_s3upload(sourcepth, full_destpth, aclstr)
  return system(%Q{aws s3 cp "#{sourcepth}" "#{full_destpth}" --acl "#{aclstr}"})
end

# -----------------------
# --- Main
# -----------------------

options = {
  ipa: ENV['ipa_path'],
  dsym: ENV['dsym_path'],
  access_key: ENV['aws_access_key'],
  secret_key: ENV['aws_secret_key'],
  bucket_name: ENV['bucket_name'],
  bucket_region: ENV['bucket_region'],
  path_in_bucket: ENV['path_in_bucket'],
  acl: ENV['file_access_level'],
  build_number: ENV['build_number'],
  app_name: ENV['app_name'],
  bundle_id: ENV['bundle_id'],
  bundle_version: ENV['bundle_version'],
  app_icon_url: ENV['app_icon_url'],
  itunes_icon_url: ENV['itunes_icon_url']
}

#
# Print options
log_info('Configs:')
log_details("* ipa_path: #{options[:ipa]}")
log_details("* dsym_path: #{options[:dsym]}")

log_details('* aws_access_key: ') if options[:access_key].to_s == ''
log_details('* aws_access_key: ***') unless options[:access_key].to_s == ''

log_details('* aws_secret_key: ') if options[:secret_key].to_s == ''
log_details('* aws_secret_key: ***') unless options[:secret_key].to_s == ''

log_details("* bucket_name: #{options[:bucket_name]}")
log_details("* bucket_region: #{options[:bucket_region]}")
log_details("* path_in_bucket: #{options[:path_in_bucket]}")
log_details("* file_access_level: #{options[:acl]}")

log_details("* build_number: #{options[:build_number]}")
log_details("* app_name: #{options[:app_name]}")
log_details("* bundle_id: #{options[:bundle_id]}")
log_details("* bundle_version: #{options[:bundle_version]}")
log_details("* app_icon_url: #{options[:app_icon_url]}")
log_details("* itunes_icon_url: #{options[:itunes_icon_url]}")

status = 'success'
begin
  #
  # Validate options
  fail 'No IPA found to deploy. Terminating.' unless File.exist?(options[:ipa])

  unless File.exist?(options[:dsym])
    options[:dsym] = nil
    log_warn("DSYM file not found. To generate debug symbols (dSYM) go to your Xcode Project's Settings - Build Settings - Debug Information Format and set it to DWARF with dSYM File.")
  end

  fail 'Missing required input: aws_access_key' if options[:access_key].to_s.eql?('')
  fail 'Missing required input: aws_secret_key' if options[:secret_key].to_s.eql?('')

  fail 'Missing required input: bucket_name' if options[:bucket_name].to_s.eql?('')
  fail 'Missing required input: file_access_level' if options[:acl].to_s.eql?('')

  fail 'Missing required input: build_number' if options[:build_number].to_s.eql?('')
  fail 'Missing required input: app_name' if options[:app_name].to_s.eql?('')
  fail 'Missing required input: bundle_id' if options[:bundle_id].to_s.eql?('')
  fail 'Missing required input: bundle_version' if options[:bundle_version].to_s.eql?('')
  fail 'Missing required input: app_icon_url' if options[:app_icon_url].to_s.eql?('')
  fail 'Missing required input: itunes_icon_url' if options[:itunes_icon_url].to_s.eql?('')

  #
  # AWS configs
  ENV['AWS_ACCESS_KEY_ID'] = options[:access_key]
  ENV['AWS_SECRET_ACCESS_KEY'] = options[:secret_key]
  ENV['AWS_DEFAULT_REGION'] = options[:bucket_region] unless options[:bucket_region].to_s.eql?('')

  #
  # define object path
  plist_upload_name = "#{options[:app_name]}.#{options[:build_number]}.ipa"
  base_path_in_bucket = ''
  if options[:path_in_bucket]
    base_path_in_bucket = options[:path_in_bucket]
    ipa_path_in_bucket = "#{base_path_in_bucket}/#{plist_upload_name}"
  else
    ipa_path_in_bucket = "#{plist_upload_name}"
  end

  #
  # supported: private, public_read
  acl_arg = 'public-read'
  if options[:acl]
    case options[:acl]
    when 'public_read'
      acl_arg = 'public-read'
    when 'private'
      acl_arg = 'private'
    else
      fail "Invalid ACL option: #{options[:acl]}"
    end
  end

  #
  # ipa upload
  log_info('Uploading IPA...')

  ipa_full_s3_path = s3_object_uri_for_bucket_and_path(options[:bucket_name], ipa_path_in_bucket)
  public_url_ipa = public_url_for_bucket_and_path(options[:bucket_name], options[:bucket_region], ipa_path_in_bucket)

  fail 'Failed to upload IPA' unless do_s3upload(options[:ipa], ipa_full_s3_path, acl_arg)

  export_output('S3_DEPLOY_STEP_URL_IPA', public_url_ipa)

  log_done('IPA upload success')

  #
  # dsym upload
  if options[:dsym]
    log_info('Uploading dSYM...')

    dsym_path_in_bucket = "#{base_path_in_bucket}/#{File.basename(options[:dsym])}"
    dsym_full_s3_path = s3_object_uri_for_bucket_and_path(options[:bucket_name], dsym_path_in_bucket)
    public_url_dsym = public_url_for_bucket_and_path(options[:bucket_name], options[:bucket_region], dsym_path_in_bucket)

    fail 'Failed to upload dSYM' unless do_s3upload(options[:dsym], dsym_full_s3_path, acl_arg)

    export_output('S3_DEPLOY_STEP_URL_DSYM', public_url_dsym)

    log_done('dSYM upload success')
  end

  ENV['S3_DEPLOY_STEP_URL_IPA'] = "#{public_url_ipa}"

  #
  # plist generation - we have to run it after we have obtained the public url to the ipa
  log_info('Generating Deploy Info.plist...')

  app_name=options[:app_name]
  bundle_id=options[:bundle_id]
  bundle_version=options[:bundle_version]
  app_icon_url=options[:app_icon_url]
  itunes_icon_url=options[:itunes_icon_url]
  build_number=options[:build_number]
  plist=IpaInstallPlistGenerator::PlistGenerator.new.generate_plist_string(public_url_ipa, bundle_id, app_name, bundle_version, app_icon_url, itunes_icon_url)

  plist_file="#{app_name}.#{build_number}.plist"
  File.open("#{plist_file}", "w") do |f|
    f.write(plist)
  end

  log_done("Generating #{plist_file} succeeded")

  #
  # plist upload
  plist_local_path = "./#{plist_file}"
  public_url_plist = ''

  if File.exist?(plist_local_path)
    log_info("Uploading #{plist_file}...")

    plist_path_in_bucket = "#{base_path_in_bucket}/#{plist_file}"
    plist_full_s3_path = s3_object_uri_for_bucket_and_path(options[:bucket_name], plist_path_in_bucket)
    public_url_plist = public_url_for_bucket_and_path(options[:bucket_name], options[:bucket_region], plist_path_in_bucket)

    fail "Failed to upload #{plist_file}" unless do_s3upload(plist_local_path, plist_full_s3_path, acl_arg)

    log_done("#{plist_file} upload success")
  else
    log_warn('NO Info.plist generated :<')
  end
  export_output('S3_DEPLOY_STEP_URL_PLIST', public_url_plist)

  email_ready_link_url = "itms-services://?action=download-manifest&url=#{public_url_plist}"
  export_output('S3_DEPLOY_STEP_EMAIL_READY_URL', email_ready_link_url)

  #
  # Print deploy infos
  log_info 'Deploy infos:'
  log_details("* Access Level: #{options[:acl]}")
  log_details("* IPA: #{public_url_ipa}")

  if options[:dsym]
    log_details("* DSYM: #{public_url_dsym}")
  else
    log_warn("%Q{DSYM file not found.
      To generate debug symbols (dSYM) go to your
      Xcode Project's Settings - `Build Settings - Debug Information Format`
      and set it to **DWARF with dSYM File**.}")
  end

  log_details("* Plist: #{public_url_plist}")

  log_info('Install link:')
  log_details("#{email_ready_link_url}")

  puts
  log_details('Open this link on an iOS device to install the app')

rescue => ex
  status = 'failed'
  log_fail("#{ex}")
ensure
  export_output('S3_DEPLOY_STEP_STATUS', status)
  puts
  log_done("#{status}")
end
