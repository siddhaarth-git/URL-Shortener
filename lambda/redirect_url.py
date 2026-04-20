import json
import boto3

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('url-shortner')

def lambda_handler(event, context):
    try:
        short_code = event['pathParameters']['short_code']

        response = table.get_item(Key={'short_code': short_code})

        if 'Item' not in response:
            return {
                'statusCode': 404,
                'body': json.dumps({'error': 'URL not found'})
            }

        long_url = response['Item']['long_url']

        return {
            'statusCode': 301,
            'headers': {'Location': long_url},
            'body': ''
        }

    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }