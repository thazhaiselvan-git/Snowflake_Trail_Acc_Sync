import logging 
import os,glob
from airflow import Dataset
from datetime import date,datetime,timedelta
from airflow import DAG
#from airflow.utils.task_group import TaskGroup
from airflow.decorators import task_group
from utils import utils
from utils import notification_utils
from airflow.operators.python import PythonOperator
from airflow.providers.snowflake.hooks.snowflake import SnowflakeHook
from airflow.operators.bash import BashOperator
from airflow.providers.ssh.hooks.ssh import SSHHook
from airflow.providers.common.sql.sensors.sql import SqlSensor
from utils.sftp_get_multiple_files_operator import SFTPGetMultipleFilesOperator
from airflow.utils.email import send_email
from airflow.sensors.external_task import ExternalTaskSensor
from airflow.providers.common.sql.operators.sql import (SQLCheckOperator,SQLExecuteQueryOperator,SQLIntervalCheckOperator,SQLValueCheckOperator,)
from airflow.providers.sftp.sensors.sftp import SFTPSensor
import pendulum
import requests
import time
import billiard as multiprocessing
#from billiard import Pool
from multiprocessing import Pool
import json
from airflow.models import Variable
from airflow.utils.db import provide_session
from airflow.models import XCom
from pendulum import duration
from airflow.operators.python import ShortCircuitOperator
import os.path
import csv
from utils import get_okta_token_prod

local_tz = pendulum.timezone("America/Chicago")

dwh_hook = SnowflakeHook(snowflake_conn_id="wca_elt_conjur_snowflake_dt",session_parameters={"QUERY_TAG": "AIRFLOW-DAILY_MASTER_METRIC_EXTRACT_XML"})
logging.basicConfig(level=logging.WARNING)
logger = logging.getLogger(__name__)

logger = multiprocessing.get_logger()
logger.setLevel(logging.WARNING)

@provide_session
def cleanup_xcom(context, session=None):
    dag_id = context['dag'].dag_id
    print('DAG_ID: ',dag_id)
    session.query(XCom).filter(XCom.dag_id == dag_id).delete()

ssh_connection = SSHHook(ssh_conn_id='SFTP_DS_UNIX')

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def mark_process_as_failed(context): 
    failed_task_instance = context.get('task_instance') 
    error_msg = context.get('exception') 
    task_id = failed_task_instance.task_id 
    task_state =failed_task_instance.state 
    #if task_state == 'failed': 
    print(f' THIS WAS CAUGHT as EXCEPTION  IN <<============== {failed_task_instance.state} ========>>   task {failed_task_instance.task_id} Failed in dag {failed_task_instance.dag_id} Error message {error_msg} ') 
    try:
       utils.incident_creation(context)
    except Exception as err:
       print('Error while creating Incident')
    finally:
       notification_utils.send_failure_email(context)

def sla_callback_function(dag, task_list, blocking_task_list, slas, blocking_tis):
    dag_id = slas[0].dag_id
    execution_date = slas[0].execution_date.isoformat()
    task_instance: TaskInstance = blocking_tis[0]
    url=task_instance.log_url
    airflow_cluster=os.getenv('AIRFLOW_CLUSTER_NAME', None)
    logurl=url.replace('localhost:8080',airflow_cluster)
    airflowenv= Variable.get("AIRFLOW_ENV", default_var=None)
    email_dl= Variable.get("EMAIL_SLA_MISS_DL", default_var=None)
    subject = f"AIRFLOW-{airflowenv} SLA miss on DAG = {dag_id}"
    msg = f" DAG missed SLA: {dag_id}  <br> Execution Date: {execution_date}  <br>  Blocking tasks:  <br> {blocking_task_list} <br> Log URL: {logurl} <br> "
    send_email(to=email_dl, subject=subject, html_content=msg)

default_args = {'owner': 'Airflow',
      'start_date': datetime(2024,3,15,tzinfo=local_tz),
      'email_on_failure':False,
      'email_on_retry': False,
      'do_xcom_push':False,
      'sla':timedelta(hours=20),
      'on_failure_callback': mark_process_as_failed}

dag = DAG(dag_id='DAILY_MASTER_METRIC_NEW',
      default_args=default_args,
      catchup=False,
      max_active_runs=1,
      schedule='0 */1 * * 1-6',
      sla_miss_callback=sla_callback_function,
      tags=['METRICS','ANNUAL','DAILY_METRIC','IRAS'])   
 
dag.doc_md = 'Smart date data information and this DAG loads data S0 to ADL' 

def filewatcher_cnm_func(): 
 PATH='/opt/p_vol/dataset/DAILY_METRIC_DATASET_READY_PROCESS.ds'   
 check_file = os.path.isfile(PATH)
 print('IS FILE AVAILABLE',check_file)
 return check_file


DAILY_MASTER_METRIC_FILE_CNM_WATCHER=ShortCircuitOperator(task_id='DAILY_MASTER_METRIC_FILE_CNM_WATCHER',
              python_callable=filewatcher_cnm_func,
              pool='HOLD_IRAS_LOAD_POOL',
              dag=dag)

def filewatcher_func(): 
 PATH='/opt/p_vol/dataset/DAILY_MASTER_METRIC_COMPLETE_LOAD.ds'   
 check_file = os.path.isfile(PATH)
 print('IS FILE AVAILABLE',check_file)
 return check_file


DAILY_MASTER_METRIC_FILE_WATCHER=ShortCircuitOperator(task_id='DAILY_MASTER_METRIC_FILE_WATCHER',
              python_callable=filewatcher_func,
              pool='HOLD_IRAS_LOAD_POOL',
              dag=dag)

delete_dataset_script=""" 
FILE=/opt/p_vol/dataset/DAILY_METRIC_DATASET_READY_PROCESS.ds
FILE1=/opt/p_vol/dataset/DAILY_MASTER_METRIC_COMPLETE_LOAD.ds
if [ -f "$FILE" ]; then
    rm $FILE
else
    echo "$FILE does not exist."
    exit 1
fi
if [ -f "$FILE1" ]; then
    rm $FILE1
else
    echo "$FILE1 does not exist."
    exit 1
fi
  """


DAILY_MASTER_METRIC_DELETE_DATASET=BashOperator(task_id='DAILY_MASTER_METRIC_DELETE_DATASET',
        bash_command= delete_dataset_script,
        depends_on_past=True,
        wait_for_downstream=True,
        dag=dag)
DAILY_MASTER_METRIC_DELETE_DATASET.doc = 'Delete dataset Task is to cleanup the dataset file on the airflow path /opt/p_vol/dataset/ before the DAG run' 

DAILY_MASTER_METRIC_CLEANING_RESPONSE = SQLExecuteQueryOperator(task_id='DAILY_MASTER_METRIC_CLEANING_RESPONSE',
      sql=""" TRUNCATE TABLE CODEBASE.DAILY_MSTR_METRIC_DLY_RESPONSE; """,
      conn_id='wca_elt_conjur_snowflake_dt',
      autocommit=True,
      pool='DEFAULT_POOL',
      do_xcom_push=True,
      show_return_value_in_logs=True,
      hook_params={"session_parameters": {"QUERY_TAG": "AIRFLOW-DAILY_MASTER_METRIC_CLEANING_RESPONSE"},},
      dag=dag)
DAILY_MASTER_METRIC_CLEANING_RESPONSE.doc='Task to Load the data from File to the S0 Table'

def DAILY_MASTER_METRIC_FUNC(REQUEST_DETAILS):
    TOKEN =get_okta_token_prod.get_okta_token()
    text = str(TOKEN)
    print(f"Processing TOKEN: {text} ")
    auth_token_string="Bearer " +text
    stimeapi =time.time()
    i = REQUEST_DETAILS
    print(f"Processing PERF_ID1: {i[1]} ")
    CREATED_TS = i[0]
    PERF_ID1 = i[1] 
    AS_OF_DT = i[2] 
    SPONSOR_CD = i[3] 
    USERID = i[10]
    SOAP_REQUEST = i[4]
    payload = SOAP_REQUEST.replace("WCABATCH", USERID)
    #print(f'CREATED_TS :' ,i[0])
    #print(f'PERF_ID :' ,i[1])
    #print(f'AS_OF_DATE :' ,i[2])
    #print(f'SPONSOR_CODE :' ,i[3])  
    #print(f'Payload :' ,i[4])
    #print("\n")
    IRAS_TYPE = i[5]
    TABLE_NM = i[6]
    REQUEST_TYPE = i[7]
    #url = i[8] 
    url =f'https://rpm-dnt.ntrs.com:8016/Services/PerformanceMetricsService.svc/basic'
    #headers = json.loads(i[9]) 
    headers = {"Authorization": auth_token_string, "Content-Type": "text/xml;charset=utf-8","SOAPAction": "http://www.ntrs.com/ns/rpm/service/IPerformanceMetricsService/GetMetrics","X-NT-tla":"WCA","X-NT-user-id":USERID} 
    print('Header:',headers)
    response = requests.request("POST", url, headers=headers, data=payload)
    print(f'PERF_ID1: {i[1]} respone status_code : {response.status_code}  ')
    RESPONSE_STATUS=str(response.status_code)
    TXT=str(response.content)
    RESPONSE_REQ=TXT.replace("b'","'")
    insert_query=PERF_ID1,AS_OF_DT,SPONSOR_CD,REQUEST_TYPE,IRAS_TYPE
    INS="INSERT INTO CODEBASE.DAILY_MSTR_METRIC_DLY_RESPONSE (PERF_ID,AS_OF_DT,SPONSOR_CD,SOAP_REQUEST_TYPE,SOAP_FREQUENCY_TYPE,SOAP_RESPONSE_BODY,RESPONSE_STATUS) values ('" +insert_query[0] + "','" +insert_query[1] + "','" +insert_query[2] + "','" +insert_query[3] + "','" +insert_query[4] + "'," +RESPONSE_REQ + "," +RESPONSE_STATUS +");"
    dwh_hook.run(INS)
    endtimeapi =time.time()
    print(f' Inserted  PERF_ID1: {i[1]} ')
    print(f'API -Time Processed {endtimeapi - stimeapi:.2f}')
    #print("\n")


def DAILY_MASTER_METRIC_EXTRACT():
    start =time.time()
    RECORD_COUNT=dwh_hook.get_first( "SELECT COUNT(*) FROM (SELECT MHI_CREATED_TS,CAST (MHI_PERF_ID AS STRING ) MHI_PERF_ID,MHI_AS_OF_DT,MHI_SPONSOR_CD,REQUEST,IRAS_TYPE,TABLE_NAME,SOAP_REQUEST_TYPE,REQUEST_URLS,HEADER,LOGIN_ID FROM CODEBASE.WCA_DAILY_METRIC_INPUT_REQUEST WHERE   (MHI_PERF_ID,MHI_AS_OF_DT,MHI_SPONSOR_CD,SOAP_REQUEST_TYPE) NOT IN (SELECT DISTINCT PERF_ID,AS_OF_DT,SPONSOR_CD,SOAP_REQUEST_TYPE FROM CODEBASE.DAILY_MSTR_METRIC_DLY_RESPONSE )) ;" )
    Total_records=RECORD_COUNT[0]
    while Total_records > 0:
        REQUEST_DETAILS=dwh_hook.get_records( "SELECT MHI_CREATED_TS,CAST (MHI_PERF_ID AS STRING ) MHI_PERF_ID,MHI_AS_OF_DT,MHI_SPONSOR_CD,REQUEST,IRAS_TYPE,TABLE_NAME,SOAP_REQUEST_TYPE,REQUEST_URLS,HEADER,LOGIN_ID FROM CODEBASE.WCA_DAILY_METRIC_INPUT_REQUEST WHERE   (MHI_PERF_ID,MHI_AS_OF_DT,MHI_SPONSOR_CD,SOAP_REQUEST_TYPE) NOT IN (SELECT DISTINCT PERF_ID,AS_OF_DT,SPONSOR_CD,SOAP_REQUEST_TYPE FROM CODEBASE.DAILY_MSTR_METRIC_DLY_RESPONSE )  limit 50;" )
        print(f"Total rows: {len(REQUEST_DETAILS)} fetched from input")
        pool=multiprocessing.Pool(processes=6)
        pool.map(DAILY_MASTER_METRIC_FUNC,REQUEST_DETAILS)
        Total_records=RECORD_COUNT[0]
        pool.close()
        Total_records=0
        RECORD_COUNT=dwh_hook.get_first( "SELECT COUNT(*) FROM (SELECT MHI_CREATED_TS,CAST (MHI_PERF_ID AS STRING ) MHI_PERF_ID,MHI_AS_OF_DT,MHI_SPONSOR_CD,REQUEST,IRAS_TYPE,TABLE_NAME,SOAP_REQUEST_TYPE,REQUEST_URLS,HEADER,LOGIN_ID FROM CODEBASE.WCA_DAILY_METRIC_INPUT_REQUEST WHERE   (MHI_PERF_ID,MHI_AS_OF_DT,MHI_SPONSOR_CD,SOAP_REQUEST_TYPE) NOT IN (SELECT DISTINCT PERF_ID,AS_OF_DT,SPONSOR_CD,SOAP_REQUEST_TYPE FROM CODEBASE.DAILY_MSTR_METRIC_DLY_RESPONSE )) ;" )
        print('Total_Records',RECORD_COUNT[0])
        Total_records=RECORD_COUNT[0]
    end =time.time()
    print(f'Time Processed {end - start:.2f}')
  

 

DAILY_MASTER_METRIC_EXTRACT_XML = PythonOperator(task_id="DAILY_MASTER_METRIC_EXTRACT_XML", 
                python_callable=DAILY_MASTER_METRIC_EXTRACT,
                pool='IRAS_POOL',
                retries=4,
                retry_delay=duration(minutes=1),
                dag=dag)

def chk_unprocessed_perfids():
    email_dl= Variable.get("IRAS_VALIDATION_EMAIL_DL", default_var=None)  
    current_env= Variable.get("AIRFLOW_ENV", default_var=None)
    dwh_hook = SnowflakeHook(snowflake_conn_id='wca_elt_conjur_snowflake_dt',session_parameters={'QUERY_TAG': 'AIRFLOW-DAILY_MASTER_METRIC_EXTRACT_XML_VALIDATION'})
    unprocessed_perfids="SELECT * FROM (SELECT * FROM CODEBASE.WCA_DAILY_METRIC_INPUT_REQUEST where (MHI_PERF_ID,MHI_AS_OF_DT,MHI_SPONSOR_CD) not in (SELECT DISTINCT IBO_ID,IBO_ASOF_DT,IBO_SPONSOR_CD FROM CODEBASE.WCA_STG_IRAS_DLY_MSTR_MTRC_S0_SRC_VW) and SOAP_REQUEST_TYPE='DLY_MSTR_METRIC_DLY' UNION SELECT * FROM CODEBASE.WCA_DAILY_METRIC_INPUT_REQUEST where (MHI_PERF_ID,MHI_AS_OF_DT,MHI_SPONSOR_CD) not in (SELECT DISTINCT IAO_PERFOBJID,IAO_ASOF_DT,IAO_SPONSOR_CD FROM CODEBASE.WCA_STG_IRAS_DLY_ANNL_MTRC_S0_SRC_VW) and SOAP_REQUEST_TYPE='DLY_MSTR_METRIC_ANNUAL');"
    unprocessed_perfids_result= dwh_hook.get_records(unprocessed_perfids)
    # Create the csv file
    filepath=r'/opt/p_vol/dataset/UNPROCESSED_PERFIDS_DAILY_MASTER_METRIC.CSV'
    with open(filepath, 'w') as fp:
      myFile = csv.writer(fp, lineterminator = '\n')
      header = ['MHI_CREATED_TS','MHI_PERF_ID','MHI_AS_OF_DT','MHI_SPONSOR_CD','REQUEST','IRAS_TYPE','TABLE_NAME','SOAP_REQUEST_TYPE','REQUEST_URLS','HEADER']
      myFile.writerow(header)
      myFile.writerows(unprocessed_perfids_result)

    if unprocessed_perfids_result:
     msg = f"Hi Team,<br>Attached is the Unprocessed PERFIDs for DAILY_MASTER_METRIC .<br> <br>Thanks,<br>WCA ETL "
     subject=f"{current_env} :DAILY_MASTER_METRIC List of Unprocessed PERFIDs "  
     filename=['/opt/p_vol/dataset/UNPROCESSED_PERFIDS_DAILY_MASTER_METRIC.CSV']
     send_email(to=email_dl, subject=subject, html_content=msg,files=filename)


DAILY_MASTER_METRIC_EXTRACT_XML_VALIDATION= PythonOperator(task_id='DAILY_MASTER_METRIC_EXTRACT_XML_VALIDATION',
      python_callable=chk_unprocessed_perfids,
      show_return_value_in_logs=True,
      dag=dag) 

DAILY_MASTER_METRIC_OPEN_BUSINESS_PRCECSS = SQLExecuteQueryOperator(task_id='IDAILY_MASTER_METRIC_OPEN_BUSINESS_PRCECSS',
      sql="""CALL RUN_CONTROL.RCC_OPEN_PROC_ROW_SP('DAILY_MASTER_METRIC');""",
      conn_id='wca_elt_conjur_snowflake_dt',
      autocommit=True,
      pool='DEFAULT_POOL',
      show_return_value_in_logs=True,
      hook_params={"session_parameters": {"QUERY_TAG": "AIRFLOW-DAILY_MASTER_METRIC_OPEN_BUSINESS_PRCECSS"},},
      dag=dag)
DAILY_MASTER_METRIC_OPEN_BUSINESS_PRCECSS.doc='Task to Open the Business process before the Data load begins'

DAILY_MASTER_METRIC_SCRTY_IRAS_MDW = SQLExecuteQueryOperator(task_id='DAILY_MASTER_METRIC_SCRTY_IRAS_MDW',
      sql="""CALL CODEBASE.WCA_ADL_TO_MDW_SCRTY_IRAS('DAILY_MASTER_METRIC_SCRTY_IRAS_MDW');""",
      conn_id='wca_elt_conjur_snowflake_dt',
      autocommit=True,
      pool='DEFAULT_POOL',
      show_return_value_in_logs=True,
      hook_params={"session_parameters": {"QUERY_TAG": "AIRFLOW-DAILY_MASTER_METRIC_SCRTY_IRAS_MDW"},},
      dag=dag)
DAILY_MASTER_METRIC_SCRTY_IRAS_MDW.doc='Task to Open the Business process before the Data load begins'

DAILY_MASTER_METRIC_IRAS_PERF_MDW = SQLExecuteQueryOperator(task_id='DAILY_MASTER_METRIC_IRAS_PERF_MDW',
      sql="""CALL CODEBASE.WCA_ADL_TO_MDW_IRAS_FACT_LOAD('DAILY_MASTER_METRIC_IRAS_PERF_MDW');""",
      conn_id='wca_elt_conjur_snowflake_dt',
      autocommit=True,
      pool='DEFAULT_POOL',
      show_return_value_in_logs=True,
      hook_params={"session_parameters": {"QUERY_TAG": "AIRFLOW-DAILY_MASTER_METRIC_IRAS_PERF_MDW"},},
      dag=dag)
DAILY_MASTER_METRIC_IRAS_PERF_MDW.doc='Task to Open the Business process before the Data load begins'


DAILY_MASTER_METRIC_IRAS_RPTNG_DATES_MDW = SQLExecuteQueryOperator(task_id='DAILY_MASTER_METRIC_IRAS_RPTNG_DATES_MDW',
      sql="""CALL CODEBASE.WCA_ADL_TO_MDW_IRAS_DATE('DAILY_MASTER_METRIC_IRAS_RPTNG_DATES_MDW');""",
      conn_id='wca_elt_conjur_snowflake_dt',
      autocommit=True,
      pool='DEFAULT_POOL',
      show_return_value_in_logs=True,
      hook_params={"session_parameters": {"QUERY_TAG": "AIRFLOW-DAILY_MASTER_METRIC_IRAS_RPTNG_DATES_MDW"},},
      dag=dag)
DAILY_MASTER_METRIC_IRAS_RPTNG_DATES_MDW.doc='Task to Open the Business process before the Data load begins'

DAILY_MASTER_METRIC_LTST_STATE_MDW = SQLExecuteQueryOperator(task_id='DAILY_MASTER_METRIC_LTST_STATE_MDW',
      sql="""CALL CODEBASE.WCA_MDW_POST_UPDATE('WCA_MDW_L_AA_LTST_STATE');""",
      conn_id='wca_elt_conjur_snowflake_dt',
      autocommit=True,
      pool='DEFAULT_POOL',
      show_return_value_in_logs=True,
      hook_params={"session_parameters": {"QUERY_TAG": "AIRFLOW-DAILY_MASTER_METRIC_LTST_STATE_MDW"},},
      dag=dag)
DAILY_MASTER_METRIC_LTST_STATE_MDW.doc='Task to Open the Business process before the Data load begins'

DAILY_MASTER_METRIC_BRIDGE_MDW = SQLExecuteQueryOperator(task_id='DAILY_MASTER_METRIC_BRIDGE_MDW',
      sql="""CALL CODEBASE.WCA_ADL_TO_MDW_IRAS_BRIDGE('DAILY_MASTER_METRIC_BRIDGE_MDW');""",
      conn_id='wca_elt_conjur_snowflake_dt',
      autocommit=True,
      pool='DEFAULT_POOL',
      show_return_value_in_logs=True,
      hook_params={"session_parameters": {"QUERY_TAG": "AIRFLOW-DAILY_MASTER_METRIC_BRIDGE_MDW"},},
      dag=dag)
DAILY_MASTER_METRIC_BRIDGE_MDW.doc='Task to Open the Business process before the Data load begins'


DAILY_MASTER_METRIC_NONBENCHMARK_IRAS_PERF_MDW = SQLExecuteQueryOperator(task_id='DAILY_MASTER_METRIC_NONBENCHMARK_IRAS_PERF_MDW',
      sql="""CALL CODEBASE.WCA_ADL_TO_MDW_IRAS_FACT_LOAD('DAILY_MASTER_METRIC_NONBENCHMARK_IRAS_PERF_MDW');""",
      conn_id='wca_elt_conjur_snowflake_dt',
      autocommit=True,
      pool='DEFAULT_POOL',
      show_return_value_in_logs=True,
      hook_params={"session_parameters": {"QUERY_TAG": "AIRFLOW-DAILY_MASTER_METRIC_NONBENCHMARK_IRAS_PERF_MDW"},},
      dag=dag)
DAILY_MASTER_METRIC_NONBENCHMARK_IRAS_PERF_MDW.doc='Task to Open the Business process before the Data load begins'

DAILY_MASTER_METRIC_CLOSE_BUSINESS_PRCECSS = SQLExecuteQueryOperator(task_id='DAILY_MASTER_METRIC_CLOSE_BUSINESS_PRCECSS',
      sql="""CALL RUN_CONTROL.RCC_CLOSE_PROC_ROW_SP('DAILY_MASTER_METRIC','Y');""",
      conn_id='wca_elt_conjur_snowflake_dt',
      autocommit=True,
      pool='DEFAULT_POOL',
      show_return_value_in_logs=True,
      hook_params={"session_parameters": {"QUERY_TAG": "AIRFLOW-DAILY_MASTER_METRIC_CLOSE_BUSINESS_PRCECSS"},},
      dag=dag)
DAILY_MASTER_METRIC_CLOSE_BUSINESS_PRCECSS.doc='Task to Close the Business process After the Data load is Complete'

DAILY_MASTER_METRIC_CNM_COMPLETE=BashOperator(task_id='DAILY_MASTER_METRIC_CNM_COMPLETE',
        bash_command= "echo 'DAILY_MASTER_METRIC_CNM_COMPLETE' > /opt/p_vol/dataset/DAILY_METRIC_DATASET_COMPLETED.ds;  ls -ltr /opt/p_vol/dataset/ ",
        retries=3,
        retry_delay=duration(minutes=2),
        dag=dag)
DAILY_MASTER_METRIC_CNM_COMPLETE.doc = 'This Task will create the dataset file on the airflow path /opt/p_vol/dataset/ after the successful completion of the DAG run'

DAILY_MASTER_METRIC_COMPLETE=BashOperator(task_id='DAILY_MASTER_METRIC_COMPLETE',
        bash_command= "echo 'DAILY_MASTER_METRIC_COMPLETE' > /opt/p_vol/dataset/DAILY_MASTER_METRIC_COMPLETE_LOAD.ds;  ls -ltr /opt/p_vol/dataset/ ",
        retries=3,
        retry_delay=duration(minutes=2),
        on_success_callback=cleanup_xcom,
        dag=dag)
DAILY_MASTER_METRIC_COMPLETE.doc = 'This Task will create the dataset file on the airflow path /opt/p_vol/dataset/ after the successful completion of the DAG run'

@task_group(group_id='DAILY_ANNUAL_DATA_PROCESS',dag=dag)
def TG1():
   DAILY_ANNUAL_METRIC_S0 = SQLExecuteQueryOperator(task_id='DAILY_ANNUAL_METRIC_S0',
      sql=""" CALL CODEBASE.WCA_API_S0_DATA_LOAD('DAILY_ANNUAL_METRIC_S0'); """,
      conn_id='wca_elt_conjur_snowflake_dt',
      autocommit=True,
      pool='DEFAULT_POOL',
      do_xcom_push=True,
      show_return_value_in_logs=True,
      hook_params={"session_parameters": {"QUERY_TAG": "AIRFLOW-DAILY_ANNUAL_METRIC-S0"},},
      dag=dag)
   DAILY_ANNUAL_METRIC_S0.doc='Task to Load the data from File to the S0 Table'

   DAILY_ANNUAL_METRIC_S1 = SQLExecuteQueryOperator(task_id='DAILY_ANNUAL_METRIC_S1',
      sql=""" CALL CODEBASE.WCA_S0_TO_S1_DATA_LOAD('DAILY_ANNUAL_METRIC_S1'); """,
      conn_id='wca_elt_conjur_snowflake_dt',
      autocommit=True,
      pool='DEFAULT_POOL',
      do_xcom_push=True,
      show_return_value_in_logs=True,
      hook_params={"session_parameters": {"QUERY_TAG": "AIRFLOW-DAILY_ANNUAL_METRIC-S1"},},
      dag=dag)
   DAILY_ANNUAL_METRIC_S1.doc='Task to Load the data from File to the S0 Table'

   DAILY_ANNUAL_METRIC_ADL = SQLExecuteQueryOperator(task_id='DAILY_ANNUAL_METRIC_ADL',
      sql=""" CALL CODEBASE.WCA_S0_TO_S1_DATA_LOAD('DAILY_ANNUAL_METRIC_ADL'); """,
      conn_id='wca_elt_conjur_snowflake_dt',
      autocommit=True,
      pool='DEFAULT_POOL',
      do_xcom_push=True,
      show_return_value_in_logs=True,
      hook_params={"session_parameters": {"QUERY_TAG": "AIRFLOW-DAILY_ANNUAL_METRIC-ADL"},},
      dag=dag)
   DAILY_ANNUAL_METRIC_ADL.doc='Task to Load the data from File to the S0 Table'


   DAILY_ANNUAL_METRIC_S0 >> DAILY_ANNUAL_METRIC_S1 >> DAILY_ANNUAL_METRIC_ADL 

@task_group(group_id='IRAS_HIERARCHY_S1_TO_MDW',dag=dag)
def TG2():
   IRAS_HIERARCHY_ADL = SQLExecuteQueryOperator(task_id='IRAS_HIERARCHY_ADL',
      sql=""" CALL CODEBASE.WCA_S1_TO_ADL_DIRECT_INSERT('IRAS_HIERARCHY_ADL');  """,
      conn_id='wca_elt_conjur_snowflake_dt',
      autocommit=True,
      pool='DEFAULT_POOL',
      do_xcom_push=True,
      show_return_value_in_logs=True,
      hook_params={"session_parameters": {"QUERY_TAG": "AIRFLOW-IRAS_HIERARCHY_ADL"},},
      dag=dag)
   IRAS_HIERARCHY_ADL.doc='Task to Load the data from S1 to the ADL Table'

   IRAS_HIERARCHY_GLBL_CONFORMITY = SQLExecuteQueryOperator(task_id='IRAS_HIERARCHY_GLBL_CONFORMITY',
      sql=""" CALL CODEBASE.WCA_ADL_TO_MDW_CDC_TYPE1('IRAS_HIERARCHY_GLBL_CONFORMITY'); """,
      conn_id='wca_elt_conjur_snowflake_dt',
      autocommit=True,
      pool='DEFAULT_POOL',
      do_xcom_push=True,
      show_return_value_in_logs=True,
      hook_params={"session_parameters": {"QUERY_TAG": "AIRFLOW-IRAS_HIERARCHY_GLBL_CONFORMITY"},},
      dag=dag)
   IRAS_HIERARCHY_GLBL_CONFORMITY.doc='Task to Load the data from File to the S0 Table'

   IRAS_HIERARCHY_MEASRS_HIER_MDW = SQLExecuteQueryOperator(task_id='IRAS_HIERARCHY_MEASRS_HIER_MDW',
      sql=""" CALL CODEBASE.WCA_ADL_TO_MDW_IRAS_MSRS_HIER('IRAS_HIERARCHY_MEASRS_HIER_MDW');  """,
      conn_id='wca_elt_conjur_snowflake_dt',
      autocommit=True,
      pool='IRAS_MAST_METRIC_D_HIERARCHY_POOL',
      do_xcom_push=True,
      show_return_value_in_logs=True,
      hook_params={"session_parameters": {"QUERY_TAG": "AIRFLOW-IRAS_HIERARCHY_MEASRS_HIER_MDW"},},
      dag=dag)
   IRAS_HIERARCHY_MEASRS_HIER_MDW.doc='Task to Load the data from ADL to the MDW Table'

   IRAS_HIERARCHY_ADL >> IRAS_HIERARCHY_GLBL_CONFORMITY >> IRAS_HIERARCHY_MEASRS_HIER_MDW

@task_group(group_id='DAILY_METRIC_DATA_PROCESS',dag=dag)
def TG0():
   DAILY_MASTER_METRIC_S0 = SQLExecuteQueryOperator(task_id='DAILY_MASTER_METRIC_S0',
      sql=""" CALL CODEBASE.WCA_API_S0_DATA_LOAD('DAILY_MASTER_METRIC_S0'); """,
      conn_id='wca_elt_conjur_snowflake_dt',
      autocommit=True,
      pool='DEFAULT_POOL',
      do_xcom_push=True,
      show_return_value_in_logs=True,
      hook_params={"session_parameters": {"QUERY_TAG": "AIRFLOW-DAILY_MASTER_METRIC-S0"},},
      dag=dag)
   DAILY_MASTER_METRIC_S0.doc='Task to Load the data from File to the S0 Table'

   DAILY_MASTER_METRIC_S1 = SQLExecuteQueryOperator(task_id='DAILY_MASTER_METRIC_S1',
      sql=""" CALL CODEBASE.WCA_S0_TO_S1_DATA_LOAD('DAILY_MASTER_METRIC_S1'); """,
      conn_id='wca_elt_conjur_snowflake_dt',
      autocommit=True,
      pool='DEFAULT_POOL',
      do_xcom_push=True,
      show_return_value_in_logs=True,
      hook_params={"session_parameters": {"QUERY_TAG": "AIRFLOW-DAILY_MASTER_METRIC-S1"},},
      dag=dag)
   DAILY_MASTER_METRIC_S1.doc='Task to Load the data from File to the S0 Table'

   DAILY_MASTER_METRIC_ADL = SQLExecuteQueryOperator(task_id='DAILY_MASTER_METRIC_ADL',
      sql=""" CALL CODEBASE.WCA_S0_TO_S1_DATA_LOAD('DAILY_MASTER_METRIC_ADL'); """,
      conn_id='wca_elt_conjur_snowflake_dt',
      autocommit=True,
      pool='DEFAULT_POOL',
      do_xcom_push=True,
      show_return_value_in_logs=True,
      hook_params={"session_parameters": {"QUERY_TAG": "AIRFLOW-DAILY_MASTER_METRIC-ADL"},},
      dag=dag)
   DAILY_MASTER_METRIC_ADL.doc='Task to Load the data from File to the S0 Table'

   DAILY_MASTER_METRIC_S0 >> DAILY_MASTER_METRIC_S1 >> DAILY_MASTER_METRIC_ADL

DAILY_MASTER_METRIC_FILE_CNM_WATCHER >> DAILY_MASTER_METRIC_FILE_WATCHER >> DAILY_MASTER_METRIC_DELETE_DATASET >> DAILY_MASTER_METRIC_CLEANING_RESPONSE >> DAILY_MASTER_METRIC_EXTRACT_XML >> DAILY_MASTER_METRIC_EXTRACT_XML_VALIDATION >> DAILY_MASTER_METRIC_OPEN_BUSINESS_PRCECSS >> [TG0(), TG1() ,TG2()] >> DAILY_MASTER_METRIC_SCRTY_IRAS_MDW >> DAILY_MASTER_METRIC_IRAS_PERF_MDW >> DAILY_MASTER_METRIC_NONBENCHMARK_IRAS_PERF_MDW >> DAILY_MASTER_METRIC_IRAS_RPTNG_DATES_MDW >> DAILY_MASTER_METRIC_LTST_STATE_MDW >> DAILY_MASTER_METRIC_BRIDGE_MDW >> DAILY_MASTER_METRIC_CLOSE_BUSINESS_PRCECSS >> [DAILY_MASTER_METRIC_CNM_COMPLETE, DAILY_MASTER_METRIC_COMPLETE]