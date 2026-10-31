PACKAGE BODY                                   NPF_COMMON_PKG IS
/*

Description:  Common package for the whole NPF application


Program Units:

  decompose_consolidation (procedure) - Returns the accounts within a consolidation
								        and key info about the consolidation

  get_account_details (procedure) - Returns all account information in two cursors
                                    for the account key passed in

  get_rpt_acct_consl_list (function) - Returns the consolidations and accounts
                                    viewable by this user for this client

  get_user_query_sk (function) - Returns the user_sk that should be used for this user
                                 when working with the passed in customer

  what_version (function) - Returns version information for this package.


  npf_get_attrb_hdr_txt (procedure)- <This is a common procedure which will be used
                                       by all reports for getting attribute header
                                       texts>

  npf_division_function (function) - <This is a common function which will be used
                                      by all reports for performing division>

  npf_asst_typ_mgr(procedure)     - <The SELECT procedure serves as a common module
                                      in VFO reporting applications. It takes in the
                                      Issue Type and Reorting Type as the arguments
                                      (input parameters) and gives supercategory and
                                      subcategory codes and descriptions as out
                                      parameters for a given reporting type and a
                                      given issue type>

  npf_date_cal_mgr (procedure)     - <This is a common module which is used to
                                      calculate current business day, previous
                                      business day,previous month end,previous
                                      quarter end, previous year end, last business
                                      day of month, first business day of month>

  npf_date_val_mgr (procedure)     - <This common module Validates the entered Dates
                                      and Checks for the Date Format. It checks
                                      whether the begin date or end date entered are
                                      greater than the system date.It also checks
                                      whether the begin date is greater than the End
                                      date.Also it checks if both the entered dates
                                      are same then for positional reports.It checks
                                      for whether the date is greater than system
                                      date>

  npf_tran_typ_mgr (procedure)     - <This Common Module retrieves the fields from
                                      NPF_TRAN_CATG table corresponding to a given
                                      Tran Code and Data source Id and The Reporting
                                      Type.This common module gives us the tran code
                                      along with the corresponding SuperCategory and
                                      SubCategory Codes and Descriptions>

  npf_valn_mgr   (procedure)         - <This is a common module which is used to
                                      calculate valuation frequency decode and
                                      valuation run time for the given account id and
                                      date passed>

  npf_para_typ_mgr (procedure)     - <This is a common module which is used to call
                                      Account/Consolidation manager based on the
                                      value of Account/Consolidation concatenated and
                                      then retrieve the data from them. This also
                                      calls valuation manager to determine valuation
                                      frequency decode and valuation run time>
*/
/*
--*************************************************************************
--*NOTE: The Version and revision information will come from PVCS. *
--*************************************************************************

 --  Date Written          : $Date:   Sep 29 2014 11:51:22  $
 --  Last Revision         : $Modtime:   Sep 04 2014 11:20:46  $
 --  Author                : $Author:   am363  $
 --  Revision              : $Revision:   1.38  $
 --  History               : $Log:   //pvcsproddata/pvcs_prod/npf/archives/database/plsql/npf_common_pkg.pkb-arc  $

-- R9.1 DEC 04 2020 Global Data Load Changes

   Rev 1.39 Sep 17 2025  aj250
   Added rule evaluation for reports

   Rev 1.38   Sep 29 2014 11:51:22   am363
R7.5 Change

   Rev 1.36   Apr 04 2012 06:34:42   sp167
get account based on data src id for nws data loading- on top of v1.34

   Rev 1.35   Mar 28 2012 06:18:40   sp167
get account based on data src id for nws data loading- on top of v1.34

   Rev 1.34   Nov 04 2011 10:36:24   sp167
P22870 - decoder changes is added for Consolidation List - On Top Of v1.29

   Rev 1.29   May 28 2010 16:46:26   kv18
I20088 : Removed the invalid package name reference. Changes made on top of 1.29

   Rev 1.28   May 27 2010 17:08:42   kv18
I20088 : Changed made for removing TRUNC from Valuation as of date

   Rev 1.27   Dec 31 2009 05:07:16   ag130
D18344 - Modified the review comments. Checked in on top of v1.26

   Rev 1.26   Dec 30 2009 06:26:28   ag130
D18344 - Incorporated code review comments. Checked in on top of  v1.25

   Rev 1.25   18 Dec 2009 07:06:18   st111
D18344 - Changes done on top of V1.24.

   Rev 1.24   Dec 03 2009 06:09:00   ag130
D18344 - Added new NPF_ASST_TYP_MGR() overloaded procedure  and GET_CSTM_CNTRY_RISK_DESC procedure to retrieve the custom asset sup and sub category and custom country of risk descriptions.
Changes done on top v1.23

   Rev 1.23   Oct 19 2009 14:10:36   MC178
Changes done for Data Mask.


   Rev 1.23   Oct 19 2009 17:19:08   mc178
Changes done for Account Masking.

   Rev 1.22   Mar 31 2008 17:19:08   ma147
EMEA - Updated union clause in decompose_consolidation proc to return null for bse_curr_dcde in the ref cursor

   Rev 1.21   Feb 29 2008 02:14:14   ss289
EMEA - Updated call to decompose_consolidation proc to return bse_curr_dcde in the ref cursor

   Rev 1.20   Oct 22 2007 06:47:28   ma147
Docket 11323 - Updated decompose_consolidation proc to return data_src_id in the ref cursor

   Rev 1.19   Jun 06 2006 13:40:46   SG78
Removed parameter manager and get_account_details functions. Moved to npf_common_rpts_pkg instead.

   Rev 1.18   May 03 2006 10:13:10   SG78
Modified the npf_para_typ_mgr2 function to exclude Synergy reports from Security check.

   Rev 1.17   Apr 14 2006 17:02:22   SG78
Modified npf_para_typ_mgr2 to raise error if the user does not sufficient access to execute the report.
Also returned back ac_sort_ord to the pg_acmgr_rec record layout.

   Rev 1.16   Mar 24 2006 10:53:18   bn21
Changed npf_para_typ_mgr and npf_para_typ_mgr2 to fetch sort_nbr when calling decompose_consolidation

   Rev 1.15   Mar 24 2006 08:56:36   bn21
Changes for PCP Reporting - New column added to consol_cmpnt table to indicate the sort order of components in a consol

   Rev 1.14   Dec 16 2005 08:03:38   SG78
PCPDR2005-10012 - Modifed valn_mgr to trunc the full timestamp when doing between check. This will shield us from AM or PM timestamps.

   Rev 1.13   Nov 29 2005 08:16:24   SG78
ITR619997 - Commented out code in valn_mgr that overwrote a periodic position with an information one if the periodic was not approved for the last business day of the month.

   Rev 1.12   Sep 19 2005 16:16:26   bs70
SIR 994
Added additional mode flag to date_cal_mgr to return previous business days the way we want in account market value report.

   Rev 1.11   Sep 19 2005 15:43:20   ka29
Added authorization checks in case user no longer has access to a customer

   Rev 1.10   Jul 24 2005 16:54:30   mm155
updated call to valuation manager in para_typ_mgr2
procedure and also added val. max begin and end output to  po_valnmgr_table cursor

   Rev 1.9   Jul 24 2005 15:25:42   sw12
Added changes for the para_typ_mgr due to changes to the valn_mgr changes

   Rev 1.8   Jul 24 2005 08:30:14   sw12
1. valn mgr fix for reports
2. sort change for get_rpt_acct_cnsl_list

   Rev 1.7   Apr 24 2005 14:03:00   ka29
Fixed get_rpt_Act_consl_list to only include consolidations the user has requested to be included in reporting drop down

   Rev 1.6   Apr 24 2005 13:49:14   ka29
Added internal id support to decompose_consolidation and get_rpt_acct_consl_list

   Rev 1.5   Apr 11 2005 08:48:24   ka29
Added new fields to decompose_consolidation and get_account_details cursor

   Rev 1.4   Mar 18 2005 08:58:20   sw12
The column ac_creat_user_id was changed to ac_creat_user_sk on the database
*/

  -- *****************************************************************************************
  -- Declare package variables.
  -- *****************************************************************************************

pg_package_c CONSTANT VARCHAR2(30) := 'npf_common_pkg';
pg_version_c CONSTANT VARCHAR2(30) := '$Revision:   1.38  $';
/* Global constants for Date Calculation Manager                                   */
pg_amvc_prev_buss_day_c CONSTANT VARCHAR2(1) := 'x';
pg_curr_buss_day_c CONSTANT VARCHAR2(1) := 'c';
pg_prev_buss_day_c CONSTANT VARCHAR2(1) := 'b';
pg_prev_mth_end_c CONSTANT VARCHAR2(1) := 'm';
pg_prev_qt_end_c CONSTANT VARCHAR2(1) := 'q';
pg_prev_year_end_c CONSTANT VARCHAR2(1) := 'y';
pg_first_busn_day_of_mth_c CONSTANT VARCHAR2(1) := 'f';
pg_last_busn_day_of_mth_c CONSTANT VARCHAR2(1) := 'l';
pg_weekend_sat_c CONSTANT VARCHAR2(10) := 'saturday';
pg_weekend_sun_c CONSTANT VARCHAR2(10) := 'sunday';
pg_weekend_mon_c CONSTANT VARCHAR2(10) := 'monday';
pg_weekend_tue_c CONSTANT VARCHAR2(10) := 'tuesday';
pg_oracle_func_constant_c CONSTANT VARCHAR2(10) := 'fmday';
pg_oracle_mth_constant_c CONSTANT VARCHAR2(5) := 'mm';
pg_oracle_qt_constant_c CONSTANT VARCHAR2(5) := 'q';
PG_ORACLE_YR_CONSTANT_C CONSTANT VARCHAR2(5) := 'yy';
pg_2bus_day_prior_c CONSTANT VARCHAR2(2) := '2b';
/* Global constants for Valuation Manager                                          */
pg_flag_mth_booked_c CONSTANT VARCHAR2(1) := 'P';
pg_flag_dly_info_c CONSTANT VARCHAR2(1) := 'I';
pg_flag_posn_c CONSTANT VARCHAR2(1) := 'p';
pg_flag_tran_c CONSTANT VARCHAR2(1) := 't';
pg_valn_appr_flag_true_c CONSTANT VARCHAR2(1) := 'Y';

/* Global constants for Parameter Manager                                          */
pg_object_account_c CONSTANT VARCHAR2(10) := 'ACCOUNT';
pg_object_consl_c CONSTANT VARCHAR2(10) := 'CONSL';
pg_accounts_only_yes_c CONSTANT VARCHAR2(1) := 'y';

/* Global constants Used by Date Validation manager                                */
--pg_package_c CONSTANT VARCHAR2(100) := 'NPF_IFS_PKG';
pg_date_time_format_c  VARCHAR2(100) := 'YYYY-MM-DD HH.MI.SS AM';
pg_trunc_by_c CONSTANT VARCHAR2(20) := 'HH';
pg_dash_c CONSTANT VARCHAR2(1) := '-';
pg_err_type_c VARCHAR2(20) := 'ORACLE';
pg_user_err_type_c VARCHAR2(20) := 'USER DEF';
pg_std_date_format_c VARCHAR2(50) := 'YYYY-MM-DD';

/* Global constants for Asset Type manager                                         */
pg_supcatg_asset_code_c VARCHAR2(10) := '30';
pg_subcatg_asset_code_c VARCHAR2(10) := '20';
pg_supcatg_asset_desc_c VARCHAR2(100) := 'Other Assets';
pg_subcatg_asset_desc_c VARCHAR2(100) := 'Miscellaneous';
pg_cntry_risk_code_c VARCHAR2(10) ;
pg_cntry_risk_desc_c VARCHAR2(100);

/* Gloval constants for Transaction Type Manager                                   */
pg_supcatg_tran_code_c VARCHAR2(10) := 'FNDDSB';
pg_subcatg_tran_code_c VARCHAR2(10) := 'FNDDSBB99';
pg_subcatg_tran_desc_c VARCHAR2(100) := 'Others';
pg_supcatg_tran_desc_c VARCHAR2(100) := 'Funding and Disbursements';
pg_not_applicable_c CONSTANT VARCHAR2(2) := 'NA';
  -- used to log the detrails in npf_rpt_hist
    pg_rpt_hist_sk      npf_rpt_hist.rpt_hist_sk %TYPE;
    pg_task_note_a      npf_rpt_hist.task_note%TYPE;
    PG_ERR_EV_ID        NPF_RPT_HIST.ERR_EV_ID%type;


  -- *****************************************************************************************
  -- Declare package exceptions.
  -- *****************************************************************************************
  NOT_AUTHORIZED_EXCEPTION EXCEPTION;
  PRAGMA EXCEPTION_INIT (NOT_AUTHORIZED_EXCEPTION, -20023);

  NOT_ACTIVE_EXCEPTION EXCEPTION;
  PRAGMA EXCEPTION_INIT (NOT_ACTIVE_EXCEPTION, -20024);

  -- *****************************************************************************************
  -- Declare global program units.
  -- *****************************************************************************************


  -- Name: decompose_consolidation
  --
  -- Type: Procedure
  --
  -- Description: Returns the consolidation accounts and key information
  --
  -- Techinical:
  --
  -- Notes:
  --
  -- Syntax: decompose_consolidation( p_consl_sk,
  --			   			p_user_sk,
  --                        p_accounts_only,
  --						p_cust_sk,
  -- 						p_consl_desc,
  --                        p_creat_by,
  --                        p_upd_by,
  --                        p_upd_tm,
  --						p_cur_out
  --				)
  -- Where: p_consl_sk = the identifier of the consolidation to decompose
  --        p_user_sk = the identifier of the user who is requesting the decompose (or being emulated)
  --        p_accounts_only = 'Y' if decompose should occur at the account level, 'N' if consolidations
  --                within the consolidation should be returned as is
  --		p_cust_sk = output of the identifier of the customer to which this consolidation is linked
  --		p_consl_desc = output of the description of the consolidation
  --        p_creat_by = the user id who created the consolidation
  --        p_upd_by = the user id who updated the consolidation most recently
  --        p_upd_tm = the time when the consolidation was last updated
  --		p_cur_out = the cursor which is output containing all of the accounts within the consolidation
  --
  -- Returns:
  --		p_cust_sk = output of the identifier of the customer to which this consolidation is linked
  --		p_consl_desc = output of the description of the consolidation
  --		p_cur_out = the cursor which is output containing all of the accounts within the consolidation
  --        p_creat_by = the user id who created the consolidation
  --        p_upd_by = the user id who updated the consolidation most recently
  --        p_upd_tm = the time when the consolidation was last updated



 PROCEDURE decompose_consolidation( p_consl_sk 		IN npf_consl.consl_sk%TYPE,
			   			p_user_sk 		IN npf_consl_user_access.user_sk%TYPE,
						p_accounts_only IN CHAR DEFAULT 'Y',
                        p_cust_sk		OUT npf_consl.cust_sk%TYPE,
						p_consl_desc	OUT npf_consl.consl_desc%TYPE,
                        p_creat_by      OUT npf_consl.creat_by%TYPE,
                        p_upd_by        OUT npf_consl.upd_by%TYPE,
                        p_upd_tm        OUT npf_consl.upd_tm%TYPE,
						p_cur_out     	OUT SYS_REFCURSOR
				)
IS

	v_procedure_c CONSTANT VARCHAR2(30)  := 'decompose_consolidation';

	v_access_i INTEGER := 0; -- this variable is used to determine whether or not
                                   -- the user has access to the consolidation

    v_parms_c    VARCHAR2(4000);  -- This variable records the calling parameters for
                                  -- debugging and error recording operations.

    v_location_i INTEGER;  -- This variable tracks our location within this procedure.

    v_user_sk npf_user.user_sk%TYPE;

    v_auth_rc NUMBER;
    v_duration NUMBER;
    v_login_id NPF_USER.login_id%TYPE;
    v_generic_type CHAR(2) := 'GI';
    v_decoder_consl          VARCHAR2(15);
    v_data_src_id   npf_account.data_src_id%type;

        -- Added for time logging R7.2 Reg
    V_SCHED_FLG           varchar2(1);
    v_decomp_consolidation_templ constant number(6) := 899995;
    v_dflt_rptg_type npf_user.dflt_rptg_type%type;
BEGIN

    v_auth_rc := 0;
    v_duration := 0;

	p_cust_sk := NULL;
	p_consl_desc := NULL;
    p_creat_by := NULL;
    p_upd_by := NULL;
    p_upd_tm := NULL;

    v_location_i := 1;

    -- Obtain the output values that do not vary for each row, if the row
    -- is not found, then the consolidation is not active, return not active consolidation
    -- IMPLICIT CURSOR is being used because the where clause is the primary key, the not
    -- found situation is explicitly handled to provide a specific error message, if multiple
    -- rows are found, the overall exception WHEN OTHERS will occur in the end of procedure
    -- exception handling.
     /*Store the metrics information in the audit table by calling npf_star_rpt procedure*/
BEGIN
		   pg_rpt_hist_sk     :=0;
		   PG_ERR_EV_ID       :=0;
      v_sched_flg        := 'N';

      pg_task_note_a := 'v_procedure_c  '||	v_procedure_c||
                             ', p_accounts_only = '||p_accounts_only||
                             ', p_cust_sk   = '||p_cust_sk||
                             ', p_consl_desc   = '||p_consl_desc||
                             ', p_creat_by   = '||p_creat_by||
                             ', p_upd_by   = '||p_upd_by||
                             ', p_upd_tm   = '||p_upd_tm||
                             ', p_consl_sk   = '||p_consl_sk||
                             ', p_user_sk    = '||p_user_sk;

		   npf_rpt_hist_pkg.npf_start_rpt_log(p_obj_desc_c => p_cust_sk,
                                            p_user_sk_a  => 0 ,
                                            p_cust_sk_a  => 0,
                                            p_task_note => pg_task_note_a,
                                            p_template_id_n =>v_decomp_consolidation_templ,
                                            p_sched_flag=>v_sched_flg,
                                            p_rpt_hist_sk =>pg_rpt_hist_sk);

end;

BEGIN
    	/* P22870 - added decoder consl details */
SELECT -- consl_desc, cust_sk, creat_by, upd_by, upd_tm
       DECODE(consl_stat_dcde,'DECODER',NULL,consl_desc),
       cust_sk, creat_by, upd_by, upd_tm,consl_stat_dcde
INTO p_consl_desc,
    p_cust_sk,
    p_creat_by,
    p_upd_by,
    p_upd_tm,
    v_decoder_consl
FROM npf_consl
WHERE consl_sk = p_consl_sk
  AND (consl_stat_dcde = 'ACTIVE' OR consl_stat_dcde = 'DECODER');
EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE NOT_ACTIVE_EXCEPTION;
END;

    v_location_i := 2;

    -- IMPLICIT CURSOR is being used because the where clause is the primary key, the not
    -- found situation is explicitly handled to provide a specific error message, if multiple
    -- rows are found, the overall exception WHEN OTHERS will occur in the end of procedure
    -- exception handling.
BEGIN
SELECT login_id, dflt_rptg_type
INTO v_login_id, v_dflt_rptg_type
FROM npf_user
WHERE user_sk = p_user_sk;
EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE NOT_AUTHORIZED_EXCEPTION;
END;

    --check for authorization
    -- skip auth check if id is a generic id, because it will fail

    IF (v_generic_type != npf_security_pkg.get_user_type(p_user_sk)) THEN

        v_location_i := 3;

        v_auth_rc := npf_asa_canaliasviewcustomer.canaliasviewcustomer(v_login_id,TO_CHAR(p_cust_sk));

        IF (v_auth_rc > 0) THEN
           RAISE NOT_AUTHORIZED_EXCEPTION;
END IF;

END IF; -- end if not generic

    v_location_i := 5;

    -- Need to get the generic id if this is a user calling the decompose method, after which
    -- any joins to user_access tables should use the result v_user_sk rather than passed in value

    v_user_sk := npf_security_pkg.get_generic_id(p_user_sk,p_cust_sk);


    v_location_i := 10;

    -- Verify that the user has access to the consolidation
    -- if not, return not authorized error, use of IMPLICIT CURSOR is due to looking for
    -- a count using primary key values, 0 or 1 result is expected, if more than one then
    -- the user still has access

SELECT COUNT(*)
INTO v_access_i
FROM npf_consl_user_access
WHERE consl_sk = p_consl_sk
  AND user_sk = v_user_sk
  AND consl_user_stat_dcde = 'ACTIVE' ;

IF(v_decoder_consl = 'ACTIVE') then
          IF v_access_i = 0             THEN
                RAISE NOT_AUTHORIZED_EXCEPTION;
END IF;
END IF;

    -- Check whether we should return the consolidation makeup down to the account level
    -- or if we should include consolidations which makeup this consolidation

    -- if need to return results down to the account level
    IF p_accounts_only = 'Y' THEN

        v_location_i := 20;

    -- still need to implement for consolidations within consolidations as specified in
    -- the program specs.  Not implemented yet because, consolidations within consolidations
    -- are not in the current requirements

OPEN p_cur_out
    FOR
SELECT ac.ac_sk,

    /* Data Mask Changes */
    /*ac.ac_id, */
       (CASE WHEN v_dflt_rptg_type = 'WLT' OR AC.DATA_SRC_ID = 7 THEN AC_ID ELSE NPF_DATA_MASK_PKG.GET_MASKED_ACID_FOR_ACSK(P_USER_SK,P_CUST_SK,AC.AC_SK) END) AC_ID,
       alias.ac_alias,
    /* Data Mask Changes */
    /*ac.ac_desc, */
       NVL(alias.UPD_AC_DESC,(CASE WHEN v_dflt_rptg_type = 'WLT' OR AC.DATA_SRC_ID = 7 THEN AC_DESC ELSE NPF_DATA_MASK_PKG.GET_MASKED_AC_NAME(P_USER_SK,P_CUST_SK,AC.AC_SK,AC.AC_DESC) END)) AC_DESC, --R8.0
       cmpnt.cmpnt_dcde, cmpnt.sort_nbr, ac.data_src_id , ac.bse_curr_dcde
FROM npf_account ac,
     npf_cust_ac_alias alias,
     npf_consl consl,
     npf_consl_cmpnt cmpnt
WHERE
    consl.consl_sk IN (p_consl_sk)
  AND cmpnt.consl_sk = consl.consl_sk
  AND cmpnt.cmpnt_dcde = 'ACCOUNT'
  AND cmpnt.cmpnt_sk_val = ac.ac_sk
  AND cmpnt.consl_cmpnt_stat_dcde = 'ACTIVE'
  AND alias.cust_sk = consl.cust_sk
  AND alias.ac_sk = ac.ac_sk
  AND NOT EXISTS (
-- this first sub select would return a row if any account in the consolidation (or sub consolidation) is not
-- accessible by the user, it should be executed once based on how it is written, therefore the NOT EXISTS is
-- used because if this returns a row, no accounts
-- should be returned
    SELECT 1
    FROM npf_account ac2,
         npf_consl consl2,
         npf_consl_cmpnt cmpnt2
    WHERE
        consl2.consl_sk IN (p_consl_sk)
      AND cmpnt2.consl_sk = consl2.consl_sk
      AND cmpnt2.cmpnt_dcde = 'ACCOUNT'
      AND cmpnt2.cmpnt_sk_val = ac2.ac_sk
      AND cmpnt2.consl_cmpnt_stat_dcde = 'ACTIVE'
      AND NOT EXISTS (
-- this subselect returns a row if the user has access to the account, the not exists looks for an account where the
-- user does not have access
        SELECT 1
        FROM npf_ac_cust_user acu
        WHERE acu.ac_sk = ac2.ac_sk
          AND acu.cust_sk = consl2.cust_sk
          AND acu.user_sk = v_user_sk
    ) -- end inner subselect
) -- end outer subselect
;

-- P22870 for Tax Letter Report - Starts
ELSIF p_accounts_only = 'D' THEN

            v_location_i := 30;

OPEN p_cur_out FOR

SELECT DISTINCT
    ac_sk,
    ac_id,
    ac_alias,
    ac_desc,
    cmpnt_dcde,
    sort_nbr,
    data_src_id,
    bse_curr_dcde
FROM
    (
        SELECT DISTINCT
            COUNT(ndx.DECODER_AC_SK) over (PARTITION BY ndx.DECODER_AC_SK) enrl_decoder_sk,
                ndx.DECODER_AC_SK decoder_sk,
            ndx.CMPNT_DATA_SRC_ID dec_data_src_id,
            ndx.DECODER_AC_ID decoder_ac_id,
            ac.ac_sk,

            /* Data Mask Changes */
            /*ac.ac_id, */
            (CASE WHEN v_dflt_rptg_type = 'WLT' OR AC.DATA_SRC_ID = 7 THEN AC_ID ELSE NPF_DATA_MASK_PKG.GET_MASKED_ACID_FOR_ACSK(P_USER_SK,P_CUST_SK,AC.AC_SK) END) AC_ID,
            alias.ac_alias,
            /* Data Mask Changes */
            /*ac.ac_desc, */
            NVL(alias.UPD_AC_DESC,(CASE WHEN v_dflt_rptg_type = 'WLT' OR AC.DATA_SRC_ID = 7 THEN AC_DESC ELSE NPF_DATA_MASK_PKG.GET_MASKED_AC_NAME(P_USER_SK,P_CUST_SK,AC.AC_SK,AC.AC_DESC) END)) AC_DESC, --R8.0
            cmpnt.cmpnt_dcde, cmpnt.sort_nbr, ac.data_src_id , ac.bse_curr_dcde
        FROM npf_account ac,
             npf_cust_ac_alias alias,
             npf_consl consl,
             npf_consl_cmpnt cmpnt,
             npf_ac_cust_user xref,
             NPF_DECODER_XREF ndx
        WHERE
            consl.consl_sk IN (p_consl_sk)
          AND cmpnt.consl_sk = consl.consl_sk
          AND cmpnt.cmpnt_dcde = 'ACCOUNT'
          AND cmpnt.cmpnt_sk_val = ac.ac_sk
          AND cmpnt.consl_cmpnt_stat_dcde = 'ACTIVE'
          AND alias.cust_sk = consl.cust_sk
          AND alias.ac_sk = ac.ac_sk
          AND xref.user_sk = v_user_sk
          AND xref.cust_sk = p_cust_sk
          AND ac.ac_sk = xref.ac_sk
          AND xref.ac_sk =ndx.CMPNT_AC_SK(+)
          AND ndx.CUST_SK(+) = p_cust_sk
          AND NOT EXISTS (
            -- this first sub select would return a row if any account in the consolidation (or sub consolidation) is not
            -- accessible by the user, it should be executed once based on how it is written, therefore the NOT EXISTS is
            -- used because if this returns a row, no accounts
            -- should be returned
            SELECT 1
            FROM npf_account ac2,
                 npf_consl consl2,
                 npf_consl_cmpnt cmpnt2
            WHERE
                consl2.consl_sk IN (p_consl_sk)
              AND cmpnt2.consl_sk = consl2.consl_sk
              AND cmpnt2.cmpnt_dcde = 'ACCOUNT'
              AND cmpnt2.cmpnt_sk_val = ac2.ac_sk
              AND cmpnt2.consl_cmpnt_stat_dcde = 'ACTIVE'
              AND NOT EXISTS (
                -- this subselect returns a row if the user has access to the account, the not exists looks for an account where the
                -- user does not have access
                SELECT 1
                FROM npf_ac_cust_user acu
                WHERE acu.ac_sk = ac2.ac_sk
                  AND acu.cust_sk = consl2.cust_sk
                  AND acu.user_sk = v_user_sk
            ) -- end inner subselect
        ) -- end outer subselect

    )ac_det, (SELECT
                  DECODER_AC_SK ,
                  COUNT(DECODER_AC_SK) over (PARTITION BY DECODER_AC_SK) tot_dec_ac
              FROM
                  NPF_DECODER_XREF
              WHERE CUST_SK = p_cust_sk) tot_decoder_ac
WHERE tot_decoder_ac.DECODER_AC_SK(+) =  ac_det.decoder_sk
  AND
    (CASE
         WHEN enrl_decoder_sk > 0
             AND (tot_dec_ac - enrl_decoder_sk ) = 0
             AND tot_dec_ac = 2
             AND ac_det.dec_data_src_id = 1
             THEN 'y'
         WHEN enrl_decoder_sk > 0
             AND (tot_dec_ac - enrl_decoder_sk ) = 0
             AND tot_dec_ac = 1
             THEN 'y'
         WHEN enrl_decoder_sk > 0
             AND (tot_dec_ac - enrl_decoder_sk ) = 0
             AND tot_dec_ac = 2
             AND ac_det.dec_data_src_id = 2
             THEN 'n'
         ELSE 'y'
        END)  = 'y'  ;
--P22870 for Tax Letter Report - Ends

ELSIF p_accounts_only = 'N' THEN
    -- return the consolidation makeup including base consolidations, not just accounts

           v_location_i := 50;

           --P22870 - modified query for Decoder Accounts
OPEN p_cur_out FOR

SELECT DISTINCT
    CASE WHEN enrl_decoder_sk > 0 AND (tot_dec_ac - enrl_decoder_sk ) = 0
             THEN DECODER_SK
         ELSE ac_sk
        END ac_sk,
    CASE WHEN enrl_decoder_sk > 0 AND (tot_dec_ac - enrl_decoder_sk ) = 0
             THEN DECODER_AC_ID
         ELSE ac_id
        END ac_id,
    ac_alias,
    ac_desc,
    cmpnt_dcde,
    sort_nbr,
    data_src_id,
    bse_curr_dcde,
    CASE WHEN enrl_decoder_sk > 0 AND (tot_dec_ac - enrl_decoder_sk ) = 0
             THEN 'Y'
         ELSE 'N'
        END decoder_acct_flag
FROM
    (
        SELECT DISTINCT
            COUNT(ndx.DECODER_AC_SK) over (PARTITION BY ndx.DECODER_AC_SK) enrl_decoder_sk,
                ndx.DECODER_AC_SK decoder_sk,
            ndx.CMPNT_DATA_SRC_ID dec_data_src_id,
            ndx.DECODER_AC_ID decoder_ac_id,
            ac.ac_sk,
            /* Data Mask Changes */
            /*ac.ac_id, */
            (CASE WHEN v_dflt_rptg_type = 'WLT' OR AC.DATA_SRC_ID = 7 THEN AC_ID ELSE NPF_DATA_MASK_PKG.GET_MASKED_ACID_FOR_ACSK(P_USER_SK,P_CUST_SK,AC.AC_SK) END) AC_ID,
            alias.ac_alias,
            /* Data Mask Changes */
            /*ac.ac_desc, */
            NVL(alias.UPD_AC_DESC,(CASE WHEN v_dflt_rptg_type = 'WLT' OR AC.DATA_SRC_ID = 7 THEN AC_DESC ELSE NPF_DATA_MASK_PKG.GET_MASKED_AC_NAME(P_USER_SK,P_CUST_SK,AC.AC_SK,AC.AC_DESC) END)) AC_DESC,--R8.0
            cmpnt.cmpnt_dcde, cmpnt.sort_nbr, ac.data_src_id , ac.bse_curr_dcde
        FROM npf_account ac,
             npf_cust_ac_alias alias,
             npf_consl consl,
             npf_consl_cmpnt cmpnt,
             npf_ac_cust_user xref,
             NPF_DECODER_XREF ndx
        WHERE
            consl.consl_sk IN (p_consl_sk)
          AND cmpnt.consl_sk = consl.consl_sk
          AND cmpnt.cmpnt_dcde = 'ACCOUNT'
          AND cmpnt.cmpnt_sk_val = ac.ac_sk
          AND cmpnt.consl_cmpnt_stat_dcde = 'ACTIVE'
          AND alias.cust_sk = consl.cust_sk
          AND alias.ac_sk = ac.ac_sk
          AND xref.user_sk = v_user_sk
          AND xref.cust_sk = p_cust_sk
          AND ac.ac_sk = xref.ac_sk
          AND xref.ac_sk =ndx.CMPNT_AC_SK(+)
          AND ndx.CUST_SK(+) = p_cust_sk
          AND NOT EXISTS (
-- this first sub select would return a row if any account in the consolidation (or sub consolidation) is not
-- accessible by the user, it should be executed once based on how it is written, therefore the NOT EXISTS is
-- used because if this returns a row, no accounts
-- should be returned
            SELECT 1
            FROM npf_account ac2,
                 npf_consl consl2,
                 npf_consl_cmpnt cmpnt2
            WHERE
                consl2.consl_sk IN (p_consl_sk)
              AND cmpnt2.consl_sk = consl2.consl_sk
              AND cmpnt2.cmpnt_dcde = 'ACCOUNT'
              AND cmpnt2.cmpnt_sk_val = ac2.ac_sk
              AND cmpnt2.consl_cmpnt_stat_dcde = 'ACTIVE'
              AND NOT EXISTS (
-- this subselect returns a row if the user has access to the account, the not exists looks for an account where the
-- user does not have access
                SELECT 1
                FROM npf_ac_cust_user acu
                WHERE acu.ac_sk = ac2.ac_sk
                  AND acu.cust_sk = consl2.cust_sk
                  AND acu.user_sk = v_user_sk
            ) -- end inner subselect
        ) -- end outer subselect

    )ac_det, (SELECT
                  DECODER_AC_SK ,
                  COUNT(DECODER_AC_SK) over (PARTITION BY DECODER_AC_SK) tot_dec_ac
              FROM
                  NPF_DECODER_XREF
              WHERE CUST_SK = p_cust_sk) tot_decoder_ac
WHERE tot_decoder_ac.DECODER_AC_SK(+) =  ac_det.decoder_sk
  AND
    (CASE
         WHEN enrl_decoder_sk > 0
             AND (tot_dec_ac - enrl_decoder_sk ) = 0
             AND tot_dec_ac = 2
             AND ac_det.dec_data_src_id = 1
             THEN 'y'
         WHEN enrl_decoder_sk > 0
             AND (tot_dec_ac - enrl_decoder_sk ) = 0
             AND tot_dec_ac = 1
             THEN 'y'
         WHEN enrl_decoder_sk > 0
             AND (tot_dec_ac - enrl_decoder_sk ) = 0
             AND tot_dec_ac = 2
             AND ac_det.dec_data_src_id = 2
             THEN 'n'
         ELSE 'y'
        END)  = 'y'
UNION
-- the second select in the UNION returns the base consolidations
SELECT sub.consl_sk, NULL, NULL, sub.consl_desc, cmpnt.cmpnt_dcde, cmpnt.sort_nbr, NULL, NULL, 'N'
FROM npf_consl consl,
     npf_consl sub,
     npf_consl_cmpnt cmpnt
WHERE
    consl.consl_sk = p_consl_sk
  AND cmpnt.consl_sk = consl.consl_sk
  AND cmpnt.cmpnt_dcde = 'CONSL'
  AND cmpnt.cmpnt_sk_val = sub.consl_sk
  AND cmpnt.consl_cmpnt_stat_dcde = 'ACTIVE' ;

-- For nws data loading
ELSIF p_accounts_only IN ('1','2','3','4','5','6','7','8','10','12')  THEN

        v_data_src_id := p_accounts_only ;

        v_location_i := 55;

OPEN p_cur_out
    FOR
-- the first select in the union returns the accounts
SELECT ac.ac_sk,
    /* Data Mask Changes */
    /*ac.ac_id, */
       (CASE WHEN v_dflt_rptg_type = 'WLT' OR AC.DATA_SRC_ID = 7 THEN AC_ID ELSE NPF_DATA_MASK_PKG.GET_MASKED_ACID_FOR_ACSK(P_USER_SK,P_CUST_SK,AC.AC_SK) END) AC_ID,
       alias.ac_alias,
    /* Data Mask Changes */
    /*ac.ac_desc, */
       NVL(alias.UPD_AC_DESC,(CASE WHEN v_dflt_rptg_type = 'WLT' OR AC.DATA_SRC_ID = 7 THEN AC_DESC ELSE NPF_DATA_MASK_PKG.GET_MASKED_AC_NAME(P_USER_SK,P_CUST_SK,AC.AC_SK,AC.AC_DESC) END)) AC_DESC, --R8.0
       cmpnt.cmpnt_dcde, cmpnt.sort_nbr, ac.data_src_id, ac.bse_curr_dcde
FROM npf_account ac,
     npf_cust_ac_alias alias,
     npf_consl consl,
     npf_consl_cmpnt cmpnt
WHERE
    consl.consl_sk = p_consl_sk
  AND cmpnt.consl_sk = consl.consl_sk
  AND cmpnt.cmpnt_dcde = 'ACCOUNT'
  AND cmpnt.cmpnt_sk_val = ac.ac_sk
  AND cmpnt.consl_cmpnt_stat_dcde = 'ACTIVE'
  AND alias.cust_sk = consl.cust_sk
  AND alias.ac_sk = ac.ac_sk
  AND ac.data_src_id = v_data_src_id
  AND NOT EXISTS (
    -- this first sub select would return a row if any account in the consolidation (or sub consolidation) is not
    -- accessible by the user, it should be executed once based on how it is written, therefore the NOT EXISTS is
    -- used because if this returns a row, no accounts
    -- should be returned
    SELECT 1
    FROM npf_account ac2,
         npf_consl consl2,
         npf_consl_cmpnt cmpnt2
    WHERE
        consl2.consl_sk = p_consl_sk
      AND cmpnt2.consl_sk = consl2.consl_sk
      AND cmpnt2.cmpnt_dcde = 'ACCOUNT'
      AND cmpnt2.cmpnt_sk_val = ac2.ac_sk
      AND ac2.data_src_id = v_data_src_id
      AND ac2.ac_sk = ac.ac_sk
      AND cmpnt2.consl_cmpnt_stat_dcde = 'ACTIVE'
      AND NOT EXISTS (
        -- this subselect returns a row if the user has access to the account, the not exists looks for an account where the
        -- user does not have access
        SELECT 1
        FROM npf_ac_cust_user acu
        WHERE acu.ac_sk = ac2.ac_sk
          AND acu.cust_sk = consl2.cust_sk
          AND acu.user_sk = v_user_sk
    ) -- end inner subselect
) -- end outer subselect
UNION
-- the second select in the UNION returns the base consolidations
SELECT sub.consl_sk, NULL, NULL, sub.consl_desc, cmpnt.cmpnt_dcde, cmpnt.sort_nbr, NULL, NULL
FROM npf_consl consl,
     npf_consl sub,
     npf_consl_cmpnt cmpnt
WHERE
    consl.consl_sk = p_consl_sk
  AND cmpnt.consl_sk = consl.consl_sk
  AND cmpnt.cmpnt_dcde = 'CONSL'
  AND cmpnt.cmpnt_sk_val = sub.consl_sk
  AND cmpnt.consl_cmpnt_stat_dcde = 'ACTIVE';


ELSE
    -- return the consolidation makeup including base consolidations, not just accounts

        v_location_i := 60;

OPEN p_cur_out
    FOR
-- the first select in the union returns the accounts
SELECT ac.ac_sk,
    /* Data Mask Changes */
    /*ac.ac_id, */
       (CASE WHEN v_dflt_rptg_type = 'WLT' OR AC.DATA_SRC_ID = 7 THEN AC_ID ELSE NPF_DATA_MASK_PKG.GET_MASKED_ACID_FOR_ACSK(P_USER_SK,P_CUST_SK,AC.AC_SK) END) AC_ID,
       alias.ac_alias,
    /* Data Mask Changes */
    /*ac.ac_desc, */
       NVL(alias.UPD_AC_DESC,(CASE WHEN v_dflt_rptg_type = 'WLT' OR AC.DATA_SRC_ID = 7 THEN AC_DESC ELSE NPF_DATA_MASK_PKG.GET_MASKED_AC_NAME(P_USER_SK,P_CUST_SK,AC.AC_SK,AC.AC_DESC) END)) AC_DESC, --R8.0
       cmpnt.cmpnt_dcde, cmpnt.sort_nbr, ac.data_src_id, ac.bse_curr_dcde
FROM npf_account ac,
     npf_cust_ac_alias alias,
     npf_consl consl,
     npf_consl_cmpnt cmpnt
WHERE
    consl.consl_sk = p_consl_sk
  AND cmpnt.consl_sk = consl.consl_sk
  AND cmpnt.cmpnt_dcde = 'ACCOUNT'
  AND cmpnt.cmpnt_sk_val = ac.ac_sk
  AND cmpnt.consl_cmpnt_stat_dcde = 'ACTIVE'
  AND alias.cust_sk = consl.cust_sk
  AND alias.ac_sk = ac.ac_sk
  AND NOT EXISTS (
-- this first sub select would return a row if any account in the consolidation (or sub consolidation) is not
-- accessible by the user, it should be executed once based on how it is written, therefore the NOT EXISTS is
-- used because if this returns a row, no accounts
-- should be returned
    SELECT 1
    FROM npf_account ac2,
         npf_consl consl2,
         npf_consl_cmpnt cmpnt2
    WHERE
        consl2.consl_sk = p_consl_sk
      AND cmpnt2.consl_sk = consl2.consl_sk
      AND cmpnt2.cmpnt_dcde = 'ACCOUNT'
      AND cmpnt2.cmpnt_sk_val = ac2.ac_sk
      AND cmpnt2.consl_cmpnt_stat_dcde = 'ACTIVE'
      AND NOT EXISTS (
-- this subselect returns a row if the user has access to the account, the not exists looks for an account where the
-- user does not have access
        SELECT 1
        FROM npf_ac_cust_user acu
        WHERE acu.ac_sk = ac2.ac_sk
          AND acu.cust_sk = consl2.cust_sk
          AND acu.user_sk = v_user_sk
    ) -- end inner subselect
) -- end outer subselect
UNION
-- the second select in the UNION returns the base consolidations
SELECT sub.consl_sk, NULL, NULL, sub.consl_desc, cmpnt.cmpnt_dcde, cmpnt.sort_nbr, NULL, NULL
FROM npf_consl consl,
     npf_consl sub,
     npf_consl_cmpnt cmpnt
WHERE
    consl.consl_sk = p_consl_sk
  AND cmpnt.consl_sk = consl.consl_sk
  AND cmpnt.cmpnt_dcde = 'CONSL'
  AND cmpnt.cmpnt_sk_val = sub.consl_sk
  AND cmpnt.consl_cmpnt_stat_dcde = 'ACTIVE'
;

v_location_i := 70;

END IF;
 /*Store the metrics information in the audit table by calling npf_star_rpt procedure*/
BEGIN
		    	npf_rpt_hist_pkg.npf_stop_rpt( p_rpt_hist_sk  => pg_rpt_hist_sk,
													  p_err_ev_id => pg_err_ev_id);
end;

EXCEPTION
      WHEN NOT_AUTHORIZED_EXCEPTION THEN
          npf_err_pkg.parms2string(v_parms_c, 'p_consl_sk', p_consl_sk);
          npf_err_pkg.parms2string(v_parms_c, 'p_user_sk', p_user_sk);
          npf_err_pkg.parms2string(v_parms_c, 'p_accounts_only', p_accounts_only);
          npf_err_pkg.rec_stop (SQLCODE,
                                'USER DEF',
                                NULL,
                                v_parms_c,
                                v_location_i,
                                pg_package_c,
                                v_procedure_c);

WHEN NOT_ACTIVE_EXCEPTION THEN
          npf_err_pkg.parms2string(v_parms_c, 'p_consl_sk', p_consl_sk);
          npf_err_pkg.parms2string(v_parms_c, 'p_user_sk', p_user_sk);
          npf_err_pkg.parms2string(v_parms_c, 'p_accounts_only', p_accounts_only);
          npf_err_pkg.rec_stop (-20024,
                                'ORACLE',
                                NULL,
                                v_parms_c,
                                v_location_i,
                                pg_package_c,
                                v_procedure_c);

WHEN OTHERS THEN
          npf_err_pkg.parms2string(v_parms_c, 'p_consl_sk', p_consl_sk);
          npf_err_pkg.parms2string(v_parms_c, 'p_user_sk', p_user_sk);
          npf_err_pkg.parms2string(v_parms_c, 'p_accounts_only', p_accounts_only);
          npf_err_pkg.rec_stop (SQLCODE,
                                'ORACLE',
                                NULL,
                                v_parms_c,
                                v_location_i,
                                pg_package_c,
                                v_procedure_c);

END decompose_consolidation;


  /* End Changes for Data Mask */


  -- Name: get_rpt_acct_consl_list
  --
  -- Type: Function
  --
  -- Description: Returns the consolidations and accounts viewable by this user for this client
  --
  -- Techinical:
  --
  -- Notes: This procedure is used by the Custom Reporting Tool to provide the dropdown of
  --        accounts and consolidations on the modify query page.  DO NOT change this procedure
  --        without considering the effects on custom.
  --
  -- Syntax: get_rpt_acct_consl_list( p_cust_sk,
  --			   			p_login_id
  --				)
  --
  -- Where: p_cust_sk = the identifier of the customer whose the user is currently working on
  --        p_login_id = the identifier of the user who is requesting the list (or being emulated)
  --
  -- Returns:
  --		SYS_REFCURSOR = the list of consolidations and accounts
  --

 FUNCTION get_rpt_acct_consl_list(p_cust_sk 		IN npf_ac_cust_user.cust_sk%TYPE,
                                  p_login_id        IN npf_user.login_id%TYPE
				) RETURN SYS_REFCURSOR
 IS

	v_procedure_c CONSTANT VARCHAR2(30)  := 'get_rpt_acct_consl_list';

    v_user_sk npf_user.user_sk%TYPE;  -- variable to hold the user sk that should be used in query
    v_orig_user_sk npf_user.user_sk%TYPE; --variable to hold the actual user login, will be different than the sk to use in the query
                                            -- if the user is an internal

    v_cur_out SYS_REFCURSOR; -- the output cursor

    v_parms_c    VARCHAR2(4000);  -- This variable records the calling parameters for
                                  -- debugging and error recording operations.

    v_location_i INTEGER;  -- This variable tracks our location within this procedure.

    v_auth_rc INTEGER; -- This variable receives the authorization result from security

BEGIN

        v_location_i := 1;

        -- determine whether or not the user has access to the customer

        v_auth_rc := npf_asa_canaliasviewcustomer.canaliasviewcustomer(p_login_id,TO_CHAR(p_cust_sk));

        IF (v_auth_rc > 0) THEN
           RAISE NOT_AUTHORIZED_EXCEPTION;
END IF;

        v_location_i := 2;

 -- the login id was passed in, modify it to use the user_sk that should be associated with the
 -- login id given the customer being worked with by calling the get_user_query_sk function.
        v_user_sk := get_user_query_sk(p_login_id,p_cust_sk);
        v_orig_user_sk := v_user_sk;

        v_location_i := 5;

 -- given the user_sk returned, we need the generic id if it is internal so check the value
        v_user_sk := npf_security_pkg.get_generic_id(v_user_sk,p_cust_sk);

        v_location_i := 10;

 -- this cursor is designed to provide a list of consolidations and accounts with the
 -- consolidations appearing first in the list, followed by the accounts. Within each they
 -- are ordered by the description
 -- The first select below selects all of the consolidations which are ACTIVE and have
 -- an ACTIVE relationship to the user.  Since Custom is looking for the columns named code, decode
 -- and we are returning a mixture of consolidations and accounts the column aliased as code concatenates
 -- CONSL with the key.  The column returned aliased as decode looks to see if the consolidation has
 -- an MR consolidation id, if it does the MR consolidation id is returned as part of the description.
 -- The sortset column returns a 1 so that consolidations can be sorted before accounts, and the last
 -- column returns the value to sort within the consolidations.
OPEN v_cur_out FOR
-- this first select gets the reporting consolidations based on the real user logged in
SELECT consl.consl_sk,
       'CONSL' || consl.consl_sk AS code,
       CASE
           WHEN NVL(consl.consl_xref_id,'E')='E' THEN consl.consl_desc
           ELSE consl.consl_xref_id || ' - ' || consl.consl_desc
           END AS decode,
       1 AS sortset,
       consl.consl_desc AS sortcol
        ,acc.user_dflt_consl_flag    -- SW12 7-24-2005
FROM npf_consl consl,
     npf_consl_user_access acc
WHERE consl.cust_sk = p_cust_sk
  AND acc.consl_sk = consl.consl_sk
  AND acc.user_sk = v_orig_user_sk
  AND acc.consl_user_stat_dcde = 'ACTIVE'
  AND consl.consl_stat_dcde = 'ACTIVE'
  AND acc.rpt_incl_flag = 'Y'

UNION
-- this second select gets the generic internal consolidations in case the internal user hasn't set their flags yet
-- this select should not return anything if generic id wasn't returned - the not exists will see to that
SELECT consl.consl_sk,
       'CONSL' || consl.consl_sk AS code,
       CASE
           WHEN NVL(consl.consl_xref_id,'E')='E' THEN consl.consl_desc
           ELSE consl.consl_xref_id || ' - ' || consl.consl_desc
           END AS decode,
       1 AS sortset,
       consl.consl_desc AS sortcol
        ,acc.user_dflt_consl_flag   -- SW12 7-24-2005
FROM npf_consl consl,
     npf_consl_user_access acc
WHERE consl.cust_sk = p_cust_sk
  AND acc.consl_sk = consl.consl_sk
  AND acc.user_sk = v_user_sk
  AND acc.consl_user_stat_dcde = 'ACTIVE'
  AND consl.consl_stat_dcde = 'ACTIVE'
  AND acc.rpt_incl_flag = 'Y'
  AND NOT EXISTS ( SELECT 1
                   FROM npf_consl_user_access acc2
                   WHERE acc2.consl_sk = consl.consl_sk
                     AND acc2.user_sk = v_orig_user_sk
)
UNION
-- The second select in the UNION selects all of the accounts which have
-- an ACTIVE relationship to the user.  Since Custom is looking for the columns named code, decode
-- and we are returning a mixture of consolidations and accounts the column aliased as code concatenates
-- ACCOUNT with the key.  The column returned aliased as decode looks to see if the account has
-- an alias, if it does the alias is returned otherwise the default description is returned.
-- The sortset column returns a 2 so that consolidations can be sorted before accounts, and the last
-- column returns the value to sort within the accounts.

/* Start P22870  -  decoder details is incorporated instead of underlying accounts
      SELECT acct.ac_sk, 'ACCOUNT' || acct.ac_sk AS code,
             acct.ac_id || ' - ' || NVL(alias.ac_alias,acct.ac_desc) AS decode,
             2 AS sortset,
             NVL(alias.ac_alias,acct.ac_desc) AS sortcol
             ,'N'   -- SW12 7-24-2005
        FROM npf_account acct,
             npf_ac_cust_user acuser,
             npf_cust_ac_alias alias
       WHERE acuser.user_sk = v_user_sk
         AND acuser.cust_sk = p_cust_sk
         AND acuser.actv_flag = 'Y'
         AND acct.ac_sk = acuser.ac_sk
         AND alias.ac_sk = acct.ac_sk
         AND alias.cust_sk = p_cust_sk
       ORDER BY 4,6 desc,5 asc -- 7-24-2005
      ;
*/

SELECT DISTINCT
    CASE WHEN enrl_ac_cnt > 0 AND (tot_dec_ac - enrl_ac_cnt ) =0
             THEN decoder_sk
         ELSE
             ac_sk
        END ac_sk,

    'ACCOUNT' ||
    CASE WHEN enrl_ac_cnt > 0 AND (tot_dec_ac - enrl_ac_cnt ) =0
             THEN decoder_sk
         ELSE
             ac_sk
        END AS code,

    CASE WHEN enrl_ac_cnt > 0 AND (tot_dec_ac - enrl_ac_cnt ) =0
             THEN decoder_ac_id
         ELSE ac_id
        END || ' - ' || sortcol  AS decode,

    2 AS sortset,
    sortcol,
    'N'
FROM
    (
        SELECT   acct.ac_sk ac_sk,
                 acct.ac_id,
                 2 AS sortset,
                 NVL (alias.ac_alias, acct.ac_desc) AS sortcol,
                 'N' ,
                 acct.data_src_id data_src_id,
                 COUNT(ndx.cmpnt_ac_sk) over (PARTITION BY ndx.decoder_ac_sk) enrl_ac_cnt,
                ndx.decoder_ac_sk decoder_sk,
                 ndx.decoder_ac_id decoder_ac_id
        FROM   npf_account acct,
               npf_ac_cust_user acuser  left outer join NPF_DECODER_XREF ndx
                                                        ON acuser.ac_sk =ndx.cmpnt_ac_sk
                                                            AND ndx.cust_sk = acuser.cust_sk ,
               npf_cust_ac_alias alias
        WHERE       acuser.user_sk = v_user_sk
          AND acuser.cust_sk = p_cust_sk
          AND acuser.actv_flag = 'Y'
          AND acct.ac_sk = acuser.ac_sk
          AND alias.ac_sk = acct.ac_sk
          AND alias.cust_sk = acuser.cust_sk        --p_cust_sk
    )  ac_det left outer join
    ( SELECT decoder_ac_sk ,
             COUNT(decoder_ac_sk) over (PARTITION BY decoder_ac_sk) tot_dec_ac
      FROM NPF_DECODER_XREF
      WHERE cust_sk = p_cust_sk ) tot_decoder_ac
    ON  tot_decoder_ac.decoder_ac_sk =  ac_det.decoder_sk
WHERE (CASE WHEN enrl_ac_cnt > 0 AND (tot_dec_ac - enrl_ac_cnt ) =0  AND tot_dec_ac = 2  AND data_src_id = 1
                THEN 'Y'
            WHEN   enrl_ac_cnt > 0 and (tot_dec_ac - enrl_ac_cnt ) =0 AND tot_dec_ac = 1
                THEN 'Y'
            WHEN enrl_ac_cnt > 0 and (tot_dec_ac - enrl_ac_cnt ) =0  AND tot_dec_ac = 2  AND data_src_id = 2
                THEN 'N'
            ELSE
                'Y'
    END)  = 'Y'
ORDER BY   4, 6 DESC, 5 ASC ;
/* End P22870       */

RETURN v_cur_out;

EXCEPTION

        WHEN NOT_AUTHORIZED_EXCEPTION THEN
            npf_err_pkg.parms2string(v_parms_c, 'p_cust_sk', p_cust_sk);
            npf_err_pkg.parms2string(v_parms_c, 'p_login_id', p_login_id);
            npf_err_pkg.parms2string(v_parms_c, 'v_user_sk', v_user_sk);
            npf_err_pkg.rec_stop (SQLCODE,
                                'USER DEF',
                                NULL,
                                v_parms_c,
                                v_location_i,
                                pg_package_c,
                                v_procedure_c);

WHEN OTHERS THEN
            npf_err_pkg.parms2string(v_parms_c, 'p_cust_sk', p_cust_sk);
            npf_err_pkg.parms2string(v_parms_c, 'p_login_id', p_login_id);
            npf_err_pkg.parms2string(v_parms_c, 'v_user_sk', v_user_sk);
            npf_err_pkg.rec_stop (SQLCODE,
                                  'ORACLE',
                                  NULL,
                                  v_parms_c,
                                  v_location_i,
                                  pg_package_c,
                                  v_procedure_c);


END get_rpt_acct_consl_list;

    -- Name: get_rpt_acct_consl_list_nmr
  --
  -- Type: Function
  --
  -- Description: Returns the consolidations and accounts viewable by this user for this client
  --
  -- Techinical:
  --
  -- Notes: This procedure is used by the Custom Reporting Tool to provide the dropdown of
  --        accounts and consolidations on the modify query page.  DO NOT change this procedure
  --        without considering the effects on custom.
  --
  -- Syntax: get_rpt_acct_consl_list_nmr( p_cust_sk,
  --			   			p_login_id
  --				)
  --
  -- Where: p_cust_sk = the identifier of the customer whose the user is currently working on
  --        p_login_id = the identifier of the user who is requesting the list (or being emulated)
  --
  -- Returns:
  --		SYS_REFCURSOR = the list of consolidations and accounts
  --

 FUNCTION get_rpt_acct_consl_list_nmr(p_cust_sk 		IN npf_ac_cust_user.cust_sk%TYPE,
                                      p_login_id    IN npf_user.login_id%TYPE
				) RETURN SYS_REFCURSOR
 IS

	v_procedure_c CONSTANT VARCHAR2(30)  := 'get_rpt_acct_consl_list_nmr';

    v_user_sk npf_user.user_sk%TYPE;  -- variable to hold the user sk that should be used in query
    v_orig_user_sk npf_user.user_sk%TYPE; --variable to hold the actual user login, will be different than the sk to use in the query
                                            -- if the user is an internal

    v_cur_out SYS_REFCURSOR; -- the output cursor

    v_parms_c    VARCHAR2(4000);  -- This variable records the calling parameters for
                                  -- debugging and error recording operations.

    v_location_i INTEGER;  -- This variable tracks our location within this procedure.

    v_auth_rc INTEGER; -- This variable receives the authorization result from security

BEGIN

        v_location_i := 1;

        -- determine whether or not the user has access to the customer

        v_auth_rc := npf_asa_canaliasviewcustomer.canaliasviewcustomer(p_login_id,TO_CHAR(p_cust_sk));

        IF (v_auth_rc > 0) THEN
           RAISE NOT_AUTHORIZED_EXCEPTION;
END IF;

        v_location_i := 2;

 -- the login id was passed in, modify it to use the user_sk that should be associated with the
 -- login id given the customer being worked with by calling the get_user_query_sk function.
        v_user_sk := get_user_query_sk(p_login_id,p_cust_sk);
        v_orig_user_sk := v_user_sk;

        v_location_i := 5;

 -- given the user_sk returned, we need the generic id if it is internal so check the value
        v_user_sk := npf_security_pkg.get_generic_id(v_user_sk,p_cust_sk);

        v_location_i := 10;

 -- this cursor is designed to provide a list of consolidations and accounts with the
 -- consolidations appearing first in the list, followed by the accounts. Within each they
 -- are ordered by the description
 -- The first select below selects all of the consolidations which are ACTIVE and have
 -- an ACTIVE relationship to the user.  Since Custom is looking for the columns named code, decode
 -- and we are returning a mixture of consolidations and accounts the column aliased as code concatenates
 -- CONSL with the key.  The column returned aliased as decode looks to see if the consolidation has
 -- an MR consolidation id, if it does the MR consolidation id is returned as part of the description.
 -- The sortset column returns a 1 so that consolidations can be sorted before accounts, and the last
 -- column returns the value to sort within the consolidations.
OPEN v_cur_out FOR
-- this first select gets the reporting consolidations based on the real user logged in
SELECT 'CONSL' || consl.consl_sk AS code,
       consl.consl_sk,
       CASE
           WHEN NVL(consl.consl_xref_id,'E')='E' THEN consl.consl_desc
           ELSE consl.consl_xref_id || ' - ' || consl.consl_desc
           END AS decode,
       1 AS sortset,
       consl.consl_desc AS sortcol
        ,acc.user_dflt_consl_flag    -- SW12 7-24-2005
FROM npf_consl consl,
     npf_consl_user_access acc
WHERE consl.cust_sk = p_cust_sk
  AND acc.consl_sk = consl.consl_sk
  AND acc.user_sk = v_orig_user_sk
  AND acc.consl_user_stat_dcde = 'ACTIVE'
  AND consl.consl_stat_dcde = 'ACTIVE'
  AND acc.rpt_incl_flag = 'Y'

UNION
-- this second select gets the generic internal consolidations in case the internal user hasn't set their flags yet
-- this select should not return anything if generic id wasn't returned - the not exists will see to that
SELECT 'CONSL' || consl.consl_sk AS code,
       consl.consl_sk,
       CASE
           WHEN NVL(consl.consl_xref_id,'E')='E' THEN consl.consl_desc
           ELSE consl.consl_xref_id || ' - ' || consl.consl_desc
           END AS decode,
       1 AS sortset,
       consl.consl_desc AS sortcol
        ,acc.user_dflt_consl_flag   -- SW12 7-24-2005
FROM npf_consl consl,
     npf_consl_user_access acc
WHERE consl.cust_sk = p_cust_sk
  AND acc.consl_sk = consl.consl_sk
  AND acc.user_sk = v_user_sk
  AND acc.consl_user_stat_dcde = 'ACTIVE'
  AND consl.consl_stat_dcde = 'ACTIVE'
  AND acc.rpt_incl_flag = 'Y'
  AND NOT EXISTS ( SELECT 1
                   FROM npf_consl_user_access acc2
                   WHERE acc2.consl_sk = consl.consl_sk
                     AND acc2.user_sk = v_orig_user_sk
)
UNION
-- The second select in the UNION selects all of the accounts which have
-- an ACTIVE relationship to the user.  Since Custom is looking for the columns named code, decode
-- and we are returning a mixture of consolidations and accounts the column aliased as code concatenates
-- ACCOUNT with the key.  The column returned aliased as decode looks to see if the account has
-- an alias, if it does the alias is returned otherwise the default description is returned.
-- The sortset column returns a 2 so that consolidations can be sorted before accounts, and the last
-- column returns the value to sort within the accounts.

/* Start P22870  -  decoder details is incorporated instead of underlying accounts
      SELECT acct.ac_sk, 'ACCOUNT' || acct.ac_sk AS code,
             acct.ac_id || ' - ' || NVL(alias.ac_alias,acct.ac_desc) AS decode,
             2 AS sortset,
             NVL(alias.ac_alias,acct.ac_desc) AS sortcol
             ,'N'   -- SW12 7-24-2005
        FROM npf_account acct,
             npf_ac_cust_user acuser,
             npf_cust_ac_alias alias
       WHERE acuser.user_sk = v_user_sk
         AND acuser.cust_sk = p_cust_sk
         AND acuser.actv_flag = 'Y'
         AND acct.ac_sk = acuser.ac_sk
         AND alias.ac_sk = acct.ac_sk
         AND alias.cust_sk = p_cust_sk
       ORDER BY 4,6 desc,5 asc -- 7-24-2005
      ;
*/

SELECT DISTINCT
    'ACCOUNT' ||
    CASE WHEN enrl_ac_cnt > 0 AND (tot_dec_ac - enrl_ac_cnt ) =0
             THEN decoder_sk
         ELSE
             ac_sk
        END AS code,

    CASE WHEN enrl_ac_cnt > 0 AND (tot_dec_ac - enrl_ac_cnt ) =0
             THEN decoder_sk
         ELSE
             ac_sk
        END ac_sk,

    CASE WHEN enrl_ac_cnt > 0 AND (tot_dec_ac - enrl_ac_cnt ) =0
             THEN decoder_ac_id
         ELSE ac_id
        END || ' - ' || sortcol  AS decode,

    2 AS sortset,
    sortcol,
    'N'
FROM
    (
        SELECT   acct.ac_sk ac_sk,
                 acct.ac_id,
                 2 AS sortset,
                 NVL (alias.ac_alias, acct.ac_desc) AS sortcol,
                 'N' ,
                 acct.data_src_id data_src_id,
                 COUNT(ndx.cmpnt_ac_sk) over (PARTITION BY ndx.decoder_ac_sk) enrl_ac_cnt,
                ndx.decoder_ac_sk decoder_sk,
                 ndx.decoder_ac_id decoder_ac_id
        FROM   npf_account acct,
               npf_ac_cust_user acuser  left outer join NPF_DECODER_XREF ndx
                                                        ON acuser.ac_sk =ndx.cmpnt_ac_sk
                                                            AND ndx.cust_sk = acuser.cust_sk ,
               npf_cust_ac_alias alias
        WHERE       acuser.user_sk = v_user_sk
          AND acuser.cust_sk = p_cust_sk
          AND acuser.actv_flag = 'Y'
          AND acct.ac_sk = acuser.ac_sk
          AND alias.ac_sk = acct.ac_sk
          AND alias.cust_sk = acuser.cust_sk        --p_cust_sk
    )  ac_det left outer join
    ( SELECT decoder_ac_sk ,
             COUNT(decoder_ac_sk) over (PARTITION BY decoder_ac_sk) tot_dec_ac
      FROM NPF_DECODER_XREF
      WHERE cust_sk = p_cust_sk ) tot_decoder_ac
    ON  tot_decoder_ac.decoder_ac_sk =  ac_det.decoder_sk
WHERE (CASE WHEN enrl_ac_cnt > 0 AND (tot_dec_ac - enrl_ac_cnt ) =0  AND tot_dec_ac = 2  AND data_src_id = 1
                THEN 'Y'
            WHEN   enrl_ac_cnt > 0 and (tot_dec_ac - enrl_ac_cnt ) =0 AND tot_dec_ac = 1
                THEN 'Y'
            WHEN enrl_ac_cnt > 0 and (tot_dec_ac - enrl_ac_cnt ) =0  AND tot_dec_ac = 2  AND data_src_id = 2
                THEN 'N'
            ELSE
                'Y'
    END)  = 'Y'
ORDER BY   4, 6 DESC, 5 ASC ;
/* End P22870       */

RETURN v_cur_out;

EXCEPTION

        WHEN NOT_AUTHORIZED_EXCEPTION THEN
            npf_err_pkg.parms2string(v_parms_c, 'p_cust_sk', p_cust_sk);
            npf_err_pkg.parms2string(v_parms_c, 'p_login_id', p_login_id);
            npf_err_pkg.parms2string(v_parms_c, 'v_user_sk', v_user_sk);
            npf_err_pkg.rec_stop (SQLCODE,
                                'USER DEF',
                                NULL,
                                v_parms_c,
                                v_location_i,
                                pg_package_c,
                                v_procedure_c);

WHEN OTHERS THEN
            npf_err_pkg.parms2string(v_parms_c, 'p_cust_sk', p_cust_sk);
            npf_err_pkg.parms2string(v_parms_c, 'p_login_id', p_login_id);
            npf_err_pkg.parms2string(v_parms_c, 'v_user_sk', v_user_sk);
            npf_err_pkg.rec_stop (SQLCODE,
                                  'ORACLE',
                                  NULL,
                                  v_parms_c,
                                  v_location_i,
                                  pg_package_c,
                                  v_procedure_c);


END get_rpt_acct_consl_list_nmr;

 -- Name: get_user_query_sk
  --
  -- Type: Function
  --
  -- Description: Returns the user_sk that should be used for this user when working with
  --                the passed in customer
  --
  -- Technical:
  --
  -- Notes:
  --
  -- Syntax: get_user_query_sk( p_login_id,
  --			   			p_cust_sk
  --				)
  --
  -- Where: p_login_id = the login id of the user who's query id is desired
  --		p_cust_sk = the identifier of the customer the user is querying on
  --
  -- Returns:
  --		user_sk = the identifier to be used when determining which accounts to see
  --

FUNCTION get_user_query_sk(p_login_id 		IN npf_user.login_id%TYPE,
                        p_cust_sk		    IN npf_consl.cust_sk%TYPE
				)  RETURN npf_user.user_sk%TYPE
 IS

	v_procedure_c CONSTANT VARCHAR2(30)  := 'get_user_query_sk';

    v_user_sk npf_user.user_sk%TYPE; -- the output variable holding the user_sk

    v_parms_c    VARCHAR2(4000);  -- This variable records the calling parameters for
                                  -- debugging and error recording operations.

    v_location_i INTEGER;  -- This variable tracks our location within this procedure.

BEGIN

        v_location_i := 1;

        -- This implicit cursor needs to be dealt with when this function is written to
        -- correctly deal with Internal ids.
SELECT user_sk
INTO v_user_sk
FROM npf_user
WHERE login_id = p_login_id;

RETURN v_user_sk;

EXCEPTION
        WHEN NO_DATA_FOUND THEN
            npf_err_pkg.parms2string(v_parms_c, 'p_login_id', p_login_id);
            npf_err_pkg.parms2string(v_parms_c, 'p_cust_sk', p_cust_sk);

            -- temporarily removed sending SQLCode because of the error generated in err_pkg
            -- it doesn't allow 100
            npf_err_pkg.rec_go (-20015,
                                  'ORACLE',
                                  NULL,
                                  v_parms_c,
                                  v_location_i,
                                  pg_package_c,
                                  v_procedure_c);
RETURN NULL;

WHEN OTHERS THEN
            npf_err_pkg.parms2string(v_parms_c, 'p_login_id', p_login_id);
            npf_err_pkg.parms2string(v_parms_c, 'p_cust_sk', p_cust_sk);
            npf_err_pkg.rec_stop (SQLCODE,
                                  'ORACLE',
                                  NULL,
                                  v_parms_c,
                                  v_location_i,
                                  pg_package_c,
                                  v_procedure_c);



END get_user_query_sk;

  -- Name: what_version
  --
  -- Description: Returns version information for this package.
  --
  -- Syntax: what_version return varchar2;
  --
  -- Returns: A varchar2 containing the package version.

  FUNCTION what_version RETURN VARCHAR2 IS

    v_procedure_c CONSTANT VARCHAR2(30) := 'what_version';

    v_location_i INTEGER;  -- This variable tracks our location within this procedure.

BEGIN

    v_location_i := 1000;

RETURN pg_version_c;

EXCEPTION
      WHEN OTHERS THEN
          raise_application_error (SQLCODE,
                                   SQLERRM);
END what_version;




/***********************************************************************************
 *****************npf_division_function*********************************************/

  -- Name: npf_division_function
  --
  -- Type: Oracle Function
  --
  -- Description: This will be a common function which will be used for division
  --              and it will raise an error if divisor is zero.
  --
  --
  --
  -- Technical:  Two parameters are passed to the npf_division_function.
  --             The dividend is divided by the divisor and the quotient is returned.
  --             If the divisor is NULL or zero, the quotient is NULL.
  --
  --
  -- Notes:  This is a common function and can be used by all reports.
  --
  --
  --
  -- Syntax: npf_division_function(
  --                                  p_dividend_n,
  --                                  p_divisor_n
  --                                 );
  --
  --
  --
  -- Where:     p_dividend_n is the number to be divided
  --            p_divisor_n is the number used as divisor
  --
  --
  -- Returns:   Returns the quotient after performing the division.
  --
  --
  --
  --


FUNCTION npf_division_function(p_dividend_n IN NUMBER,
                               p_divisor_n IN NUMBER)
   RETURN NUMBER
   AS

   v_quotient_n NUMBER(18,3);

   /* Declaration of parameters for logging of errors                                 */
   v_parms_c VARCHAR2 (4000);

BEGIN

      /* Initialization of variable for error-handling                                   */
      v_parms_c := NULL;

      /* Check for NULL or divisor = 0 and handle the corresponding error                */
      /* Start - SONAR code change - Handle proper Null case for Npf_upgrade 12C
      IF((p_divisor_n = NULL) OR (p_divisor_n = 0)) THEN */
      IF((p_divisor_n IS NULL) OR (p_divisor_n = 0)) THEN
      /* End - code change for Npf_upgrade 12C */
         v_quotient_n := NULL;
ELSE
         v_quotient_n := (p_dividend_n/p_divisor_n);
END IF;

RETURN v_quotient_n;

EXCEPTION
      WHEN OTHERS THEN
          npf_err_pkg.parms2string (v_parms_c,'p_dividend_n', p_dividend_n );
          npf_err_pkg.parms2string (v_parms_c,'p_divisor_n',p_divisor_n);
RETURN v_quotient_n;
END; /* npf_division_function */


/***********************************************************************************/

/********************* ASSET TYPE MANAGER (npf_ast_typ_mgr) ************************/

/***********************************************************************************/


  -- Name: npf_asst_typ_mgr
  --
  -- Type: Oracle Procedure
  --
  -- Description: The SELECT procedure serves as a common module in VFO
  --              reporting applications. It takes in the Issue Type and
  --              Reporting Type as the arguments (input parameters) and
  --              gives supercategory and subcategory codes and descriptions
  --              as out parameters for a given reporting type and a given
  --              issue type.
  --
  --
  --
  --
  -- Technical: This is a Common Module which gives Supercategory and
  --            Subcategory codes and Descriptions.
  --
  --
  --
  --
  -- Notes:  This is a select procedure unit that IS NOT exposed to the user.
  --
  --
  --
  --
  -- Syntax:   PROCEDURE npf_asst_typ_mgr(
  --                                      p_iss_type_a,
  --                                      p_rptg_type_a,
  --                                      po_supcatg_code_a,
  --                                      po_subcatg_code_a,
  --                                      po_supcatg_desc_a,
  --                                      po_subcatg_desc_a
  --                                     );
  --
  --
  --
  --
  -- Where: p_iss_type_a is the Issue Type to be input to this procedure
  --        p_rptg_type_a is the reporting type to be input (which will be
  --        'WLT' for the urrent reporting.
  --        po_supcatg_code_a is supercategory code that is output from this
  --        procedure.
  --        po_subcatg_code_a is subcategory code that is output from this procedure.
  --        po_supcatg_desc_a  is the supercategory description
  --        po_subcatg_desc_a is subcategory description
  --
  --
  --
  -- Returns: None.
  --
  --
   PROCEDURE npf_asst_typ_mgr(p_iss_type_a IN NPF_ASSET_CATG.iss_type%TYPE,
                           p_rptg_type_a IN NPF_ASSET_CATG.rptg_type%TYPE,
                           po_supcatg_code_a OUT NPF_ASSET_CATG.supcatg_code%TYPE,
                           po_subcatg_code_a OUT NPF_ASSET_CATG.subcatg_code%TYPE,
                           po_supcatg_desc_a OUT NPF_ASSET_CATG.supcatg_desc%TYPE,
                           po_subcatg_desc_a OUT NPF_ASSET_CATG.subcatg_desc%TYPE)
AS

   /* Input parameters for calling rec_go procedure while exception handling          */
   /* Procedures parameters when the error occourred                                  */
   v_parms_c VARCHAR2 (4000);

   /* This variable tracks the location within this procedure.                        */
   v_location_i INTEGER;

   /* Exception location procedure/function name                                      */
   v_procedure_name_c VARCHAR2(400);

      /* ASSET_CURSOR                                                                      */
      /* Cursor to retrieve the Super category and Sub Category Codes and Descriptions     */
      /* from NPF_ASSET_CATG table                                                         */
CURSOR asset_cursor
      IS
         /* Retrieval of Supercategory and Subcategory Codes and Supercategory
            and Subcategory Descriptions from NPF_ASSET_CATG table                         */
SELECT nac.supcatg_code,
       nac.subcatg_code,
       nac.supcatg_desc,
       nac.subcatg_desc
FROM   NPF_ASSET_CATG nac
WHERE  nac.rptg_type = p_rptg_type_a
  AND    nac.iss_type = p_iss_type_a;

/* Begin Section                                                                   */
BEGIN
      /* Initializing input parameters for rec_go procedure                              */
      v_parms_c := NULL;
      v_procedure_name_c := 'npf_asst_typ_mgr';
      po_supcatg_code_a := pg_supcatg_asset_code_c;
      po_subcatg_code_a := pg_subcatg_asset_code_c;
      po_supcatg_desc_a := pg_supcatg_asset_desc_c;
      po_subcatg_desc_a := pg_subcatg_asset_desc_c;

      v_location_i := 1;

OPEN asset_cursor;
FETCH asset_cursor
    INTO  po_supcatg_code_a,
    po_subcatg_code_a,
    po_supcatg_desc_a,
    po_subcatg_desc_a;
CLOSE asset_cursor;

EXCEPTION
      WHEN OTHERS THEN
            npf_err_pkg.parms2string (v_parms_c,'p_iss_type_a', p_iss_type_a );
            npf_err_pkg.parms2string (v_parms_c,'p_rptg_type_a',p_rptg_type_a);
            npf_err_pkg.rec_stop(SQLCODE,pg_err_type_c,SQLERRM,v_parms_c,
                             v_location_i,pg_package_c,v_procedure_name_c);

END npf_asst_typ_mgr;



/***********************************************************************************/
/********************** NPF_ASST_TYP_MGR *******************************************/

--D18344--AG130--Starts

-- Name: npf_asst_typ_mgr
  --
  -- Type: Oracle Procedure
  --
  -- Description: The SELECT procedure serves as a common module in VFO
  --              reporting applications. It takes in the Issue Type,
  --              Reporting Type,Instrument id,schema filter and cust sk
  --              as the arguments (input parameters) and gives standard or
  --              customized supercategory and subcategory codes
  --              and descriptions as out parameters for a given input  parameters.
  --
  --
  -- Technical: This is a Common Module which gives standard or customized supercategory and
  --            Subcategory codes and Descriptions.
  --
  --
  --
  --
  -- Notes:  This is a select procedure unit that IS NOT exposed to the user.
  --
  --
  --
  --
  -- Syntax:  npf_asst_typ_mgr(p_iss_type_a,
  --                           p_rptg_type_a,
  --                           p_instr_id_a,
  --                           p_schema_fltr,
  --                           p_cust_sk,
  --                           po_supcatg_code_a,
  --                           po_subcatg_code_a,
  --                           po_supcatg_desc_a,
  --                           po_subcatg_desc_a,
  --                           po_cstm_supcatg_code_a,
  --                           po_cstm_subcatg_code_a)
  --
  --
  -- Where: p_iss_type_a is the Issue Type to be input to this procedure
  --        p_rptg_type_a is the reporting type to be input (which will be
  --        'WLT' for the current reporting.
  --        p_instr_id_a is the instrument id to be input to this procedure
  --        p_schema_fltr is the schema filter to be input to this procedure
  --        p_cust_sk is the customer sk to be input to this procedure
  --        po_supcatg_code_a is standard or customized supercategory code that is output from this
  --        procedure.
  --        po_subcatg_code_a is standard or customized subcategory code that is output from this procedure.
  --        po_supcatg_desc_a  is the standard or customized supercategory description
  --        po_subcatg_desc_a is standard or customized subcategory description
  --
  --
  --
  -- Returns: None.
  --
  --

PROCEDURE npf_asst_typ_mgr(p_iss_type_a      IN NPF_ASSET_CATG.iss_type%TYPE,
                           p_rptg_type_a     IN NPF_ASSET_CATG.rptg_type%TYPE,
                           p_instr_id_a      IN NPF_ASSET.INSTR_ID%TYPE,
                           p_schema_fltr     IN NPF_CUST_CSTM_SCHEMA.SCHEMA_ID%TYPE,
                           p_cust_sk         IN NPF_CUSTOMER.CUST_SK%TYPE,
                           po_supcatg_code_a OUT NPF_ASSET_CATG.supcatg_code%TYPE,
                           po_subcatg_code_a OUT NPF_ASSET_CATG.subcatg_code%TYPE,
                           po_supcatg_desc_a OUT NPF_ASSET_CATG.supcatg_desc%TYPE,
                           po_subcatg_desc_a OUT NPF_ASSET_CATG.subcatg_desc%TYPE,
                           po_cstm_supcatg_code_a OUT NPF_ASSET_CATG.supcatg_code%TYPE,
                           po_cstm_subcatg_code_a OUT NPF_ASSET_CATG.subcatg_code%TYPE)
AS

   /* Input parameters for calling rec_go procedure while exception handling          */
   /* Procedures parameters when the error occourred                                  */
   v_parms_c VARCHAR2 (4000);

   /* This variable tracks the location within this procedure.                        */
   v_location_i INTEGER;

   /* Exception location procedure/function name                                      */
   v_procedure_name_c VARCHAR2(400);
   v_rec_cnt NUMBER;

   po_cstm_ast_sup_catg_desc NPF_ASSET_CATG.supcatg_desc%TYPE;
   po_cstm_ast_sub_catg_desc NPF_ASSET_CATG.subcatg_desc%TYPE;
   po_cstm_cntry_of_risk_desc varchar2(245);
   po_cntry_code_a varchar2(10);
   po_cntry_desc_a varchar2(100);

      /* ASSET_CURSOR                                                                      */
      /* Cursor to retrieve the Super category and Sub Category Codes and Descriptions     */
      /* from NPF_CSTM_SCHEMA and NPF_ASSET  table                                           */

CURSOR cstm_asset_cursor
      IS


SELECT ncs.CSTM_SUPCATG_CODE,
       ncs.CSTM_SUPCATG_DESC,
       ncs.NPF_SUPCATG_CODE,
       ncs.CSTM_SUBCATG_CODE,
       ncs.CSTM_SUBCATG_DESC,
       ncs.NPF_SUBCATG_CODE
FROM NPF_CSTM_SCHEMA ncs,NPF_ASSET na
WHERE ncs.SCHEMA_ID = p_schema_fltr
  AND ncs.INSTR_ID  = p_instr_id_a
  --AND na.ISS_TYPE   = p_iss_type_a
  AND na.INSTR_ID   = ncs.INSTR_ID
  AND ncs.RPTG_TYPE = p_rptg_type_a
  AND END_DT IS NULL;

/* Begin Section                                                                   */
BEGIN

      /* Initializing input parameters for rec_go procedure                              */
      v_parms_c := NULL;
      v_procedure_name_c := 'npf_asst_typ_mgr';
      po_supcatg_code_a := pg_supcatg_asset_code_c;
      po_subcatg_code_a := pg_subcatg_asset_code_c;
      po_supcatg_desc_a := pg_supcatg_asset_desc_c;
      po_subcatg_desc_a := pg_subcatg_asset_desc_c;
      po_cntry_code_a   := pg_cntry_risk_code_c;
      po_cntry_desc_a   := pg_cntry_risk_desc_c;


      v_location_i := 1;

SELECT COUNT('1') INTO v_rec_cnt
FROM NPF_CSTM_SCHEMA
WHERE SCHEMA_ID = p_schema_fltr
  AND INSTR_ID    = p_instr_id_a
  AND RPTG_TYPE   = p_rptg_type_a
  AND END_DT IS NULL;

/* For the given p_schema_fltr,p_instr_id_a and p_rptg_type_a value that exists in NPF_CSTM_SCHEMA table
   and based on the conditions given below  po_supcatg_desc_a,po_subcatg_desc_a,po_cstm_supcatg_code_a
   and po_cstm_subcatg_code_a out parameters will be assigned the values. */

IF v_rec_cnt <> 0 THEN

       FOR v_ast_cur_rec IN cstm_asset_cursor
       LOOP
            npf_asst_typ_mgr(p_iss_type_a,
                          p_rptg_type_a,
                          po_supcatg_code_a,
                          po_subcatg_code_a,
                          po_supcatg_desc_a,
                          po_subcatg_desc_a);
            IF v_ast_cur_rec.CSTM_SUPCATG_CODE IS NULL and v_ast_cur_rec.CSTM_SUBCATG_CODE IS NOT NULL THEN

              po_supcatg_desc_a :=v_ast_cur_rec.CSTM_SUPCATG_DESC;
              po_subcatg_desc_a :=v_ast_cur_rec.CSTM_SUBCATG_DESC;
              po_cstm_supcatg_code_a := concat(v_ast_cur_rec.npf_supcatg_code,'-S');
              po_cstm_subcatg_code_a := concat(v_ast_cur_rec.CSTM_SUBCATG_CODE,'-C');

            ELSIF  v_ast_cur_rec.cstm_supcatg_code is not NULL and v_ast_cur_rec.cstm_subcatg_code is NULL THEN

              po_supcatg_desc_a :=v_ast_cur_rec.CSTM_SUPCATG_DESC;
              po_subcatg_desc_a :=v_ast_cur_rec.CSTM_SUBCATG_DESC;
              po_cstm_supcatg_code_a := concat(v_ast_cur_rec.cstm_supcatg_code,'-C');
              po_cstm_subcatg_code_a := concat(v_ast_cur_rec.npf_SUBCATG_CODE,'-S');

            ELSIF v_ast_cur_rec.cstm_supcatg_code is NULL and v_ast_cur_rec.cstm_subcatg_code is NULL THEN


              po_supcatg_desc_a :=v_ast_cur_rec.CSTM_SUPCATG_DESC;
              po_subcatg_desc_a :=v_ast_cur_rec.CSTM_SUBCATG_DESC;
              po_cstm_supcatg_code_a := concat(v_ast_cur_rec.npf_supcatg_code,'-S');
              po_cstm_subcatg_code_a := concat(v_ast_cur_rec.npf_SUBCATG_CODE,'-S');


            ELSIF  v_ast_cur_rec.cstm_supcatg_code is not NULL and v_ast_cur_rec.cstm_subcatg_code is not NULL THEN


              po_supcatg_desc_a :=v_ast_cur_rec.CSTM_SUPCATG_DESC;
              po_subcatg_desc_a :=v_ast_cur_rec.CSTM_SUBCATG_DESC;
              po_cstm_supcatg_code_a := concat(v_ast_cur_rec.cstm_supcatg_code,'-C');
              po_cstm_subcatg_code_a := concat(v_ast_cur_rec.CSTM_SUBCATG_CODE,'-C');

END IF;

END LOOP;

ELSE

         npf_asst_typ_mgr(p_iss_type_a,
                          p_rptg_type_a,
                          po_supcatg_code_a,
                          po_subcatg_code_a,
                          po_supcatg_desc_a,
                          po_subcatg_desc_a);

--Added below for Custom Asset Schema Rule Configurator by AJ250

BEGIN

select cntry_risk_dcde INTO po_cntry_code_a
from npfdbo.npf_asset
where instr_id = p_instr_id_a;
EXCEPTION
         WHEN NO_DATA_FOUND THEN
         po_cntry_code_a := NULL;

END;

BEGIN

select dcde_desc INTO po_cntry_desc_a
from npfdbo.npf_decode
where dcde_type = 'CNTRY'
  and dcde_code = po_cntry_code_a;
EXCEPTION
         WHEN NO_DATA_FOUND THEN
         po_cntry_desc_a := NULL;

END;

         NPF_CUST_SCHEMA_RULE_EVALUATION_PKG.RULE_EVALUATION(p_schema_fltr,po_supcatg_desc_a,po_subcatg_desc_a,po_cntry_desc_a,
      	 po_cstm_ast_sup_catg_desc,po_cstm_ast_sub_catg_desc,po_cstm_cntry_of_risk_desc);

         po_supcatg_desc_a := po_cstm_ast_sup_catg_desc;
         po_subcatg_desc_a := po_cstm_ast_sub_catg_desc;

         po_cstm_supcatg_code_a := concat(po_supcatg_code_a,'-S');
         po_cstm_subcatg_code_a := concat(po_supcatg_code_a,'-');
         po_cstm_subcatg_code_a := concat(po_cstm_subcatg_code_a,po_subcatg_code_a);
         po_cstm_subcatg_code_a := concat(po_cstm_subcatg_code_a,'-S');

END IF;

EXCEPTION
      WHEN OTHERS THEN
            npf_err_pkg.parms2string (v_parms_c,'p_iss_type_a', p_iss_type_a );
            npf_err_pkg.parms2string (v_parms_c,'p_rptg_type_a',p_rptg_type_a);
            npf_err_pkg.rec_stop(SQLCODE,pg_err_type_c,SQLERRM,v_parms_c,
                             v_location_i,pg_package_c,v_procedure_name_c);

END npf_asst_typ_mgr;

  -- Name: get_cstm_cntry_risk_desc
  --
  -- Type: Oracle Procedure
  --
  -- Description: To retrieve the customized country of risk code and desc It takes in Instrument id,
  --              schema filter and cust sk as the arguments (input parameters) and gives customized
  --              country of risk codes and Descriptions as out parameters for a given input parameters.
  --
  --
  -- Technical: This is a Common Module which gives customized country of risk codes and Descriptions.
  --
  -- Notes:  This is a select procedure unit that IS NOT exposed to the user.
  --
  --
  -- Syntax:  get_cstm_cntry_risk_desc(p_instr_id_a,
  --                                   p_schema_fltr,
  --                                   p_cust_sk,
  --                                   po_cstm_cntry_risk_dcde_a,
  --                                   po_cstm_cntry_risk_desc_a
  --                                   )
  --
  --
  -- Where: p_instr_id_a is the instrument id to be input to this procedure
  --        p_schema_fltr is the schema filter to be input to this procedure
  --        p_cust_sk is the customer sk to be input to this procedure
  --        po_cstm_cntry_risk_dcde_a is customized country of risk code that is output from this
  --        procedure.
  --        po_cstm_cntry_risk_desc_a is customized country of risk desc that is output from this procedure.
  --
  --
  --
  -- Returns: None.
  --
  --


PROCEDURE get_cstm_cntry_risk_desc  (p_instr_id_a      IN NPF_ASSET.INSTR_ID%TYPE,
                                     p_schema_fltr     IN NPF_CUST_CSTM_SCHEMA.SCHEMA_ID%TYPE,
                                     p_cust_sk         IN NPF_CUSTOMER.CUST_SK%TYPE,
                                     po_cstm_cntry_risk_dcde_a OUT NPF_CSTM_SCHEMA.CSTM_CNTRY_RISK_DCDE%TYPE,
                                     po_cstm_cntry_risk_desc_a OUT NPF_CSTM_SCHEMA.CSTM_CNTRY_RISK_DESC%TYPE
                                     )
AS

CURSOR GET_CSTM_CNTRY_RISK
IS
SELECT CSTM_CNTRY_RISK_DCDE,CSTM_CNTRY_RISK_DESC
FROM NPF_CSTM_SCHEMA
WHERE SCHEMA_ID = p_schema_fltr
  AND   INSTR_ID  = p_instr_id_a
  AND   END_DT IS NULL;

BEGIN

FOR V_CSTM_CNTRY_REC IN GET_CSTM_CNTRY_RISK
LOOP
po_cstm_cntry_risk_dcde_a := V_CSTM_CNTRY_REC.CSTM_CNTRY_RISK_DCDE;
po_cstm_cntry_risk_desc_a := V_CSTM_CNTRY_REC.CSTM_CNTRY_RISK_DESC;
END LOOP;

END get_cstm_cntry_risk_desc;


--D18344--AG130--Ends

/***********************************************************************************/
/********************** Date Calculation Manager ***********************************/


  -- Name: npf_date_cal_mgr
  --
  -- Type: Oracle Procedure
  --
  -- Description:This is a common module which is used to calculate current
  --             business day, previous business day, previous month end,
  --             previous quarter end, previous year end, last business
  --             day of month, first business day of month.
  --
  --
  --
  --
  -- Technical:  This common module will take date as string and returns the
  --             business and calendar dates in DATE datatype only
  --
  --
  --
  -- Notes:  This is a select procedure unit that IS NOT exposed to the user.
  --
  --
  --
  --
  --
  -- Syntax: npf_date_cal_mgr(
  --                          p_valn_date_c,
  --                          p_date_cal_flag_c,
  --                          po_Busn_date,
  --                          po_Caln_date
  --                         );
  --
  --
  --
  --
  --
  -- Where:  p_valn_date_c is the input date for which valuation is needed as
  --         output
  --         p_date_cal_flag_c is used to determine which day is to be calculated
  --         For ex.: current business day, previous business day, etc.
  --         po_Busn_date is out parameter that corresponds to the business date
  --         po_Caln_date is the out parameter that corresponds to the calendar date
  --
  --
  --
  --
  --
  --
  -- Returns:  None.
  --
  --
  --
  --
PROCEDURE npf_date_cal_mgr(p_valn_date_c IN VARCHAR2,
                           p_date_cal_flag_c IN VARCHAR2,
                           po_Busn_date OUT DATE,
                           po_Caln_date OUT DATE )
AS

   /* Local variables used for calculations                                           */
   v_day_c VARCHAR2(10);
   v_valn_date DATE;
   v_end_date DATE;
   po_Busn_date_c VARCHAR2(10);

   /* Variables used for error-handling                                               */
   /* Procedures parameters when the error occourred                                  */
   v_parms_c VARCHAR2 (4000);

   /* Exception location procedure/function name                                      */
   v_procedure_name_c VARCHAR2(400);

   /* This variable tracks the location within this procedure.                        */
   v_location_i INTEGER;

   INVALID_FLAG_EXCEPTION EXCEPTION;
   PRAGMA EXCEPTION_INIT (INVALID_FLAG_EXCEPTION, -20009);

/***********************************************************************************/
/********************** Current Business date Calculator ***************************/



  -- Name: npf_curr_busn_day
  --
  -- Type: Oracle Procedure
  --
  -- Description: This is a sub-procedure which is used by Date Calculation
  --              Manager to determine current business day
  --
  --
  --
  --
  -- Technical:  This local procedure will take date as input and return current
  --             business day as DATE datatype only
  --
  --
  --
  --
  -- Notes:  This is a select procedure unit that IS NOT exposed to the user.
  --
  --
  --
  --
  --
  -- Syntax: npf_curr_busn_day(
  --                           p_valn_date IN DATE,
  --                           po_Busn_date OUT DATE
  --                          );
  --
  --
  --
  --
  --
  -- Where:  p_valn_date is the input date for which current business day is needed
  --         po_Busn_date is out parameter that corresponds to the current
  --         business date
  --
  --
  --
  --
  --
  -- Returns:  None.
  --
  --
  --
  --
      PROCEDURE npf_curr_busn_day(p_valn_date IN DATE,
                                  po_Busn_date OUT DATE )
AS

         v_day_c VARCHAR2(10);
         v_end_date DATE;
         po_Busn_date_c VARCHAR2(10);

     /* Executable section for npf_curr_busn_day procedure                              */
BEGIN

        /* Initialization of variables for error-handling                                  */
        v_parms_c := NULL;
        v_location_i := 1;
        v_procedure_name_c := 'npf_curr_busn_day';

       /* Initialization of parameters for error-handling                                 */
       v_parms_c := NULL;

       po_Busn_date := p_valn_date;
       v_day_c := TO_CHAR(po_Busn_date,pg_oracle_func_constant_c);

       v_location_i := 10;

      /* Check if date entered is a sunday and subtract 2 to get date of
         corresponding Friday                                                            */
      IF (LOWER(v_day_c) = LOWER(pg_weekend_sun_c)) THEN
          po_Busn_date_c := TO_CHAR(po_Busn_date,pg_std_date_format_c);
          po_Busn_date := TO_DATE(po_Busn_date_c,pg_std_date_format_c) - 2;
END IF;

      /* Check if date entered is a saturday and subtract 1 to get date of
          corresponding Friday                                                            */
      IF (LOWER(v_day_c) = LOWER(pg_weekend_sat_c)) THEN
          po_Busn_date_c := TO_CHAR(po_Busn_date,pg_std_date_format_c);
          po_Busn_date := TO_DATE(po_Busn_date_c,pg_std_date_format_c) - 1 ;
END IF;

       v_location_i := 20;

EXCEPTION
    WHEN OTHERS THEN
        npf_err_pkg.parms2string (v_parms_c,'p_valn_date', p_valn_date );
        npf_err_pkg.rec_stop(SQLCODE,pg_err_type_c,SQLERRM,v_parms_c,
                             v_location_i,pg_package_c,v_procedure_name_c);


END npf_curr_busn_day;

    /* Executable section for npf_date_cal_mgr procedure                               */
BEGIN

       /* Initialization of variables for error-handling                                  */
       v_parms_c := NULL;
       v_location_i := 30;
       v_procedure_name_c := 'npf_date_cal_mgr';

       /* Validation of dates passed                                                      */
       npf_date_val_mgr(p_valn_date_c,v_valn_date);

      /* Calculation of current business day                                             */
      IF (LOWER(p_date_cal_flag_c) = LOWER(pg_curr_buss_day_c)) THEN
          po_Caln_date := v_valn_date;
          npf_curr_busn_day( v_valn_date,po_Busn_date );

      /* Calculation of previous business day                                            */
      ELSIF (LOWER(p_date_cal_flag_c) = LOWER(pg_prev_buss_day_c)) THEN
          npf_curr_busn_day( v_valn_date,po_Busn_date );
          po_Busn_date_c := TO_CHAR(po_Busn_date,pg_std_date_format_c);
          po_Caln_date := TO_DATE(po_Busn_date_c,pg_std_date_format_c) - 1;
          NPF_CURR_BUSN_DAY( PO_CALN_DATE,PO_BUSN_DATE );


      /* Calculation of previous business day R3.7_UI - Two business day prior changes*/
      ELSIF (LOWER(p_date_cal_flag_c) = LOWER(pg_2bus_day_prior_c)) THEN
          npf_curr_busn_day( v_valn_date,po_Busn_date );
          PO_BUSN_DATE_C := TO_CHAR(PO_BUSN_DATE,PG_STD_DATE_FORMAT_C);
          po_Caln_date := TO_DATE(po_Busn_date_c,pg_std_date_format_c);
          npf_curr_busn_day( po_Caln_date,po_Busn_date );
          V_DAY_C := TO_CHAR(PO_BUSN_DATE,PG_ORACLE_FUNC_CONSTANT_C);

          /* If start date is a monday, subtract 4 to get date of
          corresponding Thursday                                                            */
          IF (LOWER(v_day_c) = LOWER(pg_weekend_mon_c)) THEN
              po_Busn_date_c := TO_CHAR(po_Busn_date,pg_std_date_format_c);
              PO_CALN_DATE  := TO_DATE(PO_BUSN_DATE_C,PG_STD_DATE_FORMAT_C) - 4;
          /* If date entered is a tuesday, subtract 4 to get date of
          corresponding Friday                                                            */
          ELSIF (LOWER(v_day_c) = LOWER(pg_weekend_tue_c)) THEN
              po_Busn_date_c := TO_CHAR(po_Busn_date,pg_std_date_format_c);
              PO_CALN_DATE := TO_DATE(PO_BUSN_DATE_C,PG_STD_DATE_FORMAT_C) - 4;
ELSE
              PO_CALN_DATE := TO_DATE(PO_BUSN_DATE_C,PG_STD_DATE_FORMAT_C) - 2;
END IF;
          /* Special handling for previous day for the Account Market Value Change report */
      ELSIF (LOWER(p_date_cal_flag_c) = LOWER(pg_amvc_prev_buss_day_c)) THEN
          --This is a special case per SIR 994. If the date passed is on the weekend
          --then we always want the same date returned for current as for the previous.
          --We want the same results.
          IF LOWER(TO_CHAR(v_valn_date,'fmDay')) IN ('saturday','sunday') THEN
              po_Caln_date := v_valn_date - 1;
              npf_curr_busn_day( po_Caln_date,po_Busn_date );
ELSE --Otherwise do the same thing the existing previous business day does
              npf_curr_busn_day( v_valn_date,po_Busn_date );
              po_Busn_date_c := TO_CHAR(po_Busn_date,pg_std_date_format_c);
              po_Caln_date := TO_DATE(po_Busn_date_c,pg_std_date_format_c) - 1;
              npf_curr_busn_day( po_Caln_date,po_Busn_date );
END IF;

      /* Calculation of previous month end                                               */
      ELSIF (LOWER(p_date_cal_flag_c) = LOWER(pg_prev_mth_end_c)) THEN
          po_Caln_date := TRUNC(v_valn_date,pg_oracle_mth_constant_c) - 1;
          npf_curr_busn_day( po_Caln_date,po_Busn_date );

      /* Calculation of previous Quarter end                                             */
      ELSIF (LOWER(p_date_cal_flag_c) = LOWER(pg_prev_qt_end_c)) THEN
          po_Caln_date := TRUNC(v_valn_date,pg_oracle_qt_constant_c) - 1;
          npf_curr_busn_day( po_Caln_date,po_Busn_date );

      /* Calculation of previous year end                                                */
      ELSIF (LOWER(p_date_cal_flag_c) = LOWER(pg_prev_year_end_c)) THEN
          po_Caln_date := TRUNC(v_valn_date,pg_oracle_yr_constant_c) - 1;
          npf_curr_busn_day( po_Caln_date,po_Busn_date );

      /* Calculation of last business day of month                                       */
      ELSIF (LOWER(p_date_cal_flag_c) = LOWER(pg_last_busn_day_of_mth_c)) THEN
          po_Caln_date := LAST_DAY(v_valn_date);
          npf_curr_busn_day( po_Caln_date,po_Busn_date );

      v_location_i := 40;

      /* Calculation of first business day of month                                      */
      ELSIF (LOWER(p_date_cal_flag_c) = LOWER(pg_first_busn_day_of_mth_c)) THEN
          po_Caln_date := TRUNC(v_valn_date,pg_oracle_mth_constant_c);
          po_Busn_date := po_Caln_date;
          v_day_c := TO_CHAR(po_Busn_date,pg_oracle_func_constant_c);

    /* Check if calculated date is a sunday and add 1 to get date of
       corresponding Monday                                                            */
          IF (LOWER(v_day_c) = LOWER(pg_weekend_sun_c)) THEN
              po_Busn_date_c := TO_CHAR(po_Busn_date,pg_std_date_format_c);
              po_Busn_date  := TO_DATE(po_Busn_date_c,pg_std_date_format_c) + 1;
END IF;

    /* Check if date entered is a saturday and add 2 to get date of
        corresponding Monday                                                            */
          IF (LOWER(v_day_c) = LOWER(pg_weekend_sat_c)) THEN
              po_Busn_date_c := TO_CHAR(po_Busn_date,pg_std_date_format_c);
              po_Busn_date := TO_DATE(po_Busn_date_c,pg_std_date_format_c) + 2;
END IF;

     v_location_i := 50;

    /* Check if flag entered is invalid, i.e. it has a value other than c,b,m,q,y,l,f  */
ELSE
          RAISE INVALID_FLAG_EXCEPTION;
END IF;

EXCEPTION
      WHEN INVALID_FLAG_EXCEPTION THEN
         npf_err_pkg.parms2string(v_parms_c,'p_valn_date_c',p_valn_date_c );
         npf_err_pkg.parms2string(v_parms_c,'p_date_cal_flag_c',p_date_cal_flag_c );
         npf_err_pkg.rec_stop(-20009,pg_user_err_type_c,
                           npf_err_pkg.get_user_err_msg(-20009,pg_user_err_type_c),
                           v_parms_c,v_location_i,pg_package_c,v_procedure_name_c);

WHEN OTHERS THEN
         npf_err_pkg.parms2string(v_parms_c,'p_valn_date_c',p_valn_date_c );
         npf_err_pkg.parms2string(v_parms_c,'p_date_cal_flag_c',p_date_cal_flag_c );
         npf_err_pkg.rec_stop(SQLCODE,pg_user_err_type_c,SQLERRM,v_parms_c,
                             v_location_i,pg_package_c,v_procedure_name_c);

END npf_date_cal_mgr;


/***********************************************************************************/
/*************** Date Validation Manager (for a single input date) *****************/

  -- Name: npf_date_val_mgr
  --
  -- Type: Oracle Procedure
  --
  -- Description: This common module Validates the entered Date and
  --              Checks for the Date Format. It checks whether the
  --              Effective date is greater than the system date.
  --
  --
  --
  --
  -- Technical: This modules validates the Input date passed as string and
  --             checks for the proper Format.
  --
  --
  --
  --
  -- Notes:  This is a select procedure unit that IS NOT exposed to the user.
  --
  --
  --
  --
  -- Syntax: PROCEDURE npf_date_val_mgr(
  --                                    p_as_of_date_c,
  --                                    po_as_of_date
  --                                   );
  --
  --
  --
  -- Where:  p_as_of_date_c is the Effective Date entered by the user
  --         po_as_of_date is the valid Effective date coming from Date Validation
  --         Manager
  --
  --
  --
  --
  -- Returns: None
  --
  --
  --
  --


PROCEDURE npf_date_val_mgr (
                            p_as_of_date_c IN VARCHAR2,
                            po_as_of_date OUT DATE
                           )

AS

v_sys_date_c VARCHAR2(100);
v_p_as_of_date_c VARCHAR2(100);
v_s_date DATE;
v_as_of_date DATE;

/* Variables used for error-handling                                               */
/* Exception location procedure/function name                                      */
v_procedure_name_c VARCHAR2(400);
/* This variable tracks the location within this procedure.                        */
v_location_i INTEGER;
/* Procedures parameters when the error occourred                                  */
v_parms_c VARCHAR2(4000);

/* Declaring some user defined Test Exceptions                                     */
EFFECTIVE_DATE_NULL_EXCEPTION EXCEPTION;
AS_OF_DATE_FORMAT_EXCEPTION EXCEPTION;
AS_OF_DATE_EXCEPTION EXCEPTION;

PRAGMA EXCEPTION_INIT (EFFECTIVE_DATE_NULL_EXCEPTION, -20010);
PRAGMA EXCEPTION_INIT (AS_OF_DATE_FORMAT_EXCEPTION, -20011);
PRAGMA EXCEPTION_INIT (AS_OF_DATE_EXCEPTION, -20003);


BEGIN

/* Write your procedure Name here                                                  */
       v_procedure_name_c := 'npf_date_val_mgr';
       v_parms_c := NULL;

       v_location_i:= 1;

/* To Check whether the Effective date is null                                     */
       IF p_as_of_date_c IS NULL THEN
     RAISE EFFECTIVE_DATE_NULL_EXCEPTION;
END IF;

/* System date is selected                                                         */
       v_sys_date_c := TO_CHAR(TRUNC(sysdate), pg_date_time_format_c);

/* Truncating the time stamp part of the entered date                              */
       v_s_date := TRUNC(sysdate,pg_trunc_by_c);

       v_location_i:= 10;

/* To Check whether the Effective date entered is in some other date format        */
       IF (Instr(p_as_of_date_c,pg_dash_c,1,1) <> 5
          OR Instr(p_as_of_date_c,pg_dash_c,1,2) <> 8 ) THEN
           RAISE AS_OF_DATE_FORMAT_EXCEPTION;
END IF;

/* Truncating the time stamp part of the Effective Date                            */
       v_as_of_date := TRUNC(TO_DATE(p_as_of_date_c,
                       pg_date_time_format_c),pg_trunc_by_c);

       v_location_i := 20;

/* To check whether the Effective date is greater than the system date             */
       IF ((v_s_date - v_as_of_date) < 0) THEN
         RAISE AS_OF_DATE_EXCEPTION;

ELSE
         po_as_of_date:= TO_DATE(v_as_of_date);

END IF;


EXCEPTION
/* Exception Handling to check whether effective date is null                      */
       WHEN EFFECTIVE_DATE_NULL_EXCEPTION THEN
            npf_err_pkg.parms2string (v_parms_c,'p_as_of_date_c', p_as_of_date_c );
            npf_err_pkg.rec_stop( -20010,pg_user_err_type_c,
            npf_err_pkg.get_user_err_msg(-20010,pg_user_err_type_c),
            v_parms_c,v_location_i,pg_package_c,v_procedure_name_c);

/* Exception Handling to check whether effective date entered
    is in yyyy-mm-dd format                                                        */
WHEN AS_OF_DATE_FORMAT_EXCEPTION THEN
            npf_err_pkg.parms2string (v_parms_c,'p_as_of_date_c', p_as_of_date_c );
            npf_err_pkg.rec_stop( -20011,pg_user_err_type_c,
            npf_err_pkg.get_user_err_msg(-20011,pg_user_err_type_c),
            v_parms_c,v_location_i,pg_package_c,v_procedure_name_c);

/* Exception Handling to check if effective date entered is greater than sysdate   */
WHEN AS_OF_DATE_EXCEPTION THEN
            npf_err_pkg.parms2string (v_parms_c,'p_as_of_date_c', p_as_of_date_c );
            npf_err_pkg.rec_stop(-20003,pg_user_err_type_c,
            npf_err_pkg.get_user_err_msg(-20003,pg_user_err_type_c),
            v_parms_c,v_location_i,pg_package_c,v_procedure_name_c);

WHEN OTHERS THEN
            npf_err_pkg.parms2string (v_parms_c,'p_as_of_date_c', p_as_of_date_c );
            npf_err_pkg.rec_stop(SQLCODE,pg_err_type_c,SQLERRM,v_parms_c,
            v_location_i,pg_package_c,v_procedure_name_c);

END npf_date_val_mgr;


/***********************************************************************************/
/**************** Date Validation Manager (for two input dates) ********************/

  -- Name: npf_date_val_mgr
  --
  -- Type: Oracle Procedure
  --
  -- Description: This common module Validates the entered Dates and
  --              Checks for the Date Format It checks whether the begin
  --              date or end date entered are greater than the system date
  --              It also checks whether the begin date is greater than the
  --              End date. Also it checks if both the entered dates are
  --              same then for positional reports it checks for
  --              whether the date is greater than system date.
  --
  --
  --
  --
  -- Technical: This modules validates the Input dates passed as string and
  --             checks for the proper Format.
  --
  --
  --
  --
  -- Notes:  This is a select procedure unit that IS NOT exposed to the user.
  --
  --
  --
  --
  -- Syntax: PROCEDURE npf_date_val_mgr(
  --                                    p_begin_date_c,
  --                                    p_end_date_c,
  --                                    po_begin_date,
  --                                    po_end_date
  --                                   );
  --
  --
  --
  -- Where:  p_begin_date_c is Begin date entered by the user
  --         p_end_date_c is End Date entered by the user
  --         po_begin_date is the valid begin date coming from Date Validation
  --         Manager
  --         po_end_date is the valid end date coming from Date Validation Manager
  --
  --
  --
  --
  -- Returns: None
  --
  --
  --
  --

PROCEDURE npf_date_val_mgr (
                            p_begin_date_c IN VARCHAR2,
                            p_end_date_c IN VARCHAR2,
                            po_begin_date OUT DATE,
                            po_end_date OUT DATE
                           )

AS

v_sys_date_c VARCHAR2(100);
v_p_begin_date_c VARCHAR2(100);
v_p_end_date_c VARCHAR2(100);
v_s_date DATE;
v_begin_date DATE;
v_end_date DATE;

/* Variables used for error-handling                                               */
/* Exception location procedure/function name                                      */
v_procedure_name_c VARCHAR2(400);
/* This variable tracks the location within this procedure.                        */
v_location_i INTEGER;
/* Procedures parameters when the error occourred                                  */
v_parms_c VARCHAR2(4000);

/* Declaring some user defined Test Exceptions                                     */

BEG_DATE_NULL_EXCEPTION EXCEPTION;
END_DATE_NULL_EXCEPTION EXCEPTION;
BEG_DATE_FORMAT_EXCEPTION EXCEPTION;
END_DATE_FORMAT_EXCEPTION EXCEPTION;
AS_OF_DATE_EXCEPTION EXCEPTION;
BEGIN_END_EXCEPTION EXCEPTION;
BEGIN_SYS_EXCEPTION EXCEPTION;
END_SYS_EXCEPTION EXCEPTION;

PRAGMA EXCEPTION_INIT (BEG_DATE_NULL_EXCEPTION, -20007);
PRAGMA EXCEPTION_INIT (END_DATE_NULL_EXCEPTION, -20008);
PRAGMA EXCEPTION_INIT (BEG_DATE_FORMAT_EXCEPTION, -20001);
PRAGMA EXCEPTION_INIT (END_DATE_FORMAT_EXCEPTION, -20002);
PRAGMA EXCEPTION_INIT (AS_OF_DATE_EXCEPTION, -20003);
PRAGMA EXCEPTION_INIT (BEGIN_END_EXCEPTION, -20004);
PRAGMA EXCEPTION_INIT (BEGIN_SYS_EXCEPTION, -20005);
PRAGMA EXCEPTION_INIT (END_SYS_EXCEPTION, -20006);


BEGIN
/* Write your procedure Name here                                                  */
    v_procedure_name_c := 'npf_date_val_mgr';
    v_parms_c := NULL;

    v_location_i:= 1;

/* To Check whether the Begin date is null                                         */
    IF (p_begin_date_c IS NULL) THEN
        RAISE BEG_DATE_NULL_EXCEPTION;
END IF;

    v_location_i:= 10;

/* To Check whether the End date is null                                           */
    IF (p_end_date_c IS NULL) THEN
     RAISE END_DATE_NULL_EXCEPTION;
END IF;

/* System date is selected                                                         */
    v_sys_date_c := TO_CHAR(TRUNC(sysdate), pg_date_time_format_c);

/* Truncating the time stamp part of the entered date                              */
    v_s_date := TRUNC(sysdate,pg_trunc_by_c);

    v_location_i:= 20;

/* To Check whether the Begin date entered is in some other date format            */
    IF (Instr(p_begin_date_c,pg_dash_c,1,1) <> 5
          OR
          Instr(p_begin_date_c,pg_dash_c,1,2) <> 8 ) THEN
    RAISE BEG_DATE_FORMAT_EXCEPTION;
END IF;

    v_location_i:= 30;

/* To check the End date entered is in desired format                              */
    IF (Instr(p_end_date_c,pg_dash_c,1,1) <> 5
          OR Instr(p_end_date_c,pg_dash_c,1,2) <> 8 )THEN
          RAISE END_DATE_FORMAT_EXCEPTION;
END IF;

/* Truncating the time stamp part of the begin Date                                */
    v_begin_date := TRUNC(TO_DATE(p_begin_date_c,
                    pg_date_time_format_c),pg_trunc_by_c);


/* Truncating the time stamp part of the begin Date                                */
    v_end_date := TRUNC(TO_DATE(p_end_date_c,
                  pg_date_time_format_c),pg_trunc_by_c);

/* Condition to check whether the two dates entered are same if they are same
    then it will be taken as AS OF DATE for positional reports                     */
/* If the two entered dates are not same then check for the dates validation       */

    v_location_i:= 40;

    IF (v_begin_date = v_end_date) THEN
       IF ((v_s_date - v_begin_date) < 0) THEN
         RAISE AS_OF_DATE_EXCEPTION;

ELSE
         po_Begin_date:= TO_DATE(v_begin_date);
         po_End_date:= TO_DATE(v_end_date);

END IF;

ELSE

        IF ((v_end_date - v_begin_date) < 0) THEN
           RAISE BEGIN_END_EXCEPTION;

        ELSIF ((v_s_date - v_begin_date) < 0) THEN
           RAISE BEGIN_SYS_EXCEPTION;

        ELSIF ((v_s_date - v_end_date) < 0) THEN
           RAISE END_SYS_EXCEPTION;

ELSE
           po_Begin_date:= TO_DATE(v_begin_date);
           po_End_date:= TO_DATE(v_end_date);

END IF;

END IF;

EXCEPTION
/* Exception Handling to check whether begin date is null                          */
       WHEN BEG_DATE_NULL_EXCEPTION THEN
            npf_err_pkg.parms2string(v_parms_c,'p_begin_date_c', p_begin_date_c );
            npf_err_pkg.parms2string(v_parms_c,'p_end_date_c',p_end_date_c);
            npf_err_pkg.rec_stop( -20007,pg_user_err_type_c,
            npf_err_pkg.get_user_err_msg(-20007,pg_user_err_type_c),
            v_parms_c,v_location_i,pg_package_c,v_procedure_name_c);


/* Exception Handling to check whether end date is null                            */
WHEN END_DATE_NULL_EXCEPTION THEN
            npf_err_pkg.parms2string(v_parms_c,'p_begin_date_c', p_begin_date_c );
            npf_err_pkg.parms2string(v_parms_c,'p_end_date_c',p_end_date_c);
            npf_err_pkg.rec_stop( -20008,pg_user_err_type_c,
            npf_err_pkg.get_user_err_msg(-20008,pg_user_err_type_c),
            v_parms_c,v_location_i,pg_package_c,v_procedure_name_c);

/* Exception Handling to check whether begin date entered
    is in yyyy-mm-dd format                                                        */
WHEN BEG_DATE_FORMAT_EXCEPTION THEN
            npf_err_pkg.parms2string(v_parms_c,'p_begin_date_c', p_begin_date_c );
            npf_err_pkg.parms2string(v_parms_c,'p_end_date_c',p_end_date_c);
            npf_err_pkg.rec_stop( -20001,pg_user_err_type_c,
            npf_err_pkg.get_user_err_msg(-20001,pg_user_err_type_c),
            v_parms_c,v_location_i,pg_package_c,v_procedure_name_c);

/* Exception Handling to check whether End date entered is in yyyy/mm/dd format    */
WHEN END_DATE_FORMAT_EXCEPTION THEN
            npf_err_pkg.parms2string(v_parms_c,'p_begin_date_c', p_begin_date_c );
            npf_err_pkg.parms2string(v_parms_c,'p_end_date_c',p_end_date_c);
            npf_err_pkg.rec_stop( -20002,pg_user_err_type_c,
            npf_err_pkg.get_user_err_msg(-20002,pg_user_err_type_c),
            v_parms_c,v_location_i,pg_package_c,v_procedure_name_c);

/* Exception Handling to check whether as of date entered is greater than sysdate  */
WHEN AS_OF_DATE_EXCEPTION THEN
            npf_err_pkg.parms2string(v_parms_c,'p_begin_date_c', p_begin_date_c );
            npf_err_pkg.parms2string(v_parms_c,'p_end_date_c',p_end_date_c);
            npf_err_pkg.rec_stop(-20003,pg_user_err_type_c,
            npf_err_pkg.get_user_err_msg(-20003,pg_user_err_type_c),
            v_parms_c,v_location_i,pg_package_c,v_procedure_name_c);

/* Exception Handling to check whether begin date is greater than End date         */
WHEN BEGIN_END_EXCEPTION THEN
            npf_err_pkg.parms2string(v_parms_c,'p_begin_date_c', p_begin_date_c );
            npf_err_pkg.parms2string(v_parms_c,'p_end_date_c',p_end_date_c);
            npf_err_pkg.rec_stop(-20004,pg_user_err_type_c,
            npf_err_pkg.get_user_err_msg(-20004,pg_user_err_type_c),
            v_parms_c,v_location_i,pg_package_c,v_procedure_name_c);

/* Exception Handling to check whether begin date is greater than sysdate          */
WHEN BEGIN_SYS_EXCEPTION THEN
            npf_err_pkg.parms2string(v_parms_c,'p_begin_date_c', p_begin_date_c );
            npf_err_pkg.parms2string(v_parms_c,'p_end_date_c',p_end_date_c);
            npf_err_pkg.rec_stop(-20005,pg_user_err_type_c,
            npf_err_pkg.get_user_err_msg(-20005,pg_user_err_type_c),
            v_parms_c,v_location_i,pg_package_c,v_procedure_name_c);

/* Exception Handling to check whether end date is greater than sysdate            */
WHEN END_SYS_EXCEPTION THEN
            npf_err_pkg.parms2string(v_parms_c,'p_begin_date_c', p_begin_date_c );
            npf_err_pkg.parms2string(v_parms_c,'p_end_date_c',p_end_date_c);
            npf_err_pkg.rec_stop(-20006,pg_user_err_type_c,
            npf_err_pkg.get_user_err_msg(-20006,pg_user_err_type_c),
            v_parms_c,v_location_i,pg_package_c,v_procedure_name_c);

WHEN OTHERS THEN
            npf_err_pkg.parms2string(v_parms_c,'p_begin_date_c', p_begin_date_c );
            npf_err_pkg.parms2string(v_parms_c,'p_end_date_c',p_end_date_c);
            npf_err_pkg.rec_stop(SQLCODE,pg_err_type_c,SQLERRM,v_parms_c,
            v_location_i,pg_package_c,v_procedure_name_c);

END npf_date_val_mgr;


/***********************************************************************************/
/*********************** Transaction Type Manager **********************************/
/***********************************************************************************/


  -- Name: npf_tran_typ_mgr
  --
  -- Type: Oracle Procedure
  --
  -- Description: This Common Module retrieves the fields from
  --              NPF_TRAN_CATG table.Corresponding to a given Tran Code and
  --              Data source Id and The Reporting Type
  --              This common module gives us the tran code along woth the the
  --              corresponding SuperCategory and
  --              SubCategory Codes and Descriptions.
  --
  --
  --
  --
  -- Technical: This is a Common Module which gives Supercategory and
  --            Subcategory codes and Descriptions.
  --
  --
  -- Notes:  This is a select procedure unit that IS NOT exposed to the user.
  --
  --
  -- Syntax: npf_tran_typ_mgr(
  --                          p_trancode_a,
  --                          p_datasrcid_a,
  --                          p_rptgtype_a,
  --                          po_trancode_a,
  --                          po_supcatgdesc_a,
  --                          po_subcatgdesc_a,
  --                          po_supcatgcode_a,
  --                          po_subcatgcode_a
  --                         );
  --
  --
  -- Where:     p_trancode_a is Transaction Code
  --            p_datasrcid_a is Data Source ID
  --            p_rptgtype_a is Reporting Type.For current reporting system it is
  --            'WLT'.
  --            po_trancode_a is Transaction Code
  --            po_supcatgdesc_a is Supercategory Description
  --            po_subcatgdesc_a is Subcategory Description
  --            po_supcatgcode_a is Supercategory Code
  --            po_subcatgcode_a is Subcategory Code
  --
  --
  -- Returns:   None
  --
  --
  --
  --


PROCEDURE npf_tran_typ_mgr (
                            p_trancode_a IN NPF_TRAN_CATG.tran_code%TYPE,
                            p_datasrcid_a IN NPF_TRAN_CATG.data_src_id%TYPE,
                            p_rptgtype_a IN NPF_TRAN_CATG.rptg_type%TYPE,
                            po_trancode_a OUT NPF_TRAN_CATG.tran_code%TYPE,
                            po_supcatgdesc_a OUT NPF_TRAN_CATG.supcatg_desc%TYPE,
                            po_subcatgdesc_a OUT NPF_TRAN_CATG.subcatg_desc%TYPE,
                            po_supcatgcode_a OUT NPF_TRAN_CATG.supcatg_code%TYPE,
                            po_subcatgcode_a OUT NPF_TRAN_CATG.subcatg_code%TYPE
                           )

AS

/* Variables used for error-handling                                               */
/* Exception location procedure/function name                                      */
v_procedure_name_c VARCHAR2(400);
/* This variable tracks the location within this procedure.                        */
v_location_i INTEGER;
/* Procedures parameters when the error occourred                                  */
v_parms_c VARCHAR2(4000);

/* Cursor to retrieve the Transaction Supercategory and Subcategory codes and
 Decsriptions from NPF_TRAN_CATG table                                             */
CURSOR tran_cursor

IS

SELECT
    ntc.tran_code, ntc.supcatg_desc, ntc.subcatg_desc,ntc.supcatg_code,
    ntc.subcatg_code
FROM
    NPF_TRAN_CATG ntc
WHERE
    ntc.tran_code = p_trancode_a
  AND
    ntc.data_src_id = p_datasrcid_a
  AND
    ntc.rptg_type = p_rptgtype_a;


BEGIN

    v_procedure_name_c := 'npf_tran_typ_mgr';
    v_parms_c := NULL;

    v_location_i:= 1;

    po_trancode_a := p_trancode_a;
    po_supcatgdesc_a := pg_supcatg_tran_desc_c;
    po_subcatgdesc_a := pg_subcatg_tran_desc_c;
    po_supcatgcode_a := pg_supcatg_tran_code_c;
    po_subcatgcode_a := pg_subcatg_tran_code_c;

OPEN tran_cursor;
FETCH tran_cursor
    INTO
    po_trancode_a,
    po_supcatgdesc_a,
    po_subcatgdesc_a,
    po_supcatgcode_a,
    po_subcatgcode_a;

CLOSE tran_cursor;

EXCEPTION
        WHEN OTHERS THEN
            npf_err_pkg.parms2string (v_parms_c,'p_trancode_a', p_trancode_a );
            npf_err_pkg.parms2string (v_parms_c,'p_rptgtype_a',p_rptgtype_a);
            npf_err_pkg.parms2string (v_parms_c,'p_datasrcid_a',p_datasrcid_a);
            npf_err_pkg.rec_stop(SQLCODE,pg_err_type_c,SQLERRM,v_parms_c,
                                 v_location_i,pg_package_c,v_procedure_name_c);

/* End of procedure npf_asst_typ_mgr                                               */
END npf_tran_typ_mgr;

/***********************************************************************************
 *****************Valuation Manager*************************************************/


  -- Name: npf_valn_mgr
  --
  -- Type: Oracle Procedure
  --
  -- Description:This is a common module which is used to calculate valuation
  --             frequency decode and valuation run time for the given account
  --             id and date passed
  --
  --
  --
  --
  -- Technical:  This module takes input date(s) as string and returns the
  --             valn_run_times as DATE out parameters. The input parameter
  --             End date is optional. For positional reports, only begin date
  --             will be passed, while for transactional reports, both dates
  --             will be passed.
  --
  --
  --
  -- Notes:    This is a select procedure unit that IS NOT exposed to the user.
  --
  --
  --
  --
  -- Syntax:   PROCEDURE npf_valn_mgr(
  --                                  p_ac_sk_a,
  --                                  p_begin_date_c,
  --                                  p_end_date_c,
  --                                  po_valn_freq_dcde_a,
  --                                  po_begin_valn_run_time_a,
  --                                  po_end_valn_run_time_a
  --                                 )
  --
  --
  --
  --
  --
  -- Where:     p_ac_sk_a is the account id entered as input
  --            p_begin_date_c is the begin date entered as input
  --            p_end_date_c is the end date entered as input
  --            report identification
  --            po_valn_freq_dcde_a is the valuation frequency code output
  --            po_begin_valn_run_time_a is the begin valuation run time.
  --            po_end_valn_run_time_a is the end valuation run time
  --
  --
  --
  --
  -- Returns:   None.
  --
  --
  --
  --

PROCEDURE npf_valn_mgr(
                       p_ac_sk_a IN NPF_ACCOUNT.ac_sk%TYPE,
                       p_begin_date_c IN VARCHAR2,
                       p_end_date_c IN VARCHAR2 DEFAULT 'NA',
                       po_valn_freq_dcde_a OUT NPF_AC_POSN_SUM.valn_freq_dcde%TYPE,
                       po_begin_valn_run_time_a OUT NPF_AC_POSN_SUM.valn_run_time%TYPE,
                       po_end_valn_run_time_a OUT NPF_AC_POSN_SUM.valn_run_time%TYPE
                      )

AS

/* Local Variables used for calculation inside this procedure                      */
v_As_of_date DATE;
v_From_date DATE;
v_Thru_date DATE;
v_LBDOM_date DATE;
v_FBDOM_date DATE;
v_Caln_date DATE;
v_day_c VARCHAR2(10);

/* Variables used for error-handling                                               */
/* Procedures parameters when the error occourred                                  */
v_parms_c VARCHAR2 (4000);
/* Exception location procedure/function name                                      */
v_procedure_name_c VARCHAR2(400);
/* This variable tracks the location within this procedure.                        */
v_location_i INTEGER;

/* Cursor for retrieving valn_freq_dcde and valn_run_time for
   monthly booked and daily informational data                                     */
CURSOR get_valn_cursor(
                       p_ac_sk_a IN NPF_ACCOUNT.AC_SK%TYPE,
                       p_as_of_date IN DATE
                      )
IS

SELECT
    MAX(valn_run_time) v_valn_run_time,valn_freq_dcde,valn_appr_flag
FROM
    NPF_AC_POSN_SUM
WHERE
--        TO_CHAR(valn_as_of_date,pg_std_date_format_c) =
--        TO_CHAR(p_as_of_date,pg_std_date_format_c)
  -- Trunc Changes for I20088
    valn_as_of_date BETWEEN TRUNC(p_as_of_date) and TRUNC(p_as_of_date) + 86399/86400	-- PG73 I20088
  AND
    ac_sk = p_ac_sk_a
GROUP BY
    valn_freq_dcde,valn_appr_flag
ORDER BY
    valn_freq_dcde DESC,valn_appr_flag DESC;


/* Executable section for npf_valn_mgr                                             */
BEGIN

/* Initialization of variables for error-handling                                  */
    v_parms_c := NULL;
    v_location_i := 1;
    v_procedure_name_c := 'npf_valn_mgr';

    IF (p_end_date_c = pg_not_applicable_c) THEN
/* Logic for positional reports                                                    */
/* Call to date cal. manager to calculate current business day                     */
        npf_date_cal_mgr(
                         p_begin_date_c,pg_curr_buss_day_c,
                         v_As_of_date,v_Caln_date
                        );

/* Calculation of valuation run time                                               */
FOR v_valn_cur IN get_valn_cursor(p_ac_sk_a,v_As_of_date)
        LOOP

            po_valn_freq_dcde_a := v_valn_cur.valn_freq_dcde;
            po_begin_valn_run_time_a := v_valn_cur.v_valn_run_time;
            EXIT;

END LOOP;

        v_location_i := 10;

/* If data is not present in table for given inputs then calculate valn_freq_dcde
   separately by comparing As of date with Last Business day of month              */
        IF (po_valn_freq_dcde_a IS NULL) THEN

            npf_date_cal_mgr (
                              p_begin_date_c, pg_last_busn_day_of_mth_c,
                              v_LBDOM_date,v_Caln_date
                             );

            v_location_i := 20;

/* Determine valn_freq_dcde by comparing As_of_date with LBDOM                     */
            IF (TO_CHAR(v_As_of_date,pg_std_date_format_c) =
                 TO_CHAR(v_LBDOM_date,pg_std_date_format_c)) THEN
                po_valn_freq_dcde_a := pg_flag_mth_booked_c;

ELSE
                po_valn_freq_dcde_a := pg_flag_dly_info_c;

END IF;

END IF;

        v_location_i := 30;

ELSE
/* Valuation logic for transactional reports                                       */
/* Call to date validation manager to validate the date and
   store it in v_From_date and v_Thru_date                                         */
        npf_date_val_mgr(
                         p_begin_date_c,p_end_date_c,v_From_date,v_Thru_date
                        );

/* Get first date of month by calling date calculation manager                     */
        npf_date_cal_mgr(
                         p_begin_date_c,pg_first_busn_day_of_mth_c,
                         v_FBDOM_date,v_Caln_date
                        );

        v_location_i := 40;

/* Calculation of valuation frequency decode                                       */
        IF (TO_CHAR(v_From_date) = TO_CHAR(v_Caln_date)) THEN
            po_valn_freq_dcde_a := pg_flag_mth_booked_c;

ELSE
            po_valn_freq_dcde_a := pg_flag_dly_info_c;

END IF;

        v_location_i := 50;

        v_From_date := v_From_date - 1;

/* Retrieve valn_run_time for Begin date                                           */
FOR v_valn_cur IN get_valn_cursor(p_ac_sk_a,v_From_date)
        LOOP

            po_begin_valn_run_time_a := v_valn_cur.v_valn_run_time;
            EXIT;

END LOOP;

/* If no data for valn_run_time for begin date then put it same as begin date      */
        po_begin_valn_run_time_a := NVL(po_begin_valn_run_time_a,v_From_date);

/* Retrieve valn_run_time for End date                                             */
FOR v_valn_cur IN get_valn_cursor(p_ac_sk_a,v_Thru_date)
        LOOP

            po_end_valn_run_time_a := v_valn_cur.v_valn_run_time;
            EXIT;

END LOOP;

/* If no data for valn_run_time for begin date then put it same as begin date      */
        po_end_valn_run_time_a := NVL(po_end_valn_run_time_a,v_Thru_date);

END IF;

EXCEPTION
    WHEN OTHERS THEN
        npf_err_pkg.parms2string (v_parms_c,'p_ac_sk_a',p_ac_sk_a );
        npf_err_pkg.parms2string (v_parms_c,'p_begin_date_c',p_begin_date_c);
        npf_err_pkg.parms2string (v_parms_c,'p_end_date_c',p_end_date_c);
        npf_err_pkg.rec_stop(SQLCODE,pg_err_type_c,SQLERRM,v_parms_c,
                             v_location_i,pg_package_c,v_procedure_name_c);

END npf_valn_mgr;
/***********************************************************************************
 *****************Valuation Manager*************************************************/


  -- Name: npf_valn_mgr
  --
  -- Type: Oracle Procedure
  --
  -- Description:This is a common module which is used to calculate valuation
  --             frequency decode and valuation run time for the given account
  --             id and date passed
  --
  --
  --
  --
  -- Technical:  This module takes input date(s) as string and returns the
  --             valn_run_times as DATE out parameters. The input parameter
  --             End date is optional. For positional reports, only begin date
  --             will be passed, while for transactional reports, both dates
  --             will be passed.
  --
  --
  --
  -- Notes:    This is a select procedure unit that IS NOT exposed to the user.
  --
  --
  --
  --
  -- Syntax:   PROCEDURE npf_valn_mgr(
  --                     p_ac_sk_a IN NPF_ACCOUNT.ac_sk%TYPE,
  --                     p_begin_date_c IN VARCHAR2,
  --                     p_end_date_c IN VARCHAR2 DEFAULT pg_not_applicable_c,
  --                     po_valn_freq_dcde_a OUT NPF_AC_POSN_SUM.valn_freq_dcde%TYPE,
  --                     po_begin_valn_run_time_a OUT NPF_AC_POSN_SUM.valn_run_time%TYPE,
  --                     po_end_valn_run_time_a OUT NPF_AC_POSN_SUM.valn_run_time%TYPE,
  --                     po_max_valn_date OUT NPF_AC_POSN_SUM.valn_as_of_date%TYPE,
  --                     po_max_valn_end_date OUT NPF_AC_POSN_SUM.valn_as_of_date%TYPE
  --                                 )
  --
  --
  --
  --
  --
  -- Where:     p_ac_sk_a is the account id entered as input
  --            p_begin_date_c is the begin date entered as input
  --            p_end_date_c is the end date entered as input
  --            report identification
  --            po_valn_freq_dcde_a is the valuation frequency code output
  --            po_begin_valn_run_time_a is the begin valuation run time.
  --            po_end_valn_run_time_a is the end valuation run time
  --
  --
  --
  --
  -- Returns:   None.
  --
  --
  --
  --


PROCEDURE npf_valn_mgr(
                       p_ac_sk_a IN NPF_ACCOUNT.ac_sk%TYPE,
                       p_begin_date_c IN VARCHAR2,
                       p_end_date_c IN VARCHAR2 DEFAULT 'NA',
                       po_valn_freq_dcde_a OUT NPF_AC_POSN_SUM.valn_freq_dcde%TYPE,
                       po_begin_valn_run_time_a OUT NPF_AC_POSN_SUM.valn_run_time%TYPE,
                       po_end_valn_run_time_a OUT NPF_AC_POSN_SUM.valn_run_time%TYPE,
                       po_max_valn_date OUT NPF_AC_POSN_SUM.valn_as_of_date%TYPE,
                       po_max_valn_end_date OUT NPF_AC_POSN_SUM.valn_as_of_date%TYPE,
                       p_object_type_id_c IN VARCHAR2 DEFAULT NULL,    -- added for GDR Changes
                       p_strm_ac_consl_flag IN VARCHAR2 DEFAULT NULL,   -- added for GDR Changes
                       p_tran_typ_flag IN VARCHAR2 DEFAULT NULL -- added for GDR Changes
                      )


AS

    /* Local Variables used for calculation inside this procedure                      */
    v_As_of_date DATE;
    v_From_date DATE;
    v_Thru_date DATE;
    v_LBDOM_date DATE;
    v_FBDOM_date DATE;
    v_Caln_date DATE;
    v_day_c VARCHAR2(10);

    -- New vars required after update to this package
     v_As_of_date_d DATE;         --mm155 07/15/2005
     v_Caln_date_d DATE;          --mm155 07/15/2005
     v_As_of_date_e DATE;         --mm155 07/15/2005
     v_Caln_date_e DATE;          --mm155 07/15/2005
     v_max_valn_date_begin DATE;  --mm155 07/15/2005
     v_max_valn_date_end DATE;    --mm155 07/15/2005

     v_begin_valn_run_time DATE;  --mm155 07/19/2005 var output
     v_valn_appr_flag VARCHAR2(5); --mm155 07/19/2005 var output

    /* Variables used for error-handling                                               */
    /* Procedures parameters when the error occourred                                  */
    v_parms_c VARCHAR2 (4000);
    /* Exception location procedure/function name                                      */
    v_procedure_name_c VARCHAR2(400);
    /* This variable tracks the location within this procedure.                        */
    v_location_i INTEGER;

     -- added for GDR Changes starts here
     v_npf_data_load_date DATE;
     v_begin_date_c       VARCHAR2(100);
     v_begin_date_d       DATE;
     v_end_date_c         VARCHAR2(100);
     v_end_date_d         DATE;
     v_gdr_report_flag    VARCHAR2(1);
     v_strm_cnt           NUMBER := 0;
     v_data_load_flag     VARCHAR2(1) := 'N';
     v_data_src_id        NUMBER;
     v_gdr_glbl_flag      CHAR;
     -- added for GDR Changes ends here

        /* Cursor for retrieving valn_freq_dcde and valn_run_time for
            monthly booked and daily informational data                                     */

CURSOR get_valn_cursor(p_ac_sk_a IN NPF_ACCOUNT.AC_SK%TYPE,
                               p_as_of_date IN DATE)
        IS

SELECT MAX(valn_run_time) v_valn_run_time,
       valn_freq_dcde,
       valn_appr_flag
FROM NPF_AC_POSN_SUM
WHERE  -- TO_CHAR(valn_as_of_date,pg_std_date_format_c) = TO_CHAR(p_as_of_date,pg_std_date_format_c)
  -- Trunc Changes for I20088
    valn_as_of_date BETWEEN TRUNC(p_as_of_date) and TRUNC(p_as_of_date) + 86399/86400	-- PG73 I20088
  AND ac_sk = p_ac_sk_a
GROUP BY valn_freq_dcde,valn_appr_flag
ORDER BY valn_freq_dcde DESC,valn_appr_flag DESC;

-- Local procedure
PROCEDURE npf_get_max_valn_date(p_ac_sk IN NPF_ACCOUNT.AC_SK%TYPE,
p_busn_date IN DATE,
p_caln_date IN DATE,
po_max_valn_date OUT DATE)
AS

         v_max_valn_date_c DATE;


         -- Executable section for npf_get_max_valn_date procedure
BEGIN
           --Initialization of variables for error-handling
            v_parms_c := NULL;
            v_location_i := 1;
            v_procedure_name_c := 'npf_get_max_valn_date';
SELECT MAX(valn_as_of_date)
INTO v_max_valn_date_c
FROM NPF_AC_POSN_SUM
WHERE ac_sk = p_ac_sk
  AND (
    (TRUNC(p_busn_date) <= TRUNC(p_caln_date)  AND
        --   TRUNC(valn_as_of_date) BETWEEN TRUNC(p_busn_date) AND TRUNC(p_caln_date)            -- PG73 I20088
        -- Trunc Changes for I20088
     valn_as_of_date BETWEEN TRUNC(p_busn_date) and TRUNC(p_caln_date) + 86399/86400)
        OR
    (TRUNC(p_busn_date) >  TRUNC(p_caln_date)  AND
        --   TRUNC(valn_as_of_date) BETWEEN TRUNC(p_caln_date) and TRUNC(p_busn_date)            -- PG73  I20088
        -- Trunc Changes for I20088
     valn_as_of_date BETWEEN TRUNC(p_caln_date) and TRUNC(p_busn_date) + 86399/86400)
    );

/* PCPDR2005-10012 - SG78 - 12/15/2005 - Added TRUNC clauses to all of the dates above inorder to shield
   ourselves from the overall hours,mins,secs, and AM/PM portion of the date. A problem arouse when rows
   where added to the NPF_AC_POSN_SUM table with varying AM/PM timestamps. This caused the BETWEEN clause
   to grab the prior days valuation. */



po_max_valn_date := v_max_valn_date_c;

EXCEPTION
                WHEN OTHERS THEN
                    npf_err_pkg.parms2string (v_parms_c,'p_busn_date', p_busn_date );
                    npf_err_pkg.rec_stop(SQLCODE,pg_err_type_c,SQLERRM,v_parms_c,
                                     v_location_i,pg_package_c,v_procedure_name_c);
END npf_get_max_valn_date;

    /* Executable section for npf_valn_mgr                                             */
BEGIN

    /* Initialization of variables for error-handling                                  */
        v_parms_c := NULL;
        v_location_i := 1;
        v_procedure_name_c := 'npf_valn_mgr';

        -- GDR Changes starts here
        -- get GDR_REPORT_FLAG from decode table

        v_gdr_report_flag := NVL(npf_util_pkg.get_dcde_desc('GDR_ENBL_FLG', 'REPORT_FLAG'), 'N');
        v_gdr_glbl_flag   := NVL(npf_util_pkg.get_dcde_desc('GDR_ENBL_FLG', 'GDR_GLBL'), 'N');

        --dbms_output.put_line('v_gdr_report_flag - '||v_gdr_report_flag);
        -- get the data load date
SELECT TRUNC(data_load_date) INTO v_npf_data_load_date FROM npf_data_load_date;

-- Check if the begin date is greater than data_load_date
-- If yes, check if it is global account and check for latest valn date for the account
--npf_common_pkg.npf_date_val_mgr(p_begin_date_c,v_begin_date_d);
v_begin_date_d := TO_DATE(p_begin_date_c, pg_date_time_format_c);

        -- get latest valn date for the account only if the
        -- GDR_REPORT_FLAG is Y
        -- and In begin date > data_load_date
        -- and consolidation has atleast on completed stream account
        -- and if it is p_object_type_id_c is CONSL/GDRINTRA

BEGIN
SELECT data_src_id
INTO v_data_src_id
FROM npf_account
WHERE ac_sk = p_ac_sk_a;
EXCEPTION WHEN OTHERS THEN
          v_data_src_id := 0;
END;

SELECT COUNT(1)
INTO v_strm_cnt
FROM NPF_DATA_SRC_STREAM_WLT_AC_VW ac,
     NPF_DATA_SRC_STREAM_WLT_RUN_VW run
WHERE ac.ac_sk = p_ac_sk_a
  AND run.src_stream_id = ac.src_stream_id
  AND run.src_stream_stat = 'NPF_DATALOAD_SUCCESS'
  AND run.STREAM_LOAD_DATE = v_begin_date_d;

IF v_strm_cnt = 0 THEN
SELECT DECODE(COUNT(1), 0, 'N', 'Y')
INTO v_data_load_flag
FROM NPF_DATA_LOAD
WHERE TRUNC(NPF_DATA_LOAD_DATE) = v_begin_date_d
  AND DATA_SRC_ID = v_data_src_id
  AND DATA_SRC_ID NOT IN (SELECT DISTINCT DATA_SRC_ID FROM NPF_DATA_SRC_STREAM_WLT_RUN_VW)
  AND STAT_DCDE = 'SUCCESS';
END IF;

        IF (v_begin_date_d >= v_npf_data_load_date AND (v_data_load_flag = 'N' OR v_strm_cnt = 0)
       AND ((v_gdr_report_flag = 'Y' AND NVL(p_object_type_id_c, ' ') = 'CONSL' AND p_strm_ac_consl_flag = 'Y' AND p_tran_typ_flag IS NULL))
           )
        OR (v_begin_date_d >= v_npf_data_load_date AND NVL(p_object_type_id_c, ' ') = 'GDRINTRA' AND (v_data_load_flag = 'N' OR v_strm_cnt = 0)) AND v_gdr_glbl_flag = 'Y' THEN
          v_begin_date_c := npf_common_pkg_wlth.get_last_valn_date(p_ac_sk_a, p_begin_date_c);

        -- if data load/stream load is completed for the latest date, pass the same date to report
        ELSIF v_gdr_report_flag = 'Y' AND NVL(p_object_type_id_c, ' ') = 'CONSL' AND p_strm_ac_consl_flag = 'Y'
              AND p_tran_typ_flag IS NULL
              AND v_begin_date_d = npf_ac_posn_filter_pkg.get_gdr_date AND ((v_data_load_flag = 'Y' ) OR (v_strm_cnt > 0)) AND v_gdr_glbl_flag = 'Y'
        THEN
          v_begin_date_c := p_begin_date_c;
ELSE
          v_begin_date_c := p_begin_date_c;
END IF;
        -- GDR Changes ends here

        IF (p_end_date_c = pg_not_applicable_c) THEN

            ----------------------------------------------------------------------------------------------------
            -- Logic for positional reports
            ----------------------------------------------------------------------------------------------------

                   -- Call to date cal. manager to calculate current business day
                    npf_date_cal_mgr(v_begin_date_c,    -- p_begin_date_c -> v_begin_date_c for GDR changes
                                     pg_curr_buss_day_c,
                                     v_As_of_date,
                                     v_Caln_date);

                   -- get the max valuation date between v_as_of_date and v_Caln_date for a given account
                    npf_get_max_valn_date(p_ac_sk_a,
                                          v_As_of_date-1, --mm155 07/19/2005
                                          v_Caln_date,
                                          po_max_valn_date);

                  -- po_valn_as_of_date := po_max_valn_date_c;


                --  FOR v_valn_cur IN get_valn_cursor(p_ac_sk_a,v_As_of_date) MM155 07/15/2005

                -- Calculation of valuation run time
FOR v_valn_cur IN get_valn_cursor(p_ac_sk_a,po_max_valn_date) --MM155 07/15/2005
                    LOOP
                        po_valn_freq_dcde_a := v_valn_cur.valn_freq_dcde;
                        po_begin_valn_run_time_a := v_valn_cur.v_valn_run_time;
                        v_valn_appr_flag := v_valn_cur.valn_appr_flag;          --mm155 07/19/2005

                        EXIT;
END LOOP;

                    v_location_i := 10;

                    -- Below code is moved up from  IF (po_valn_freq_dcde_a IS NULL) THEN because this will be used outside the if condition
                    npf_date_cal_mgr (v_begin_date_c,   -- v_begin_date_c -> v_begin_date_c
                                      pg_last_busn_day_of_mth_c,
                                      v_LBDOM_date,v_Caln_date);                  -- mm155 07/14/2005 not required to pass ac_sk because we are not getting Valuation rundates


                    /* If data is not present in table for given inputs then calculate valn_freq_dcde
                        separately by comparing As of date with Last Business day of month              */
                    IF (po_valn_freq_dcde_a IS NULL) THEN

                        v_location_i := 20;

                        /* Determine valn_freq_dcde by comparing As_of_date with LBDOM                     */
                        IF (TO_CHAR(v_As_of_date,pg_std_date_format_c) =
                             TO_CHAR(v_LBDOM_date,pg_std_date_format_c)) THEN
                            po_valn_freq_dcde_a := pg_flag_mth_booked_c;

ELSE
                            po_valn_freq_dcde_a := pg_flag_dly_info_c;

END IF;

END IF;

                    v_location_i := 30;


ELSE

        ----------------------------------------------------------------------------------------------------
        /* Valuation logic for transactional reports                                       */
        -----------------------------------------------------------------------------------------------------
              -- GDR Changes starts here
              -- Check if the end date is greater than data_load_date
              -- If yes, check if it is global account and check for latest valn date for the account
              --npf_common_pkg.npf_date_val_mgr(p_end_date_c,v_end_date_d);
              v_end_date_d := TO_DATE(p_end_date_c, pg_date_time_format_c);

              -- get latest valn date for the account only if the
              -- GDR_REPORT_FLAG is Y
              -- and In begin date > data_load_date
              -- and consolidation has atleast on completed stream account
              -- and if it is p_object_type_id_c is CONSL/GDRINTRA
SELECT COUNT(1)
INTO v_strm_cnt
FROM NPF_DATA_SRC_STREAM_WLT_AC_VW ac,
     NPF_DATA_SRC_STREAM_WLT_RUN_VW run
WHERE ac.ac_sk = p_ac_sk_a
  AND run.src_stream_id = ac.src_stream_id
  AND run.src_stream_stat = 'NPF_DATALOAD_SUCCESS'
  AND run.STREAM_LOAD_DATE = v_end_date_d;

IF v_strm_cnt = 0 THEN
SELECT DECODE(COUNT(1), 0, 'N', 'Y')
INTO v_data_load_flag
FROM NPF_DATA_LOAD
WHERE TRUNC(NPF_DATA_LOAD_DATE) = v_end_date_d
  AND DATA_SRC_ID = v_data_src_id
  AND DATA_SRC_ID NOT IN (SELECT DISTINCT DATA_SRC_ID FROM NPF_DATA_SRC_STREAM_WLT_RUN_VW)
  AND STAT_DCDE = 'SUCCESS';
END IF;


              IF (v_end_date_d >= v_npf_data_load_date AND (v_data_load_flag = 'N' OR v_strm_cnt = 0)
             AND ((v_gdr_report_flag = 'Y' AND NVL(p_object_type_id_c, ' ') = 'CONSL' AND p_strm_ac_consl_flag = 'Y' AND p_tran_typ_flag IS NULL))
                 )
              OR (v_end_date_d >= v_npf_data_load_date AND NVL(p_object_type_id_c, ' ') = 'GDRINTRA' AND (v_data_load_flag = 'N' OR v_strm_cnt = 0)) AND v_gdr_glbl_flag = 'Y' THEN
                v_end_date_c := npf_common_pkg_wlth.get_last_valn_date(p_ac_sk_a, p_end_date_c);

              -- if data load/stream load is completed for the latest date, pass the same date to report
              ELSIF v_gdr_report_flag = 'Y' AND NVL(p_object_type_id_c, ' ') = 'CONSL' AND p_strm_ac_consl_flag = 'Y'
                    AND p_tran_typ_flag IS NULL
                    AND v_end_date_d = npf_ac_posn_filter_pkg.get_gdr_date AND ((v_data_load_flag = 'Y' ) OR (v_strm_cnt > 0)) AND v_gdr_glbl_flag = 'Y'
              THEN
                v_end_date_c := p_end_date_c;
ELSE
                v_end_date_c := p_end_date_c;
END IF;

              -- GDR Changes ends here


            /* Call to date validation manager to validate the date and
               store it in v_From_date and v_Thru_date                                         */
                    npf_date_val_mgr(v_begin_date_c,    -- p_begin_date_c -> v_begin_date_c for GDR changes
                                     v_end_date_c,   -- p_end_date_c -> v_end_date_c for GDR changes
                                     v_From_date,
                                     v_Thru_date);

            /* Get first date of month by calling date calculation manager                     */
                    npf_date_cal_mgr(v_begin_date_c,    -- p_begin_date_c -> v_begin_date_c for GDR changes
                                     pg_first_busn_day_of_mth_c,
                                     v_FBDOM_date,
                                     v_Caln_date);

                    v_location_i := 40;

            /* Calculation of valuation frequency decode                                       */
                    IF (TO_CHAR(v_From_date) = TO_CHAR(v_Caln_date)) THEN
                        po_valn_freq_dcde_a := pg_flag_mth_booked_c;

ELSE
                        po_valn_freq_dcde_a := pg_flag_dly_info_c;

END IF;

                    v_location_i := 50;

                    v_From_date := v_From_date - 1;

                    -------------------------------------------------------------------------------------
                    -- Begin Date Logic for Transactional Report
                    --------------------------------------------------------------------------------------

                   -- mm155 07/15/2005
                   -- get the current business day  for e.g. you user input is 05/01/2005 then -1 becomes 04/30/2005
                   -- so we need to get max date between 4/30/2005 and 4/28/2005
                    npf_date_cal_mgr(
                                   TO_CHAR(v_From_date,'YYYY-MM-DD'),pg_curr_buss_day_c,
                                   v_As_of_date_d,v_Caln_date_d);



                   -- mm155 07/15/2005
                   -- Call npf_get_max_valn_date to get the max valuation date between v_From_date - 1 and last business day
                    npf_get_max_valn_date(p_ac_sk_a,
                                          v_As_of_date_d-1,  --mm155 07/19/2005
                                          v_Caln_date_d,
                                          v_max_valn_date_begin);



                    --FOR v_valn_cur IN get_valn_cursor(p_ac_sk_a,v_From_date)
                    -- mm155 07/15/2005
                    -- Retrieve valn_run_time for Begin date
FOR v_valn_cur IN get_valn_cursor(p_ac_sk_a,v_max_valn_date_begin)
                    LOOP
                        po_begin_valn_run_time_a := v_valn_cur.v_valn_run_time;
                        EXIT;
END LOOP;

                    po_max_valn_date := v_max_valn_date_begin ;
                    -- If no data for max valn begin date then put it same as begin date   mm155 07/24/2005
                    po_max_valn_date := NVL(po_max_valn_date,v_From_date);

                    /* If no data for valn_run_time for begin date then put it same as begin date      */
                    po_begin_valn_run_time_a := NVL(po_begin_valn_run_time_a,v_From_date);

                    -------------------------------------------------------------------------------------
                    -- End Date Logic for Transactional Report
                    --------------------------------------------------------------------------------------

                    -- mm155 07/15/2005
                    --Call to date cal. manager to calculate current business day
                    npf_date_cal_mgr(
                                     TO_CHAR(v_Thru_date,'YYYY-MM-DD'),pg_curr_buss_day_c,
                                     v_As_of_date_e,v_Caln_date_e);

                 -- get the max valuation date between the above date ranges
                    npf_get_max_valn_date(p_ac_sk_a,
                                          v_As_of_date_e-1, --mm155 07/19/2005
                                          v_Caln_date_e,
                                          v_max_valn_date_end);



                   -- mm155 07/15/2005
                   -- Retrieve valn_run_time for End date                                             */
                   -- FOR v_valn_cur IN get_valn_cursor(p_ac_sk_a,v_Thru_date)
FOR v_valn_cur IN get_valn_cursor(p_ac_sk_a,v_max_valn_date_end)
                    LOOP
                        po_end_valn_run_time_a := v_valn_cur.v_valn_run_time;
                        EXIT;
END LOOP;

                   -- assigning v_max_valn_date_end to parameter out var
                    po_max_valn_end_date  := v_max_valn_date_end;

               /* If no data for po_max_valn_end_date for through date then put it same as through date    */    -- mm155 07/30/2005
                  po_max_valn_end_date := NVL(po_max_valn_end_date,v_Thru_date);

               /* If no data for valn_run_time for begin date then put it same as begin date      */
                    po_end_valn_run_time_a := NVL(po_end_valn_run_time_a,v_Thru_date);

END IF;

EXCEPTION
    WHEN OTHERS THEN
        npf_err_pkg.parms2string (v_parms_c,'p_ac_sk_a',p_ac_sk_a );
        npf_err_pkg.parms2string (v_parms_c,'p_begin_date_c',p_begin_date_c);
        npf_err_pkg.parms2string (v_parms_c,'p_end_date_c',p_end_date_c);
        npf_err_pkg.rec_stop(SQLCODE,pg_err_type_c,SQLERRM,v_parms_c,
                             v_location_i,pg_package_c,v_procedure_name_c);

END npf_valn_mgr;

/***
* Procedure Name: get_bank_holiday_list
* Objective	: This procedure fetches all the bank holidays within the given date range.
* Table		: NPF_CALENDAR
* Author	: ps242
* Date 		: 30/05/2014
*
*/
   PROCEDURE GET_BANK_HOLIDAY_LIST(
                              p_start_date IN DATE,
                              p_end_date IN DATE,
                              p_cur_out  OUT SYS_REFCURSOR
    )IS
    v_timestamp TIMESTAMP               :=systimestamp;
    v_procedure_c CONSTANT VARCHAR2(30) := 'GET_BANK_HOLIDAY_LIST';
    v_location_i  INTEGER;        -- This variable tracks our location within this procedure.
    v_parms_c     VARCHAR2(4000); -- This variable records the calling parameters for debugging and error recording operations.
BEGIN
OPEN P_CUR_OUT FOR
SELECT TO_CHAR(npf_calendar_date, 'DAY') AS holidayName, npf_calendar_date AS  holidayDate
FROM npfdbo.npf_calendar
WHERE npf_calendar_date BETWEEN p_start_date AND p_end_date AND is_bank_open = 'N'
  AND TRIM(TO_CHAR(npf_calendar_date, 'DAY')) NOT IN ('SATURDAY','SUNDAY');
EXCEPTION
        WHEN OTHERS THEN
          NPF_ERR_PKG.PARMS2STRING(V_PARMS_C, 'p_start_date', P_START_DATE);
          NPF_ERR_PKG.PARMS2STRING(V_PARMS_C, 'p_end_date', P_END_DATE);
          npf_err_pkg.rec_stop (sqlcode, 'ORACLE', null, v_parms_c, v_location_i, pg_package_c, v_procedure_c);
END GET_BANK_HOLIDAY_LIST;

END npf_common_pkg;
