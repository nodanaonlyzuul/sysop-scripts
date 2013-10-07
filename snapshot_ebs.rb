#!/usr/local/bin/ruby
require 'rubygems'
require 'optparse'
require 'timeout'
require 'AWS'

### sample roots crontab conf ###
#backout ebs volumn #vol-fb13f692
#1       2,14    *       *       *       /ebs-mnt/SlingItNginx/scripts/snap.sh &> /dev/null

################################################################################
options = OptionParser.new

options.on('-i', '--awsid=AWS ID', 'AWS ID (Required)' ) do |o|
  $aws_id = o
end

options.on('-d', '--name=some_name', 'description of the snapshot (Required)' ) do |o|
  $snapshot_description = o
end

options.on('-s', '--awskey=AWS Key', 'AWS Key (Required)' ) do |o|
  $aws_key = o
end

options.on('-v', '--volume=EBS Volume', 'EBS Volume (Required)') do |o|
  $volume = o
end

options.on('-m', '--mnt=mount point', 'Mount Point (Required)') do |o|
  $mount = o
end

options.on('-k', '--keep=number to keep', 'Snapshots to keep (Default 5)') do |o|
  $keep = o.to_i
end

$keep = 5 if $keep.nil?

options.parse!

unless $aws_id && $aws_key && $volume && $mount
  options.parse(["-h"])
  exit 1
end
################################################################################

ec2 = AWS::EC2::Base.new(:access_key_id => $aws_id, :secret_access_key => $aws_key)

begin
  # #freeze fs
  # puts "freezing #{$mount}"
  # `/usr/sbin/xfs_freeze -f #{$mount}`

  begin
    #create shapshot
    # Don't take longer than 5 seconds
    Timeout::timeout(5) do
      today       = Time.now
      description = "#{$snapshot_description}_#{today.strftime('%Y_%m_%d')}"
      puts "creating snapshot of #{$volume}"
      ec2.create_snapshot(:volume_id => $volume, :description => description, :name => description)
    end
  rescue Timeout::Error
    puts "Too slow"
  end

rescue Exception => e
  puts e
ensure
  # #unfreeze fs
  # puts "un-freezing #{$mount}"
  # `/usr/sbin/xfs_freeze -u #{$mount}`
end

#keep last 5 snapshots
completed_snap_shots = []
ec2.describe_snapshots.snapshotSet.item.each do |snapshot|
  if snapshot.volumeId == $volume && snapshot.status == "completed"
    completed_snap_shots.push snapshot
  end
end

if completed_snap_shots.length > $keep
  completed_snap_shots.sort_by { |ss| ss["startTime"] }[0..-($keep+1)].each do |snapshot|
    puts "deleting snapshot #{snapshot['snapshotId']}"
    ec2.delete_snapshot( :snapshot_id => snapshot['snapshotId'] )
  end
end
