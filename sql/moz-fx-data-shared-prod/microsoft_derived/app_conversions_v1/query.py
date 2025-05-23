"""microsoft_store data - download deliverables, clean and upload to BigQuery."""

import csv
import json
import os
import re
import tempfile
from argparse import ArgumentParser
from time import sleep

import requests
from google.cloud import bigquery

API_URI = "https://manage.devcenter.microsoft.com"

"""MICROSOFT_STORE_APP_LIST is a list of dictionaries.
Keys are the app_name, and app_tenant_id in the form:
{"app_name":"<specific_app_name from Microsoft Store", "tenant_id":"<unique Microsoft tenant_id"}
Look here to see the apps we are tracking: https://partner.microsoft.com/en-us/dashboard/insights/analytics/reports/summary
"""
CSV_FIELDS = [
    "date",
    "application_id",
    "application_name",
    "custom_campaign_id",
    "referrer_uri_domain",
    "channel_type",
    "store_client",
    "device_type",
    "market",
    "click_count",
    "conversion_count",
]

MS_CLIENT_ID = os.environ.get("MICROSOFT_CLIENT_ID")
MS_CLIENT_SECRET = os.environ.get("MICROSOFT_CLIENT_SECRET")
MS_APP_LIST = os.environ.get("MICROSOFT_STORE_APP_LIST")
MS_TENANT_ID = os.environ.get("MICROSOFT_TENANT_ID")


def post_response(url, headers, data):
    """POST response function."""
    response = requests.post(url, headers=headers, data=data)
    if (response.status_code == 401) or (response.status_code == 400):
        print(f"***Error: {response.status_code}***")
        print(response.text)
    return response


def get_response(url, headers, params):
    """GET response function."""
    response = requests.get(url, headers=headers, params=params)
    if (response.status_code == 401) or (response.status_code == 400):
        print(f"***Error: {response.status_code}***")
        print(response.text)
    return response


def read_json(filename: str) -> dict:
    """Read JSON file."""
    with open(filename, "r") as f:
        print(f.read())
        data = json.loads(f.read())
    return data


def change_null_to_string(json_string):
    """Change null values in downloaded json string to string."""
    none_string = re.sub("null", '"null"', json_string)
    return none_string


def write_dict_to_csv(json_data, filename):
    """Write a dictionary to a csv."""
    with open(filename, "w") as out_file:
        dict_writer = csv.DictWriter(out_file, CSV_FIELDS)
        dict_writer.writeheader()
        dict_writer.writerows(json_data)


def microsoft_authorization(tenant_id, client_id, client_secret, resource_url):
    """Microsoft Store Authoriazation. Returns the bearer token required for data download."""
    url = f"https://login.microsoftonline.com/{tenant_id}/oauth2/token"
    query_params = {
        "grant_type": "client_credentials",
        "client_id": client_id,
        "client_secret": client_secret,
        "resource": resource_url,
    }
    headers = {"Content-Type": "application/x-www-form-urlencoded"}
    json_file = post_response(url, headers, query_params)
    response_data = json.loads(json_file.text)
    bearer_token = response_data["access_token"]
    return bearer_token


def download_microsoft_store_data(date, application_id, bearer_token):
    """Download data from Microsoft - application_id, bearer_token are called here."""
    # Need to delay the running of the job to ensure data is present.
    start_date = date
    end_date = date
    token = bearer_token
    app_id = application_id
    # getting overview metrics for different kpis / Deliverables
    url = f"https://manage.devcenter.microsoft.com/v1.0/my/analytics/appchannelconversions?applicationId={app_id}"
    url_params = (
        f"aggregationLevel=day&startDate={start_date}&endDate={end_date}&skip=0"
    )
    headers = {
        "Content-Type": "application/x-www-form-urlencoded",
        "Authorization": f"Bearer {token}",
    }
    print(url)
    response = get_response(url, headers, url_params)
    return response


def clean_json(query_export, date):
    """Turn the json file into a list to be input into a CSV for bq upload."""
    fields_list = []
    for val in query_export["Value"]:
        field_dict = {
            "date": date,
            "application_id": val["applicationId"],
            "application_name": val["applicationName"],
            "custom_campaign_id": val["customCampaignId"],
            "referrer_uri_domain": val["referrerUriDomain"],
            "channel_type": val["channelType"],
            "store_client": val["storeClient"],
            "device_type": val["deviceType"],
            "market": val["market"],
            "click_count": val["clickCount"],
            "conversion_count": val["conversionCount"],
        }
        fields_list.append(field_dict)
    return fields_list


def upload_to_bigquery(csv_data, project, dataset, table_name, date):
    """Upload the data to bigquery."""
    date = date
    print("writing json to csv")
    partition = f"{date}".replace("-", "")
    print(partition)
    with tempfile.NamedTemporaryFile() as tmp_csv:
        with open(tmp_csv.name, "w+b") as f_csv:
            write_dict_to_csv(csv_data, f_csv.name)
            client = bigquery.Client(project)
            job_config = bigquery.LoadJobConfig(
                create_disposition="CREATE_IF_NEEDED",
                write_disposition="WRITE_TRUNCATE",
                time_partitioning=bigquery.TimePartitioning(
                    type_=bigquery.TimePartitioningType.DAY,
                    field="date",
                ),
                skip_leading_rows=1,
                schema=[
                    bigquery.SchemaField("date", "DATE"),
                    bigquery.SchemaField("application_id", "STRING"),
                    bigquery.SchemaField("application_name", "STRING"),
                    bigquery.SchemaField("custom_campaign_id", "STRING"),
                    bigquery.SchemaField("referrer_uri_domain", "STRING"),
                    bigquery.SchemaField("channel_type", "STRING"),
                    bigquery.SchemaField("store_client", "STRING"),
                    bigquery.SchemaField("device_type", "STRING"),
                    bigquery.SchemaField("market", "STRING"),
                    bigquery.SchemaField("click_count", "INT64"),
                    bigquery.SchemaField("conversion_count", "INT64"),
                ],
            )
            destination = f"{project}.{dataset}.{table_name}${partition}"

            job = client.load_table_from_file(f_csv, destination, job_config=job_config)
            print(
                f"Writing microsoft_store data for all apps to {destination}. BigQuery job ID: {job.job_id}"
            )
            job.result()


def main():
    """Input data, call functions, get stuff done."""
    parser = ArgumentParser(description=__doc__)
    parser.add_argument("--date", required=True)
    parser.add_argument("--project", default="moz-fx-data-shared-prod")
    parser.add_argument("--dataset", default="microsoft_derived")

    args = parser.parse_args()

    project = args.project
    dataset = args.dataset
    table_name = "app_conversions_v1"

    date = args.date
    client_id = MS_CLIENT_ID
    client_secret = MS_CLIENT_SECRET
    app_list = MS_APP_LIST
    tenant_id = MS_TENANT_ID
    resource_url = API_URI

    ms_app_list = json.loads(app_list)

    data = []

    bearer_token = microsoft_authorization(
        tenant_id, client_id, client_secret, resource_url
    )

    # Cycle through the apps to get the relevant data
    for app in ms_app_list:
        print(f'This is data for {app["app_name"]} - {app["app_id"]} for ', date)
        # Ping the microsoft_store URL and get a response
        json_file = download_microsoft_store_data(date, app["app_id"], bearer_token)
        # For some reason, the date returned from https://manage.devcenter.microsoft.com/v1.0/my/analytics/appchannelconversions? returns the date as null.
        # This needs to be changed from a null to a string null.
        json_none_string = change_null_to_string(json_file.text)
        # Convert the string to a dictionary
        query_export = eval(json_none_string)
        if query_export["Value"]:
            # This section writes the tmp json data into a temp CSV file which will then be put into a BigQuery table
            microsoft_store_data = clean_json(query_export, date)
            data.extend(microsoft_store_data)
        else:
            print("no data for ", date)
        sleep(5)
    upload_to_bigquery(data, project, dataset, table_name, date)


if __name__ == "__main__":
    main()
