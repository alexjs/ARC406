#!/bin/bash

############
# Config options here.
# Please also remember to set an IAM role on the instance in question
# Sample policy for that role contained within this repo
# https://github.com/alexjs/CTD303
############

mountPoint="/opt/myAppName/var/run"
devicePoint="xvdz" # We start from the top down rather than bottom up to avoid conflicts
volumeType="gp2" # standard | io1 | gp2 | sc1 | st1
minSize="2" # Size in GiB - must be greater than 0
maxSize="5" # Size in GiB
fsType="ext4" # We assume the existence of mkfs.${fsType}


# Check the mountPoint to see whether anything's mounted there now. If there is, abort
grep ${mountPoint} /etc/mtab
if [[ ${?} -eq 0 ]]; then
	echo "${mountPoint} already has something mounted. Please check and try again"
	exit 0
fi

# Make sure the mountPoint is a valid directory

mkdir -p ${mountPoint}

# Grab the region, AZ and Instance ID
availabilityZone=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
region=${availabilityZone:0:-1}
instanceId=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)



# Calculate a size for the EBS volume - randomly between min/max
volumeSize=$(( ( RANDOM % ${maxSize} )  + ${minSize} ))

# Create the volume
# This assumes the instance has the rights to create an EBS volume
# Please always remember to use roles rather than hardcoded permissions
# Sample role policy available in the same repo (https://github.com/alexjs/ARC406)

volumeId=$(aws ec2 create-volume --region ${region} --availability-zone ${availabilityZone} \
	--volume-type ${volumeType} --size ${volumeSize} --output text \
	| awk '{print $7}') # Maybe we should have a better way of grabbing the vol ID

# Wait for it to come online

checkVolume () {
	volumeState=$(aws ec2 describe-volumes --region ap-southeast-1 \
		--volume ${volumeId} --output text | awk '{print $7}')
}

checkVolume

until [[ ${volumeState} == 'available' ]]; do
	sleep 2
	checkVolume
done


# And now attach

aws ec2 attach-volume --region ${region} --volume-id ${volumeId} \
	--instance-id ${instanceId} --device ${devicePoint}

# Wait for it to be attached...

until [[ -b "/dev/${devicePoint}" ]]; do
	sleep 1
done

# mkfs

mkfs.${fsType} /dev/${devicePoint}

# Mount

mount /dev/${devicePoint} ${mountPoint}

