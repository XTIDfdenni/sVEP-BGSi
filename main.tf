provider "aws" {
  region = var.region
}

data "aws_caller_identity" "this" {}

locals {
  api_version = "v1.0.0"
  slice_size_mbp = 5
  result_suffix = "_results.tsv"
  result_duration = 86400
  # layers
  binaries_layer         = "${aws_lambda_layer_version.binaries_layer.layer_arn}:${aws_lambda_layer_version.binaries_layer.version}"
  // python_libraries_layer = module.python_libraries_layer.lambda_layer_arn
  python_modules_layer   = module.python_modules_layer.lambda_layer_arn
}

#
# initQuery Lambda Function
#
module "lambda-initQuery" {
  source = "github.com/bhosking/terraform-aws-lambda"

  function_name = "svep-backend-initQuery"
  description = "Invokes queryVCF with the calculated regions"
  handler = "lambda_function.lambda_handler"
  runtime = "python3.12"
  memory_size = 1792
  timeout = 28
  policy = {
    json = data.aws_iam_policy_document.lambda-initQuery.json
  }
  source_path = "${path.module}/lambda/initQuery"
  tags = var.common-tags

  environment ={
    variables = {
      CONCAT_STARTER_SNS_TOPIC_ARN = aws_sns_topic.concatStarter.arn
      QUERY_VCF_SNS_TOPIC_ARN = aws_sns_topic.queryVCF.arn
      RESULT_DURATION = local.result_duration
      RESULT_SUFFIX = local.result_suffix
      SLICE_SIZE_MBP = local.slice_size_mbp
      SVEP_TEMP = aws_s3_bucket.svep-temp.bucket
      HTS_S3_HOST = "s3.${var.region}.amazonaws.com"
    }
  }

  layers = [
    local.binaries_layer,
    local.python_modules_layer,
  ]
}

#
# queryVCF Lambda Function
#
module "lambda-queryVCF" {
  source = "github.com/bhosking/terraform-aws-lambda"

  function_name = "svep-backend-queryVCF"
  description = "Invokes queryGTF for each region."
  handler = "lambda_function.lambda_handler"
  runtime = "python3.12"
  memory_size = 2048
  timeout = 28
  policy = {
    json = data.aws_iam_policy_document.lambda-queryVCF.json
  }
  source_path = "${path.module}/lambda/queryVCF"
  tags = var.common-tags

  environment ={
    variables = {
      SVEP_TEMP = aws_s3_bucket.svep-temp.bucket
      QUERY_GTF_SNS_TOPIC_ARN = aws_sns_topic.queryGTF.arn
      QUERY_VCF_SNS_TOPIC_ARN = aws_sns_topic.queryVCF.arn
      QUERY_VCF_SUBMIT_SNS_TOPIC_ARN = aws_sns_topic.queryVCFsubmit.arn
      SLICE_SIZE_MBP = local.slice_size_mbp
      HTS_S3_HOST = "s3.${var.region}.amazonaws.com"
    }
  }

  layers = [
    local.binaries_layer,
    local.python_modules_layer,
  ]
}

#
# queryVCFsubmit Lambda Function
#
module "lambda-queryVCFsubmit" {
  source = "github.com/bhosking/terraform-aws-lambda"

  function_name = "svep-backend-queryVCFsubmit"
  description = "This lambda will be called if there are too many batchids to be processed within"
  handler = "lambda_function.lambda_handler"
  runtime = "python3.12"
  memory_size = 2048
  timeout = 28
  policy = {
    json = data.aws_iam_policy_document.lambda-queryVCFsubmit.json
  }
  source_path = "${path.module}/lambda/queryVCFsubmit"
  tags = var.common-tags

  environment ={
    variables = {
      SVEP_TEMP = aws_s3_bucket.svep-temp.bucket
      QUERY_GTF_SNS_TOPIC_ARN = aws_sns_topic.queryGTF.arn
      QUERY_VCF_SUBMIT_SNS_TOPIC_ARN = aws_sns_topic.queryVCFsubmit.arn
    }
  }

  layers = [
    local.python_modules_layer
  ]
}

#
# queryGTF Lambda Function
#
module "lambda-queryGTF" {
  source = "github.com/bhosking/terraform-aws-lambda"
  function_name = "svep-backend-queryGTF"
  description = "Queries GTF for a specified VCF regions."
  handler = "lambda_function.lambda_handler"
  runtime = "python3.12"
  memory_size = 2048
  timeout = 24
  policy = {
    json = data.aws_iam_policy_document.lambda-queryGTF.json
  }
  source_path = "${path.module}/lambda/queryGTF"
  tags = var.common-tags
  environment ={
    variables = {
      REFERENCE_LOCATION = aws_s3_bucket.svep-references.bucket
      SVEP_TEMP = aws_s3_bucket.svep-temp.bucket
      REFERENCE_GENOME = "sorted_filtered_Homo_sapiens.GRCh38.109.chr.gtf.gz"
      PLUGIN_CONSEQUENCE_SNS_TOPIC_ARN = aws_sns_topic.pluginConsequence.arn
      PLUGIN_UPDOWNSTREAM_SNS_TOPIC_ARN = aws_sns_topic.pluginUpdownstream.arn
      QUERY_GTF_SNS_TOPIC_ARN = aws_sns_topic.queryGTF.arn
      HTS_S3_HOST = "s3.${var.region}.amazonaws.com"
    }
  }

  layers = [
    local.binaries_layer,
    local.python_modules_layer,
  ]
}

#
# pluginConsequence Lambda Function
#
# TODO: update source to github.com/bhosking/terraform-aws-lambda once docker support is added
module "lambda-pluginConsequence" {
  source = "terraform-aws-modules/lambda/aws"

  function_name      = "svep-backend-pluginConsequence"
  description = "Queries VCF for a specified variant."
  create_package = false
  image_uri = module.docker_image_pluginConsequence_lambda.image_uri
  package_type = "Image"
  memory_size = 2048
  timeout = 60
  attach_policy_jsons = true
  policy_jsons = [
    data.aws_iam_policy_document.lambda-pluginConsequence.json
  ]
  number_of_policy_jsons = 1
  source_path = "${path.module}/lambda/pluginConsequence"
  tags = var.common-tags
  environment_variables = {
      SVEP_TEMP = aws_s3_bucket.svep-temp.bucket
      SVEP_REGIONS = aws_s3_bucket.svep-regions.bucket
      REFERENCE_LOCATION = aws_s3_bucket.svep-references.bucket
      SPLICE_REFERENCE = "sorted_splice_GRCh38.109.gtf.gz"
      MIRNA_REFERENCE = "sorted_filtered_mirna.gff3.gz" 
      HTS_S3_HOST = "s3.${var.region}.amazonaws.com"
  }
}

#
# pluginUpdownstream Lambda Function
#
module "lambda-pluginUpdownstream" {
  source = "github.com/bhosking/terraform-aws-lambda"
  function_name = "svep-backend-pluginUpdownstream"
  description = "Write upstream and downstream gene variant to temp bucket."
  handler = "lambda_function.lambda_handler"
  runtime = "python3.12"
  memory_size = 2048
  timeout = 24
  policy = {
    json = data.aws_iam_policy_document.lambda-pluginUpdownstream.json
  }
  source_path = "${path.module}/lambda/pluginUpdownstream"
  tags = var.common-tags
  environment ={
    variables = {
      SVEP_TEMP = aws_s3_bucket.svep-temp.bucket
      SVEP_REGIONS = aws_s3_bucket.svep-regions.bucket
      REFERENCE_LOCATION = aws_s3_bucket.svep-references.bucket
      REFERENCE_GENOME = "transcripts_Homo_sapiens.GRCh38.109.chr.gtf.gz"
      HTS_S3_HOST = "s3.${var.region}.amazonaws.com"
    }
  }

  layers = [
    local.binaries_layer,
    local.python_modules_layer,
  ]
}

#
# concat Lambda Function
#
module "lambda-concat" {
  source = "github.com/bhosking/terraform-aws-lambda"

  function_name = "svep-backend-concat"
  description = "Triggers createPages."
  handler = "lambda_function.lambda_handler"
  runtime = "python3.12"
  memory_size = 2048
  timeout = 28
  policy = {
    json = data.aws_iam_policy_document.lambda-concat.json
  }
  source_path = "${path.module}/lambda/concat"
  tags = var.common-tags

  environment ={
    variables = {
      SVEP_REGIONS = aws_s3_bucket.svep-regions.bucket
      CREATEPAGES_SNS_TOPIC_ARN = aws_sns_topic.createPages.arn
    }
  }

  layers = [
    local.python_modules_layer
  ]
}

#
# concatStarter Lambda Function
#
module "lambda-concatStarter" {
  source = "github.com/bhosking/terraform-aws-lambda"

  function_name = "svep-backend-concatStarter"
  description = "Validates all processing is done and triggers concat"
  handler = "lambda_function.lambda_handler"
  runtime = "python3.12"
  memory_size = 128
  timeout = 28
  policy = {
    json = data.aws_iam_policy_document.lambda-concatStarter.json
  }
  source_path = "${path.module}/lambda/concatStarter"
  tags = var.common-tags

  environment ={
    variables = {
      SVEP_TEMP = aws_s3_bucket.svep-temp.bucket
      SVEP_REGIONS = aws_s3_bucket.svep-regions.bucket
      CONCAT_SNS_TOPIC_ARN = aws_sns_topic.concat.arn
      CONCAT_STARTER_SNS_TOPIC_ARN = aws_sns_topic.concatStarter.arn
    }
  }

  layers = [
    local.python_modules_layer,
  ]
}

#
# createPages Lambda Function
#
module "lambda-createPages" {
  source = "github.com/bhosking/terraform-aws-lambda"

  function_name = "svep-backend-createPages"
  description = "concatenates individual page with 700 entries, received from concat lambda"
  handler = "lambda_function.lambda_handler"
  runtime = "python3.12"
  memory_size = 2048
  timeout = 28
  policy = {
    json = data.aws_iam_policy_document.lambda-createPages.json
  }
  source_path = "${path.module}/lambda/createPages"
  tags = var.common-tags

  environment ={
    variables = {
      SVEP_REGIONS = aws_s3_bucket.svep-regions.bucket
      SVEP_RESULTS = var.data_portal_bucket_name
      CONCATPAGES_SNS_TOPIC_ARN = aws_sns_topic.concatPages.arn
      CREATEPAGES_SNS_TOPIC_ARN = aws_sns_topic.createPages.arn
    }
  }

  layers = [
    local.python_modules_layer,
  ]
}

#
# concatPages Lambda Function
#
module "lambda-concatPages" {
  source = "github.com/bhosking/terraform-aws-lambda"

  function_name = "svep-backend-concatPages"
  description = "concatenates all the page files created by createPages lambda."
  handler = "lambda_function.lambda_handler"
  runtime = "python3.12"
  memory_size = 2048
  timeout = 28
  policy = {
    json = data.aws_iam_policy_document.lambda-concatPages.json
  }
  source_path = "${path.module}/lambda/concatPages"
  tags = var.common-tags

  environment ={
    variables = {
      RESULT_SUFFIX = local.result_suffix
      SVEP_REGIONS = aws_s3_bucket.svep-regions.bucket
      SVEP_RESULTS = var.data_portal_bucket_name
      CONCATPAGES_SNS_TOPIC_ARN = aws_sns_topic.concatPages.arn
    }
  }

  layers = [
    local.python_modules_layer
  ]
}

#
# getResultsURL Lambda Function
#
module "lambda-getResultsURL" {
  source = "github.com/bhosking/terraform-aws-lambda"

  function_name = "svep-backend-getResultsURL"
  description = "Returns the presigned results URL for results"
  handler = "lambda_function.lambda_handler"
  runtime = "python3.12"
  memory_size = 1792
  timeout = 28
  policy = {
    json = data.aws_iam_policy_document.lambda-getResultsURL.json
  }
  source_path = "${path.module}/lambda/getResultsURL"
  tags = var.common-tags

  environment ={
    variables = {
      REGION = var.region
      RESULT_DURATION = local.result_duration
      RESULT_SUFFIX = local.result_suffix
      SVEP_RESULTS = var.data_portal_bucket_name
    }
  }

  layers = [
    local.python_modules_layer,
  ]
}