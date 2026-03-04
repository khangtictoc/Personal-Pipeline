#!/bin/bash

# ─────────────────────────────────────────
# Velero S3 Bucket Access Grant Script
# Usage: ./grant-bucket-access.sh
# ─────────────────────────────────────────

# ── Config ────────────────────────────────
BUCKET_NAME="velero-backup-kubernetes-aws"
REGION="us-east-1"
# ─────────────────────────────────────────

# ── Input ─────────────────────────────────
read -p "Enter user ARN (e.g. arn:aws:iam::123456789:user/john): " USER_ARN

if [ -z "$USER_ARN" ]; then
  echo "❌ Error: USER_ARN cannot be empty"
  exit 1
fi

# Basic ARN format validation
if [[ ! "$USER_ARN" =~ ^arn:aws:iam::[0-9]{12}:(user|root|role)/.+ ]] && \
   [[ ! "$USER_ARN" =~ ^arn:aws:iam::[0-9]{12}:root$ ]]; then
  echo "❌ Error: Invalid ARN format"
  echo "   Expected: arn:aws:iam::123456789012:user/username"
  exit 1
fi

echo ""
read -p "Access mode - (1) ReadOnly  (2) ReadWrite [default: 1]: " ACCESS_MODE
ACCESS_MODE=${ACCESS_MODE:-1}

if [ "$ACCESS_MODE" == "1" ]; then
  ACTIONS='["s3:GetObject","s3:ListBucket","s3:GetBucketLocation"]'
  MODE_LABEL="ReadOnly"
elif [ "$ACCESS_MODE" == "2" ]; then
  ACTIONS='["s3:GetObject","s3:ListBucket","s3:GetBucketLocation","s3:PutObject","s3:DeleteObject"]'
  MODE_LABEL="ReadWrite"
else
  echo "❌ Invalid option. Choose 1 or 2."
  exit 1
fi

# ── Check existing policy ─────────────────
echo ""
echo "🔍 Checking existing bucket policy..."
EXISTING_POLICY=$(aws s3api get-bucket-policy \
  --bucket "$BUCKET_NAME" \
  --query Policy \
  --output text 2>/dev/null)

if [ -z "$EXISTING_POLICY" ]; then
  echo "   No existing policy found. Creating new one."
  # Build fresh policy
  POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "VeleroAccess-$(date +%s)",
      "Effect": "Allow",
      "Principal": {
        "AWS": "$USER_ARN"
      },
      "Action": $ACTIONS,
      "Resource": [
        "arn:aws:s3:::$BUCKET_NAME",
        "arn:aws:s3:::$BUCKET_NAME/*"
      ]
    }
  ]
}
EOF
)
else
  echo "   Existing policy found. Appending new statement."
  # Append new statement to existing policy
  NEW_STATEMENT=$(cat <<EOF
{
  "Sid": "VeleroAccess-$(date +%s)",
  "Effect": "Allow",
  "Principal": {
    "AWS": "$USER_ARN"
  },
  "Action": $ACTIONS,
  "Resource": [
    "arn:aws:s3:::$BUCKET_NAME",
    "arn:aws:s3:::$BUCKET_NAME/*"
  ]
}
EOF
)
  POLICY=$(echo "$EXISTING_POLICY" | jq \
    --argjson stmt "$NEW_STATEMENT" \
    '.Statement += [$stmt]')
fi

# ── Preview ───────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 Policy to be applied:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "$POLICY" | jq .
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Bucket  : $BUCKET_NAME"
echo "  User ARN: $USER_ARN"
echo "  Mode    : $MODE_LABEL"
echo ""
read -p "❓ Apply this policy? (y/n): " CONFIRM

if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
  echo "⏭️  Aborted. No changes made."
  exit 0
fi

# ── Apply policy ──────────────────────────
echo ""
echo "⏳ Applying bucket policy..."
aws s3api put-bucket-policy \
  --bucket "$BUCKET_NAME" \
  --policy "$POLICY"

if [ $? -eq 0 ]; then
  echo ""
  echo "✅ Done! Access granted."
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📌 Developer setup instructions:"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "  velero backup-location create shared \\"
  echo "    --provider aws \\"
  echo "    --bucket $BUCKET_NAME \\"
  echo "    --config region=$REGION \\"
  echo "    --access-mode $MODE_LABEL"
  echo ""
  echo "  velero backup get --storage-location shared"
  echo ""
else
  echo "❌ Failed to apply bucket policy. Check your AWS credentials and permissions."
  exit 1
fi
```

## What it does
```
1. Takes USER_ARN as input        → validates ARN format
2. Asks ReadOnly or ReadWrite     → builds correct S3 actions
3. Checks existing bucket policy  → appends instead of overwriting
4. Previews the policy            → asks confirmation before applying
5. Applies policy                 → prints developer setup instructions