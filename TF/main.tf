############################
# S3 para artifacts
############################
resource "aws_s3_bucket" "artifacts" {
  bucket        = "dupla-artifacts-${var.account_id}-${var.region}"
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  versioning_configuration { status = "Enabled" }
}

############################
# ECR
############################
resource "aws_ecr_repository" "app" {
  name                 = var.ecr_repo_name
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration { scan_on_push = true }
}

############################
# IAM - CodePipeline
############################
data "aws_iam_policy_document" "codepipeline_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["codepipeline.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "codepipeline" {
  name               = "dupla-codepipeline-role"
  assume_role_policy = data.aws_iam_policy_document.codepipeline_trust.json
}

data "aws_iam_policy_document" "codepipeline_policy" {
  statement {
    sid      = "S3Artifacts"
    actions  = ["s3:GetObject","s3:GetObjectVersion","s3:PutObject","s3:ListBucket"]
    resources = [
      aws_s3_bucket.artifacts.arn,
      "${aws_s3_bucket.artifacts.arn}/*"
    ]
  }

  statement {
    sid      = "CodeBuild"
    actions  = ["codebuild:BatchGetBuilds","codebuild:StartBuild","codebuild:StartBuildBatch"]
    resources = ["*"]
  }

  statement {
    sid      = "CodeStarUse"
    actions  = ["codestar-connections:UseConnection"]
    resources = [var.codestar_connection_arn]
  }

  statement {
    sid      = "PassRole"
    actions  = ["iam:PassRole"]
    resources = ["arn:aws:iam::${var.account_id}:role/service-role/codebuild-asn-demo-lab-service-role"]
  }
}

resource "aws_iam_policy" "codepipeline" {
  name   = "dupla-codepipeline-policy"
  policy = data.aws_iam_policy_document.codepipeline_policy.json
}

resource "aws_iam_role_policy_attachment" "codepipeline_attach" {
  role       = aws_iam_role.codepipeline.name
  policy_arn = aws_iam_policy.codepipeline.arn
}

############################
# CodeBuild: usar role FIXA
############################
data "aws_iam_role" "codebuild_fixed" {
  name = "service-role/codebuild-asn-demo-lab-service-role"
}

# Anexos mínimos para build/deploy (se ainda não existirem)
resource "aws_iam_role_policy_attachment" "cb_ecr" {
  role       = data.aws_iam_role.codebuild_fixed.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}

resource "aws_iam_role_policy_attachment" "cb_logs" {
  role       = data.aws_iam_role.codebuild_fixed.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

resource "aws_iam_role_policy_attachment" "cb_s3" {
  role       = data.aws_iam_role.codebuild_fixed.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_role_policy_attachment" "cb_eks" {
  role       = data.aws_iam_role.codebuild_fixed.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

############################
# CodeBuild Projects
############################
resource "aws_codebuild_project" "build" {
  name         = "dupla-build"
  service_role = data.aws_iam_role.codebuild_fixed.arn

  artifacts { type = "CODEPIPELINE" }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/standard:7.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = true

    environment_variable { 
        name = "ECR_REPO"           
        value = aws_ecr_repository.app.repository_url 
    }
    environment_variable { 
        name = "COMPONENT"          
        value = "todo-frontend" 
    }
    environment_variable { 
        name = "AWS_DEFAULT_REGION" 
        value = var.region 
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspec-build.yml"
  }

  logs_config {
    cloudwatch_logs { group_name = "/codebuild/dupla-build" }
  }

  tags = { dupla = "ccbc-rmf2", periodo = "8" }
}

resource "aws_codebuild_project" "deploy" {
  name         = "dupla-deploy"
  service_role = data.aws_iam_role.codebuild_fixed.arn

  artifacts { type = "CODEPIPELINE" }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/standard:7.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = false

    environment_variable { 
        name = "EKS_CLUSTER_NAME"   
        value = var.eks_cluster_name 
    }
    environment_variable { 
        name = "AWS_DEFAULT_REGION" 
        value = var.region 
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspec-deploy.yml"
  }

  logs_config {
    cloudwatch_logs { group_name = "/codebuild/dupla-deploy" }
  }

  tags = { dupla = "ccbc-rmf2", periodo = "8" }
}

############################
# CodePipeline
############################
resource "aws_codepipeline" "pipeline" {
  name     = "dupla-ci-cd"
  role_arn = aws_iam_role.codepipeline.arn

  artifact_store {
    location = aws_s3_bucket.artifacts.bucket
    type     = "S3"
  }

  stage {
    name = "Source"
    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_output"]
      configuration = {
        ConnectionArn        = var.codestar_connection_arn
        FullRepositoryId     = "${var.github_owner}/${var.repo_name}"
        BranchName           = var.branch
        OutputArtifactFormat = "CODE_ZIP"
      }
    }
  }

  stage {
    name = "Build"
    action {
      name             = "BuildImage"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]
      version          = "1"
      configuration = {
        ProjectName = aws_codebuild_project.build.name
      }
    }
  }

  stage {
    name = "Deploy"
    action {
      name            = "DeployToEKS"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      input_artifacts = ["build_output"]
      version         = "1"
      configuration = {
        ProjectName = aws_codebuild_project.deploy.name
      }
    }
  }

  tags = { dupla = "ccbc-rmf2", periodo = "8" }
}
