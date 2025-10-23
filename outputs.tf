output "lambda_function_name" {
  value = aws_lambda_function.python_lambda.function_name
}

output "lambda_function_arn" {
  value = aws_lambda_function.python_lambda.arn
}

output "api_invoke_url" {
  description = "Full invoke URL for GET /invokeLamdaApi on the prod stage"
  value = format(
    "https://%s.execute-api.%s.amazonaws.com/%s/%s",
    aws_api_gateway_rest_api.api.id,
    var.region,
    aws_api_gateway_deployment.deployment.stage_name,
    aws_api_gateway_resource.invoke_resource.path_part
  )
}
