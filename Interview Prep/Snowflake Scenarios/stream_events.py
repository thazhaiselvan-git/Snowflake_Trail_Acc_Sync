"""
Snowpipe Streaming lab: push rows straight into a Snowflake table (no files, no stage, no S3).

Usage (from /root/work):
  ./ssenv/bin/python stream_events.py                 # 10 rows on channel_1
  ./ssenv/bin/python stream_events.py --rows 50 --channel channel_2
  ./ssenv/bin/python stream_events.py --start-offset 1 --rows 5   # replay old offsets (dedup test)
"""
import argparse
import json
import random
import time
from datetime import datetime, timezone

from snowflake.ingest.streaming import StreamingIngestClient

ACCOUNT = "FBIAJMH-QH29041"
USER = "THAZHAISELVAN"
DATABASE = "SF_SCENARIO_BASED_LEARNING"
SCHEMA = "SNOWPIPE"
TABLE = "STREAM_EVENTS"
PIPE = f"{TABLE}-STREAMING"  # default pipe, created automatically on first use
KEY_PATH = "/home/cloudshell-user/keys/rsa_key.p8"
PROFILE_PATH = "/home/cloudshell-user/keys/profile.json"

parser = argparse.ArgumentParser()
parser.add_argument("--rows", type=int, default=10)
parser.add_argument("--channel", default="channel_1")
parser.add_argument("--start-offset", type=int, default=None,
                    help="first offset to send; default = continue after last committed offset")
parser.add_argument("--delay", type=float, default=0.2, help="seconds between rows")
args = parser.parse_args()

with open(KEY_PATH) as f:
    profile = {
        "account": ACCOUNT,
        "user": USER,
        "url": f"https://{ACCOUNT}.snowflakecomputing.com:443",
        "private_key": f.read(),
        "role": "ACCOUNTADMIN",
    }
with open(PROFILE_PATH, "w") as f:
    json.dump(profile, f)

client = StreamingIngestClient(
    client_name="lab_client",
    db_name=DATABASE,
    schema_name=SCHEMA,
    pipe_name=PIPE,
    profile_json=PROFILE_PATH,
)

channel, status = client.open_channel(channel_name=args.channel)
last = channel.get_latest_committed_offset_token()
print(f"Opened channel {args.channel}; last committed offset = {last}")

start = args.start_offset if args.start_offset is not None else (int(last) + 1 if last else 1)
end = start + args.rows - 1

for offset in range(start, end + 1):
    row = {
        "EVENT_ID": offset,
        "DEVICE_ID": f"sensor-{random.randint(1, 3)}",
        "EVENT_TYPE": random.choice(["READING", "READING", "ALERT"]),
        "TEMPERATURE": round(random.uniform(18, 35), 2),
        "PAYLOAD": {"battery": random.randint(20, 100), "fw": "1.0.3"},  # dict -> stored as OBJECT
        "EVENT_TS": datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S.%f"),
        "CHANNEL_NAME": args.channel,
        "STREAM_OFFSET": offset,
    }
    channel.append_row(row, offset_token=str(offset))
    print(f"sent offset {offset}: {row['DEVICE_ID']} {row['EVENT_TYPE']} {row['TEMPERATURE']}")
    time.sleep(args.delay)

t0 = time.time()
# Wait for the exact last offset sent. A ">=" check passes immediately when replaying
# offsets lower than what the channel had already committed, and closing then loses rows.
channel.wait_for_commit(
    token_checker=lambda t: t == str(end),
    timeout_seconds=60,
)
print(f"Committed through offset {end} in {time.time() - t0:.1f}s after last send")

s = channel.get_channel_status()
print(f"Channel status: code={s.status_code} row_errors={s.row_error_count} "
      f"last_committed={s.last_committed_offset_token}")

channel.wait_for_flush(timeout_seconds=30)
channel.close()
client.close()
