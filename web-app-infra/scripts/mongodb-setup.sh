#!/bin/bash

# Exit on any error
set -e

# Update system
sudo yum update -y

# Install MongoDB 4.4 (outdated version as requested)
echo "[mongodb-org-4.4]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/amazon/2/mongodb-org/4.4/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://www.mongodb.org/static/pgp/server-4.4.asc" | sudo tee /etc/yum.repos.d/mongodb-org-4.4.repo

sudo yum install -y mongodb-org

# Configure MongoDB data directory on additional EBS volume
sudo mkfs -t xfs /dev/xvdf
sudo mkdir -p /data/db
sudo mount /dev/xvdf /data/db
sudo chown -R mongod:mongod /data/db

# Add to fstab for persistent mounting
echo "/dev/xvdf /data/db xfs defaults 0 0" | sudo tee -a /etc/fstab

# Configure MongoDB to use new data directory and bind to all interfaces (insecure)
sudo tee /etc/mongod.conf > /dev/null <<EOF
systemLog:
  destination: file
  logAppend: true
  path: /var/log/mongodb/mongod.log

storage:
  dbPath: /data/db
  journal:
    enabled: true

processManagement:
  fork: true
  pidFilePath: /var/run/mongodb/mongod.pid
  timeZoneInfo: /usr/share/zoneinfo

net:
  port: 27017
  bindIp: 0.0.0.0

security:
  authorization: disabled
EOF

# Start and enable MongoDB
sudo systemctl start mongod
sudo systemctl enable mongod

# Install AWS CLI v2 for backups
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Create backup script
sudo tee /home/ec2-user/backup-mongodb.sh > /dev/null <<'EOF'
#!/bin/bash

# Configuration
S3_BUCKET="${s3_bucket}"
AWS_REGION="${region}"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="mongodb_backup_$DATE"
BACKUP_DIR="/tmp/$BACKUP_NAME"

# Create backup
echo "Starting MongoDB backup at $(date)"
mongodump --out "$BACKUP_DIR"

# Compress backup
echo "Compressing backup..."
tar -czf "/tmp/$BACKUP_NAME.tar.gz" -C /tmp "$BACKUP_NAME"

# Upload to S3
echo "Uploading backup to S3..."
aws s3 cp "/tmp/$BACKUP_NAME.tar.gz" "s3://$S3_BUCKET/" --region "$AWS_REGION"

# Cleanup local files
echo "Cleaning up local files..."
rm -rf "/tmp/$BACKUP_NAME"
rm -f "/tmp/$BACKUP_NAME.tar.gz"

echo "Backup completed successfully at $(date)"
EOF

sudo chmod +x /home/ec2-user/backup-mongodb.sh
sudo chown ec2-user:ec2-user /home/ec2-user/backup-mongodb.sh

# Schedule daily backups at 2 AM
(sudo crontab -l 2>/dev/null; echo "0 2 * * * /home/ec2-user/backup-mongodb.sh >> /var/log/mongodb-backup.log 2>&1") | sudo crontab -

# Create restore script
sudo tee /home/ec2-user/restore-mongodb.sh > /dev/null <<'EOF'
#!/bin/bash

if [ $# -eq 0 ]; then
    echo "Usage: $0 <backup-filename>"
    echo "Available backups:"
    aws s3 ls s3://${s3_bucket}/ --region ${region}
    exit 1
fi

BACKUP_FILE="$1"
S3_BUCKET="${s3_bucket}"
AWS_REGION="${region}"

# Download backup from S3
echo "Downloading backup from S3..."
aws s3 cp "s3://$S3_BUCKET/$BACKUP_FILE" "/tmp/$BACKUP_FILE" --region "$AWS_REGION"

# Extract backup
echo "Extracting backup..."
tar -xzf "/tmp/$BACKUP_FILE" -C /tmp/

# Get directory name (remove .tar.gz extension)
BACKUP_DIR="/tmp/$(basename "$BACKUP_FILE" .tar.gz)"

# Restore MongoDB
echo "Restoring MongoDB..."
mongorestore --drop "$BACKUP_DIR"

# Cleanup
echo "Cleaning up..."
rm -rf "$BACKUP_DIR"
rm -f "/tmp/$BACKUP_FILE"

echo "Restore completed successfully!"
EOF

sudo chmod +x /home/ec2-user/restore-mongodb.sh
sudo chown ec2-user:ec2-user /home/ec2-user/restore-mongodb.sh

# Create MongoDB status check script
sudo tee /home/ec2-user/mongodb-status.sh > /dev/null <<'EOF'
#!/bin/bash

echo "=== MongoDB Status ==="
sudo systemctl status mongod

echo -e "\n=== MongoDB Connection Test ==="
mongo --eval "db.adminCommand('ismaster')"

echo -e "\n=== Disk Usage ==="
df -h /data/db

echo -e "\n=== Recent Backup Logs ==="
tail -n 10 /var/log/mongodb-backup.log 2>/dev/null || echo "No backup logs found"
EOF

sudo chmod +x /home/ec2-user/mongodb-status.sh
sudo chown ec2-user:ec2-user /home/ec2-user/mongodb-status.sh

echo "MongoDB setup completed successfully!"
echo "MongoDB is running on port 27017 (accessible from anywhere - INSECURE)"
echo "Backups are scheduled daily at 2 AM"
echo "Use /home/ec2-user/mongodb-status.sh to check status"
echo "Use /home/ec2-user/restore-mongodb.sh <backup-file> to restore from backup"