resource "aws_iam_role" "tf_codepipeline_role" {
  name = var.tf_codepipeline_role

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "codepipeline.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

data "aws_iam_policy_document" "tf_cicd_pipeline_policies" {
  statement {
    sid       = ""
    actions   = ["codestar-connections:UseConnection"]
    resources = ["*"]
    effect    = "Allow"
  }
  statement {
    sid       = ""
    actions   = ["cloudwatch:*", "s3:*", "sns:Publish", "dynamodb:*", "codebuild:*"]
    resources = ["*"]
    effect    = "Allow"
  }
}

resource "aws_iam_policy" "tf_cicd_pipeline_policy" {
  name        = var.tf_codepipeline_policy
  path        = "/"
  description = "Pipeline policy"
  policy      = data.aws_iam_policy_document.tf_cicd_pipeline_policies.json
}

resource "aws_iam_role_policy_attachment" "tf-cicd-pipeline-attachment" {
  policy_arn = aws_iam_policy.tf_cicd_pipeline_policy.arn
  role       = aws_iam_role.tf_codepipeline_role.id
}


resource "aws_iam_role" "tf_codebuild_role" {
  name = var.tf_codebuild_role

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "codebuild.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF

}

data "aws_iam_policy_document" "tf_cicd_build_policies" {
  statement {
    sid       = ""
    actions   = ["logs:*", "s3:*", "codebuild:*", "secretsmanager:*", "iam:*"]
    resources = ["*"]
    effect    = "Allow"
  }
}

resource "aws_iam_policy" "tf_cicd_build_policy" {
  name        = var.tf_codebuild_policy
  path        = "/"
  description = "Codebuild policy"
  policy      = data.aws_iam_policy_document.tf_cicd_build_policies.json
}

resource "aws_iam_role_policy_attachment" "tf_cicd_codebuild_attachment1" {
  policy_arn = aws_iam_policy.tf_cicd_build_policy.arn
  role       = aws_iam_role.tf_codebuild_role.id
}

resource "aws_iam_role_policy_attachment" "tf_cicd_codebuild_attachment2" {
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
  role       = aws_iam_role.tf_codebuild_role.id
}

resource "aws_codebuild_project" "tf_plan" {
  name         = "tf-cicd-plan"
  description  = "Plan stage for terraform"
  service_role = aws_iam_role.tf_codebuild_role.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "hashicorp/terraform:1.1.4"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "SERVICE_ROLE"
    registry_credential {
      credential          = var.dockerhub_credentials
      credential_provider = "SECRETS_MANAGER"
    }
  }
  source {
    type      = "CODEPIPELINE"
    buildspec = file("../../envs/${var.environment}/buildspec/plan-buildspec.yml")
  }

  tags = merge({
    env = var.environment
  }, var.tags)
}

resource "aws_codebuild_project" "tf-apply" {
  name         = "tf-cicd-apply"
  description  = "Apply stage for terraform"
  service_role = aws_iam_role.tf_codebuild_role.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "hashicorp/terraform:1.1.4"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "SERVICE_ROLE"
    registry_credential {
      credential          = var.dockerhub_credentials
      credential_provider = "SECRETS_MANAGER"
    }
  }
  source {
    type      = "CODEPIPELINE"
    buildspec = file("../../envs/${var.environment}/buildspec/apply-buildspec.yml")
  }

  tags = merge({
    env = var.environment
  }, var.tags)
}


resource "aws_codepipeline" "cicd_pipeline" {

  name     = "tf-cicd"
  role_arn = aws_iam_role.tf_codepipeline_role.arn

  artifact_store {
    type     = "S3"
    location = aws_s3_bucket.codepipeline_artifacts.id
  }

  stage {
    name = "Source"
    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["tf-code"]
      configuration = {
        FullRepositoryId     = var.git_repo_id
        BranchName           = "master"
        ConnectionArn        = var.codestar_connector_credentials
        OutputArtifactFormat = "CODE_ZIP"
      }
    }
  }

  stage {
    name = "Plan"
    action {
      name            = "Build"
      category        = "Build"
      provider        = "CodeBuild"
      version         = "1"
      owner           = "AWS"
      input_artifacts = ["tf-code"]
      configuration = {
        ProjectName = "tf-cicd-plan"
      }
    }
  }

  stage {
    name = "Approve"

    action {
      name     = "Approval"
      category = "Approval"
      owner    = "AWS"
      provider = "Manual"
      version  = "1"

      configuration = {
        CustomData      = var.cicd_approval_message
        NotificationArn = aws_sns_topic.cicd_topic.arn
      }
    }
  }

  stage {
    name = "Deploy"
    action {
      name            = "Deploy"
      category        = "Build"
      provider        = "CodeBuild"
      version         = "1"
      owner           = "AWS"
      input_artifacts = ["tf-code"]
      configuration = {
        ProjectName = "tf-cicd-apply"
      }
    }
  }

  tags = merge({
    env = var.environment
  }, var.tags)
}

resource "aws_s3_bucket" "codepipeline_artifacts" {
  bucket = var.cicd_artefacts_bucket_name

  tags = merge({
    env = var.environment
  }, var.tags)
}

resource "aws_s3_bucket_acl" "codepipeline_artifacts" {
  bucket = aws_s3_bucket.codepipeline_artifacts.id
  acl    = "private"
}

resource "aws_sns_topic" "cicd_topic" {
  name = var.cicd_sns_topic_name
}

resource "aws_sns_topic_subscription" "email-target" {
  topic_arn = aws_sns_topic.cicd_topic.arn
  protocol  = "email"
  endpoint  = var.cicd_approval_email
}