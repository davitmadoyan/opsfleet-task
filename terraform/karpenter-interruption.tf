# Karpenter consumes Spot interruption / rebalance / health events from an
# SQS queue. EventBridge rules fan AWS events into the queue.

resource "aws_sqs_queue" "karpenter" {
  name                      = "${local.name}-karpenter-interruption"
  message_retention_seconds = 300
  sqs_managed_sse_enabled   = true
  tags                      = local.tags
}

data "aws_iam_policy_document" "karpenter_queue" {
  statement {
    sid       = "EventBridgeSend"
    effect    = "Allow"
    resources = [aws_sqs_queue.karpenter.arn]
    actions   = ["sqs:SendMessage"]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com", "sqs.amazonaws.com"]
    }
  }
}

resource "aws_sqs_queue_policy" "karpenter" {
  queue_url = aws_sqs_queue.karpenter.url
  policy    = data.aws_iam_policy_document.karpenter_queue.json
}

locals {
  karpenter_event_rules = {
    health_event = {
      name = "${local.name}-karpenter-health"
      pattern = jsonencode({
        source      = ["aws.health"]
        detail-type = ["AWS Health Event"]
      })
    }
    spot_interruption = {
      name = "${local.name}-karpenter-spot"
      pattern = jsonencode({
        source      = ["aws.ec2"]
        detail-type = ["EC2 Spot Instance Interruption Warning"]
      })
    }
    rebalance = {
      name = "${local.name}-karpenter-rebalance"
      pattern = jsonencode({
        source      = ["aws.ec2"]
        detail-type = ["EC2 Instance Rebalance Recommendation"]
      })
    }
    state_change = {
      name = "${local.name}-karpenter-state"
      pattern = jsonencode({
        source      = ["aws.ec2"]
        detail-type = ["EC2 Instance State-change Notification"]
      })
    }
  }
}

resource "aws_cloudwatch_event_rule" "karpenter" {
  for_each      = local.karpenter_event_rules
  name          = each.value.name
  event_pattern = each.value.pattern
  tags          = local.tags
}

resource "aws_cloudwatch_event_target" "karpenter" {
  for_each  = local.karpenter_event_rules
  rule      = aws_cloudwatch_event_rule.karpenter[each.key].name
  arn       = aws_sqs_queue.karpenter.arn
  target_id = "karpenter-${each.key}"
}
