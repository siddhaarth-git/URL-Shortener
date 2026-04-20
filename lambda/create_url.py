import json
import boto3
import string
import random

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('url-shortner')

def generate_short_code(length=6):
    characters = string.ascii_letters + string.digits
    return ''.join(random.choices(characters, k=length))

def lambda_handler(event, context):
    try:
        body = json.loads(event['body'])
        long_url = body['long_url']

        short_code = generate_short_code()

        table.put_item(Item={
            'short_code': short_code,
            'long_url': long_url
        })

        return {
            'statusCode': 200,
            'body': json.dumps({
                'short_code': short_code,
                'short_url': f"https://wt23w0da4b.execute-api.us-east-1.amazonaws.com/{short_code}"
            })
        }

    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }