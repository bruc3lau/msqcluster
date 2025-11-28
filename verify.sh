#!/bin/bash
set -e

echo "🔍 Starting Verification..."

# Get Pod Names
MASTER_POD=$(kubectl get pod -l app=mysql-master -o jsonpath="{.items[0].metadata.name}")
SLAVE_POD=$(kubectl get pod -l app=mysql-slave -o jsonpath="{.items[0].metadata.name}")
RABBITMQ_POD=$(kubectl get pod -l app=rabbitmq -o jsonpath="{.items[0].metadata.name}")

echo "✅ Found Pods:"
echo "   Master: $MASTER_POD"
echo "   Slave:  $SLAVE_POD"
echo "   Rabbit: $RABBITMQ_POD"

echo -e "\n---------------------------------------------------"
echo "🧪 1. Testing MySQL Replication"
echo "---------------------------------------------------"

# Create DB and Table on Master (ignore errors if they exist)
echo "📝 Creating test data on Master..."
kubectl exec $MASTER_POD -c mysql -- mysql -u root -prootpassword -e "CREATE DATABASE IF NOT EXISTS testdb; USE testdb; CREATE TABLE IF NOT EXISTS messages (id INT AUTO_INCREMENT PRIMARY KEY, content VARCHAR(255), created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP);" 2>/dev/null

# Insert Data
TEST_MSG="Verification Run $(date +%s)"
kubectl exec $MASTER_POD -c mysql -- mysql -u root -prootpassword -e "USE testdb; INSERT INTO messages (content) VALUES ('$TEST_MSG');" 2>/dev/null
echo "   Inserted: '$TEST_MSG'"

# Wait a moment for replication
sleep 1

# Read from Slave
echo "📖 Reading from Slave..."
RESULT=$(kubectl exec $SLAVE_POD -- mysql -u root -prootpassword -e "USE testdb; SELECT * FROM messages WHERE content='$TEST_MSG';")

if [[ "$RESULT" == *"$TEST_MSG"* ]]; then
  echo "✅ Replication Success! Found data on Slave."
else
  echo "❌ Replication Failed! Data not found on Slave."
  echo "   Debug: $RESULT"
fi

echo -e "\n---------------------------------------------------"
echo "🐰 2. Testing RabbitMQ Log Shipping"
echo "---------------------------------------------------"

# Check Queue Count
echo "📊 Checking 'retry_logs' queue..."
QUEUE_INFO=$(kubectl exec $RABBITMQ_POD -- rabbitmqctl list_queues | grep retry_logs || true)

if [[ -n "$QUEUE_INFO" ]]; then
  COUNT=$(echo $QUEUE_INFO | awk '{print $2}')
  echo "✅ Queue 'retry_logs' exists with $COUNT messages."
else
  echo "❌ Queue 'retry_logs' not found or empty."
fi

echo -e "\n---------------------------------------------------"
echo "🎉 Verification Complete"
