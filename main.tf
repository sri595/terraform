terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# ---------------------
# IAM role for Lambda (trust policy)
# ---------------------
resource "aws_iam_role" "lambda_exec" {
  name = "tf_python_lambda_execution_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

# Attach AWS managed policy to allow Lambda to write logs
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ---------------------
# Lambda function
# ---------------------
resource "aws_lambda_function" "python_lambda" {
  function_name    = "tf_python_lambda_example"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "lambda_function.handler"
  runtime          = "python3.11"
  filename         = "lambda.zip"
  source_code_hash = filebase64sha256("lambda.zip")
  publish          = true
  timeout          = 10
  memory_size      = 128
}

# ---------------------
# API Gateway REST API
# ---------------------
# 1) REST API
resource "aws_api_gateway_rest_api" "api" {
  name        = "tf_python_lambda_api"
  description = "REST API to invoke python lambda"
}

# 2) Resource: /invokeLamdaApi (child of root)
resource "aws_api_gateway_resource" "invoke_resource" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "invokeLamdaApi"
}

# 3) Method: GET /invokeLamdaApi (no auth)
resource "aws_api_gateway_method" "get_invoke" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.invoke_resource.id
  http_method   = "GET"
  authorization = "NONE"
}

# 4) Integration: Lambda proxy integration (API Gateway -> Lambda)
resource "aws_api_gateway_integration" "get_invoke_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.invoke_resource.id
  http_method             = aws_api_gateway_method.get_invoke.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "arn:aws:apigateway:${var.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.python_lambda.arn}/invocations"
}

# ---------------------
# Permission: allow API Gateway to invoke Lambda
# ---------------------
resource "aws_lambda_permission" "apigw_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.python_lambda.function_name
  principal     = "apigateway.amazonaws.com"

  # Restrict to our API's GET /invokeLamdaApi
  source_arn = "${aws_api_gateway_rest_api.api.execution_arn}/*/GET/invokeLamdaApi"
}

# ---------------------
# Deployment and stage
# ---------------------
resource "aws_api_gateway_deployment" "deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = "prod"

  # Force redeploy when lambda code changes
  triggers = {
    redeploy = aws_lambda_function.python_lambda.source_code_hash
  }

  depends_on = [
    aws_api_gateway_integration.get_invoke_integration,
    aws_lambda_permission.apigw_invoke
  ]
}
