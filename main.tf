#############################################################
# Brandon Vicedomini
# Onica DevOps Test
# Approach 2
# Completed 3/27/2020
#############################################################
provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

#############################################################
# DyanmoDB table.
#############################################################
resource "aws_dynamodb_table" "project-dynamodb-table" {
  name = "OnicaProjects"

  billing_mode   = "PROVISIONED"
  read_capacity  = 1
  write_capacity = 1
  hash_key       = "ProjectId"

  attribute {
    name = "ProjectId"
    type = "N"
  }

  attribute {
    name = "ProjectDueDate"
    type = "S"
  }

  attribute {
    name = "ProjectName"
    type = "S"
  }

  global_secondary_index {
    name               = "ProjectNameIndex"
    hash_key           = "ProjectName"
    range_key          = "ProjectDueDate"
    write_capacity     = 1
    read_capacity      = 1
    projection_type    = "INCLUDE"
    non_key_attributes = ["ProjectId"]
  }
}


#############################################################
# IAM for the Lambda function.
#############################################################
resource "aws_iam_role" "iam_for_lambda" {
  name = "iam_for_lambda"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": [
          "lambda.amazonaws.com",
          "apigateway.amazonaws.com"
        ]
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "dynamodb-lambda-policy" {
  name   = "dynamodb_lambda_policy"
  role   = aws_iam_role.iam_for_lambda.id
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:*"
      ],
      "Resource": "${aws_dynamodb_table.project-dynamodb-table.arn}"
    },
		{
			"Effect": "Allow",
			"Action": [
				"logs:CreateLogStream",
				"logs:PutLogEvents"
			],
			"Resource": "arn:aws:logs:${var.aws_region}:${var.aws_account_id}:*"
		},
		{
			"Effect": "Allow",
			"Action": "logs:CreateLogGroup",
			"Resource": "*"
		}
  ]
}
EOF
}


#############################################################
# Lambda functions.
#############################################################
resource "aws_lambda_function" "get-project-function" {
  filename         = "function.zip"
  function_name    = "getProject"
  role             = aws_iam_role.iam_for_lambda.arn
  handler          = "index.getProject"
  source_code_hash = filebase64sha256("function.zip")
  runtime          = "nodejs12.x"
  publish          = true
}

resource "aws_lambda_function" "get-project-list-function" {
  filename         = "function.zip"
  function_name    = "getProjectList"
  role             = aws_iam_role.iam_for_lambda.arn
  handler          = "index.getProjectList"
  source_code_hash = filebase64sha256("function.zip")
  runtime          = "nodejs12.x"
  publish          = true
}


#############################################################
# API Gateway.
#############################################################
#############################################################
# Get project list method. /project
#############################################################
resource "aws_api_gateway_rest_api" "project-api" {
  name        = "ProjectAPI"
  description = "API for Onica Projects"
}

resource "aws_api_gateway_resource" "get-project-list-resource" {
  rest_api_id = aws_api_gateway_rest_api.project-api.id
  parent_id   = aws_api_gateway_rest_api.project-api.root_resource_id
  path_part   = "project"
}

resource "aws_api_gateway_method" "get-project-list-method" {
  rest_api_id   = aws_api_gateway_rest_api.project-api.id
  resource_id   = aws_api_gateway_resource.get-project-list-resource.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "get-project-list-method-integration" {
  rest_api_id             = aws_api_gateway_rest_api.project-api.id
  resource_id             = aws_api_gateway_resource.get-project-list-resource.id
  http_method             = aws_api_gateway_method.get-project-list-method.http_method
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.get-project-list-function.invoke_arn
  integration_http_method = "POST"
}

resource "aws_api_gateway_deployment" "projects-deployment-dev" {
  depends_on = [
    aws_api_gateway_method.get-project-list-method,
    aws_api_gateway_integration.get-project-list-method-integration
  ]
  rest_api_id = aws_api_gateway_rest_api.project-api.id
  stage_name  = "dev"
}

resource "aws_api_gateway_deployment" "projects-deployment-prod" {
  depends_on = [
    aws_api_gateway_method.get-project-list-method,
    aws_api_gateway_integration.get-project-list-method-integration
  ]
  rest_api_id = aws_api_gateway_rest_api.project-api.id
  stage_name  = "prod"
}

resource "aws_lambda_permission" "get-project-list-lambda-permission" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get-project-list-function.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.aws_region}:${var.aws_account_id}:${aws_api_gateway_rest_api.project-api.id}/*/${aws_api_gateway_method.get-project-list-method.http_method}${aws_api_gateway_resource.get-project-list-resource.path}"
}

output "get_project_list_dev_url" {
  value = "https://${aws_api_gateway_deployment.projects-deployment-dev.rest_api_id}.execute-api.${var.aws_region}.amazonaws.com/${aws_api_gateway_deployment.projects-deployment-dev.stage_name}"
}

output "get_project_list_prod_url" {
  value = "https://${aws_api_gateway_deployment.projects-deployment-prod.rest_api_id}.execute-api.${var.aws_region}.amazonaws.com/${aws_api_gateway_deployment.projects-deployment-prod.stage_name}"
}


#############################################################
# Get project by id method. /project/5
#############################################################
resource "aws_api_gateway_resource" "get-project-resource" {
  rest_api_id = aws_api_gateway_rest_api.project-api.id
  parent_id   = aws_api_gateway_resource.get-project-list-resource.id
  path_part   = "{projectId}"
}

resource "aws_api_gateway_method" "get-project-method" {
  rest_api_id   = aws_api_gateway_rest_api.project-api.id
  resource_id   = aws_api_gateway_resource.get-project-resource.id
  http_method   = "GET"
  authorization = "NONE"

  request_parameters = {
    "method.request.path.projectId" = true
  }
}

resource "aws_api_gateway_integration" "get-project-method-integration" {
  rest_api_id             = aws_api_gateway_rest_api.project-api.id
  resource_id             = aws_api_gateway_resource.get-project-resource.id
  http_method             = aws_api_gateway_method.get-project-method.http_method
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.get-project-function.invoke_arn
  integration_http_method = "POST"
}

resource "aws_api_gateway_deployment" "get-project-deployment-dev" {
  depends_on = [
    aws_api_gateway_method.get-project-method,
    aws_api_gateway_integration.get-project-method-integration
  ]
  rest_api_id = aws_api_gateway_rest_api.project-api.id
  stage_name  = "dev"
}

resource "aws_api_gateway_deployment" "get-project-deployment-prod" {
  depends_on = [
    aws_api_gateway_method.get-project-method,
    aws_api_gateway_integration.get-project-method-integration
  ]
  rest_api_id = aws_api_gateway_rest_api.project-api.id
  stage_name  = "prod"
}

resource "aws_lambda_permission" "get-project-lambda-permission" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get-project-function.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.aws_region}:${var.aws_account_id}:${aws_api_gateway_rest_api.project-api.id}/*/${aws_api_gateway_method.get-project-method.http_method}${aws_api_gateway_resource.get-project-resource.path}"
}

output "get_project_dev_url" {
  value = "https://${aws_api_gateway_deployment.projects-deployment-dev.rest_api_id}.execute-api.${var.aws_region}.amazonaws.com/${aws_api_gateway_deployment.projects-deployment-dev.stage_name}"
}

output "get_project_prod_url" {
  value = "https://${aws_api_gateway_deployment.projects-deployment-prod.rest_api_id}.execute-api.${var.aws_region}.amazonaws.com/${aws_api_gateway_deployment.projects-deployment-prod.stage_name}"
}
