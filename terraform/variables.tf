variable "aws_region"{
    description = "AWS region to deploy into"
    type = string
    default = "us-east-1"
}

variable "lambda_zip_path"{
    description = "Path to zipped Lambda deployment package"
    type = string
    default = "../lambda/lambda.zip"
    }