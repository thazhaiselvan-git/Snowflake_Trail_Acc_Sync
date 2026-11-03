-- Set up the defaults
CREATE WAREHOUSE IF NOT EXISTS COMPUTE_WH;
USE WAREHOUSE COMPUTE_WH;

DROP DATABASE IF EXISTS AIRBNB CASCADE;

CREATE DATABASE AIRBNB;

CREATE SCHEMA IF NOT EXISTS AIRBNB.RAW;
CREATE SCHEMA IF NOT EXISTS AIRBNB.DEV;

USE DATABASE AIRBNB;
USE SCHEMA RAW;

-- Create our three tables and import the data from S3
CREATE OR REPLACE TABLE raw_listings
                    (id integer,
                     listing_url string,
                     name string,
                     room_type string,
                     minimum_nights integer,
                     host_id integer,
                     price string,
                     created_at datetime,
                     updated_at datetime);

COPY INTO raw_listings (id,
                        listing_url,
                        name,
                        room_type,
                        minimum_nights,
                        host_id,
                        price,
                        created_at,
                        updated_at)
                   from 's3://dbt-datasets/listings.csv'
                    FILE_FORMAT = (type = 'CSV' skip_header = 1
                    FIELD_OPTIONALLY_ENCLOSED_BY = '"');


CREATE OR REPLACE TABLE raw_reviews
                    (listing_id integer,
                     date datetime,
                     reviewer_name string,
                     comments string,
                     sentiment string);

COPY INTO raw_reviews (listing_id, date, reviewer_name, comments, sentiment)
                   from 's3://dbt-datasets/reviews.csv'
                    FILE_FORMAT = (type = 'CSV' skip_header = 1
                    FIELD_OPTIONALLY_ENCLOSED_BY = '"');


CREATE OR REPLACE TABLE raw_hosts
                    (id integer,
                     name string,
                     is_superhost string,
                     created_at datetime,
                     updated_at datetime);

COPY INTO raw_hosts (id, name, is_superhost, created_at, updated_at)
                   from 's3://dbt-datasets/hosts.csv'
                    FILE_FORMAT = (type = 'CSV' skip_header = 1
                    FIELD_OPTIONALLY_ENCLOSED_BY = '"');


-- =====================================================================
-- DATA FLOW EXPLORATION  (AIRBNB database)
--
--   RAW (loaded from S3)          DEV (built by dbt)
--   RAW_LISTINGS --> src_listings --> DIM_LISTINGS_CLEANSED --+
--                \-> SCD_RAW_LISTINGS (snapshot)              +--> DIM_LISTINGS_W_HOSTS
--   RAW_HOSTS    --> src_hosts    --> DIM_HOSTS_CLEANSED -----+
--                \-> SCD_RAW_HOSTS (snapshot)
--   RAW_REVIEWS  --> src_reviews  --> FCT_REVIEWS (incremental) --+
--   SEED_FULL_MOON_DATES (seed) ----------------------------------+--> MART_FULLMOON_REVIEWS
--
--   src_* models are ephemeral (not materialized), so they don't exist as objects.
-- =====================================================================

-- ---------- 1. RAW layer ----------
SELECT * FROM AIRBNB.RAW.RAW_LISTINGS LIMIT 10;
SELECT * FROM AIRBNB.RAW.RAW_HOSTS    LIMIT 10;
SELECT * FROM AIRBNB.RAW.RAW_REVIEWS  LIMIT 10;

-- ---------- 2. Cleansed dimensions ----------
SELECT * FROM AIRBNB.DEV.DIM_LISTINGS_CLEANSED LIMIT 10;
SELECT * FROM AIRBNB.DEV.DIM_HOSTS_CLEANSED    LIMIT 10;
SELECT * FROM AIRBNB.DEV.DIM_LISTINGS_W_HOSTS  LIMIT 10;

-- ---------- 3. Fact + seed + mart ----------
SELECT * FROM AIRBNB.DEV.FCT_REVIEWS           LIMIT 10;
SELECT * FROM AIRBNB.DEV.SEED_FULL_MOON_DATES  LIMIT 10;
SELECT * FROM AIRBNB.DEV.MART_FULLMOON_REVIEWS LIMIT 10;

-- ---------- 4. Snapshots (SCD Type 2 history) ----------
SELECT * FROM AIRBNB.DEV.SCD_RAW_LISTINGS ORDER BY id, dbt_valid_from LIMIT 10;
SELECT * FROM AIRBNB.DEV.SCD_RAW_HOSTS    ORDER BY id, dbt_valid_from LIMIT 10;

-- ---------- 5. Practice / test models ----------
SELECT * FROM AIRBNB.DEV.MY_FIRST_DBT_MODEL;
SELECT * FROM AIRBNB.DEV.MY_SECOND_DBT_MODEL;
SELECT * FROM AIRBNB.DEV.DBT_FIRST_FILE  LIMIT 10;
SELECT * FROM AIRBNB.DEV.DBT_SECOND_FILE LIMIT 10;

-- ---------- 6. Follow the flow: row counts per layer ----------
SELECT 'RAW_REVIEWS' AS model, COUNT(*) AS row_cnt FROM AIRBNB.RAW.RAW_REVIEWS
UNION ALL SELECT 'FCT_REVIEWS',           COUNT(*) FROM AIRBNB.DEV.FCT_REVIEWS
UNION ALL SELECT 'MART_FULLMOON_REVIEWS', COUNT(*) FROM AIRBNB.DEV.MART_FULLMOON_REVIEWS
UNION ALL SELECT 'RAW_LISTINGS',          COUNT(*) FROM AIRBNB.RAW.RAW_LISTINGS
UNION ALL SELECT 'DIM_LISTINGS_W_HOSTS',  COUNT(*) FROM AIRBNB.DEV.DIM_LISTINGS_W_HOSTS
UNION ALL SELECT 'RAW_HOSTS',             COUNT(*) FROM AIRBNB.RAW.RAW_HOSTS
UNION ALL SELECT 'DIM_HOSTS_CLEANSED',    COUNT(*) FROM AIRBNB.DEV.DIM_HOSTS_CLEANSED;

-- Reviews dropped between RAW and FCT (fct_reviews filters out NULL review text)
SELECT COUNT(*) AS null_comment_reviews FROM AIRBNB.RAW.RAW_REVIEWS WHERE comments IS NULL;

-- ---------- 7. Compare raw vs cleansed listings ----------
SELECT r.id, r.name, r.price AS raw_price, d.listing_name, d.price AS clean_price, d.minimum_nights
FROM AIRBNB.RAW.RAW_LISTINGS r
JOIN AIRBNB.DEV.DIM_LISTINGS_CLEANSED d ON d.listing_id = r.id
LIMIT 10;

-- ---------- 8. Play with the data ----------
-- Does a full moon affect review sentiment?
SELECT is_full_moon, review_sentiment, COUNT(*) AS reviews
FROM AIRBNB.DEV.MART_FULLMOON_REVIEWS
GROUP BY 1, 2
ORDER BY 1, 2;

-- Superhosts vs regular hosts: listing count and average price
SELECT host_is_superhost, COUNT(*) AS listings, ROUND(AVG(price), 2) AS avg_price
FROM AIRBNB.DEV.DIM_LISTINGS_W_HOSTS
GROUP BY 1;

-- Reviews per year with sentiment split
SELECT YEAR(review_date) AS yr,
       COUNT_IF(review_sentiment = 'positive') AS positive,
       COUNT_IF(review_sentiment = 'neutral')  AS neutral,
       COUNT_IF(review_sentiment = 'negative') AS negative
FROM AIRBNB.DEV.FCT_REVIEWS
GROUP BY 1
ORDER BY 1;