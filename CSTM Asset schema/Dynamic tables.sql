create or replace dynamic table UAT_WPA_ASSET_DB.CORE.WPA_ASSET_DYN(
	INSTR_ID,
	ISS_TYPE,
	ISIN_ID,
	CUSIP_ID,
	SEDOL_ID,
	FM_SEC_ID,
	TNT_SEC_ID,
	ST_INCRP_DCDE,
	MATUR_DATE,
	TOT_SHR_OUTST_AMT,
	AST_SHORT_DESC,
	AST_LONG_DESC,
	MOODY_QUAL_DCDE,
	SP_QUAL_DCDE,
	CALL_PRC_AMT,
	CALL_DATE,
	TKR_SYM_ID,
	ORIG_ISS_DATE,
	ORIG_ISS_AMT,
	CNTRY_QUOTE_DCDE,
	CNTRY_RISK_DCDE,
	DENOM_CURR_DCDE,
	PRC_CURR_DCDE,
	INC_RT_AMT,
	DUR_TO_MATUR_AMT,
	PYBL_DATE,
	REC_DATE,
	EX_DIV_DATE,
	BETA_PRED_RT_AMT,
	BETA_PRED_LCL_RT_AMT,
	BETA_PRED_WRLD_RT_AMT,
	ROR_DV_RT_AMT,
	MKT_CAP_AMT,
	MKT_CAP_CURR_DCDE,
	PE_RATIO_AMT,
	EPS_AMT,
	EPS_12_MO_AMT,
	EPS_5YR_GROW_AMT,
	CNTRY_INCRP_DCDE,
	CINS_ID,
	PVT_PLC_ID,
	ISSR_DESC,
	PYMT_FREQ_DCDE,
	PYDN_FCTR_RT_AMT,
	ROR_MATUR_RT_AMT,
	GICS_IND_GRP_DCDE,
	GICS_IND_CLASS_DCDE,
	GICS_SUB_IND_DCDE,
	EPS_CURR_DCDE,
	ADR_FACTOR_AMT,
	ADR_RELAT_SEDOL_ID,
	ADR_RELAT_CUSIP_ID,
	ADR_RELAT_ISIN_ID,
	SHRS_OUTST_AMT,
	TOT_ISS_AMT,
	CONSD_CONST_RT_AMT,
	DEBT_TO_CAP_RT_AMT,
	DEBT_TO_EQTY_RT_AMT,
	DIV_5YR_GROW_RT_AMT,
	PRC_TO_SALE_RT_AMT,
	PRC_TO_CASH_FLOW_RT_AMT,
	PRC_TO_BV_RT_AMT,
	ROE_RT_AMT,
	ROC_RT_AMT,
	ROA_RT_AMT,
	PRIM_TRD_EXCH_DCDE,
	RTRS_CDE,
	POOL_ID,
	FRST_CPN_DATE,
	PRE_REFND_DATE,
	PCR_AST_ID,
	BKRG_AST_ID,
	DATA_SRC_ID,
	MAN_AGGR_AST_ID,
	ACTV_STAT_TYPE,
	PRTNR_STMT_DATE,
	PRTNR_VALN_RCVD_DATE,
	LOC_COMMT_AMT,
	VINTAGE_YR,
	FUND_TYPE,
	STRK_PRC_AMT,
	MKT_CAP_GRP_DCDE,
	LOC_FUND_AMT,
	AMT_ELIG_INDC,
	YLD_TO_MATUR_AMT,
	YRS_TO_MATUR_AMT,
	PIT_SWEEP_FLAG,
	MMF_NAV_IND,
	REGION_RISK_CURR_DESC,
	GICS_ECON_SECTR_DCDE_DESC,
	GICS_IND_CLASS_DCDE_DESC,
	GICS_IND_GRP_DCDE_DESC,
	GICS_SUB_IND_DCDE_DESC,
	CNTRY_RISK_DCDE_DESC,
	CNTRY_INCRP_DCDE_DESC,
	CNTRY_QUOTE_DCDE_DESC,
	DENOM_CURR_DCDE_DESC,
	PYMT_FREQ_DCDE_DESC,
	ST_INCRP_DCDE_DESC,
	AST_SHORT_LONG_DESC_FLG,
	AST_LNG_DESCRIPTION,
	GICS_ECON_SECTR_DCDE,
	MKT_CAP_CURR_DCDE_DESC,
	PRC_CURR_DCDE_DESC,
	EPS_CURR_DCDE_DESC,
	MOODY_QUAL_DCDE_DESC,
	PRIM_TRD_EXCH_DCDE_DESC,
	SP_QUAL_DCDE_DESC
) target_lag = '5 minutes' refresh_mode = INCREMENTAL initialize = ON_SCHEDULE warehouse = UAT_WPA_DYNAMICTABLE_VWH
 as
WITH INSTR_IDS AS (
    SELECT DISTINCT INSTR_ID FROM UAT_WPA_HOLDINGS_DB.CORE.WPA_AC_POSITION
    UNION 
    SELECT DISTINCT INSTR_ID FROM UAT_WPA_TRANSACTION_DB.CORE.WPA_TRANSACTION_DYN
)
SELECT
    ast.instr_id,
    ast.iss_type,
    ast.isin_id,
    ast.cusip_id,
    ast.sedol_id,
    ast.fm_sec_id,
    ast.tnt_sec_id,
    ast.st_incrp_dcde,
    ast.matur_date,
    ast.tot_shr_outst_amt,
    ast.ast_short_desc,
    ast.ast_long_desc,
    ast.moody_qual_dcde,
    ast.sp_qual_dcde,
    ast.call_prc_amt,
    ast.call_date,
    ast.tkr_sym_id,
    ast.orig_iss_date,
    ast.orig_iss_amt,
    ast.cntry_quote_dcde,
    ast.cntry_risk_dcde,
    ast.denom_curr_dcde,
    ast.prc_curr_dcde,
    ast.inc_rt_amt,
    ast.dur_to_matur_amt,
    ast.pybl_date,
    ast.rec_date,
    ast.ex_div_date,
    ast.beta_pred_rt_amt,
    ast.beta_pred_lcl_rt_amt,
    ast.beta_pred_wrld_rt_amt,
    ast.ror_dv_rt_amt,
    ast.mkt_cap_amt,
    ast.mkt_cap_curr_dcde,
    ast.pe_ratio_amt,
    ast.eps_amt,
    ast.eps_12_mo_amt,
    ast.eps_5yr_grow_amt,
    ast.cntry_incrp_dcde,
    ast.cins_id,
    ast.pvt_plc_id,
    ast.issr_desc,
    ast.pymt_freq_dcde,
    ast.pydn_fctr_rt_amt,
    ast.ror_matur_rt_amt,
    ast.gics_ind_grp_dcde,
    ast.gics_ind_class_dcde,
    ast.gics_sub_ind_dcde,
    ast.eps_curr_dcde,
    ast.adr_factor_amt,
    ast.adr_relat_sedol_id,
    ast.adr_relat_cusip_id,
    ast.adr_relat_isin_id,
    ast.shrs_outst_amt,
    ast.tot_iss_amt,
    ast.consd_const_rt_amt,
    ast.debt_to_cap_rt_amt,
    ast.debt_to_eqty_rt_amt,
    ast.div_5yr_grow_rt_amt,
    ast.prc_to_sale_rt_amt,
    ast.prc_to_cash_flow_rt_amt,
    ast.prc_to_bv_rt_amt,
    ast.roe_rt_amt,
    ast.roc_rt_amt,
    ast.roa_rt_amt,
    ast.prim_trd_exch_dcde,
    ast.rtrs_cde,
    ast.pool_id,
    ast.frst_cpn_date,
    ast.pre_refnd_date,
    ast.pcr_ast_id,
    ast.bkrg_ast_id,
    ast.data_src_id,
    ast.man_aggr_ast_id,
    ast.actv_stat_type,
    ast.prtnr_stmt_date,
    ast.prtnr_valn_rcvd_date,
    ast.loc_commt_amt,
    ast.vintage_yr,
    ast.fund_type,
    ast.strk_prc_amt,
    ast.mkt_cap_grp_dcde,
    ast.loc_fund_amt,
    ast.amt_elig_indc,
    ast.yld_to_matur_amt,
    ast.yrs_to_matur_amt,
    ast.pit_sweep_flag,
    ast.mmf_nav_ind,
    region.code_desc                              AS region_risk_curr_desc,
    NVL(gise.code_desc, 'Miscellaneous')          AS gics_econ_sectr_dcde_desc,
    NVL(gicls.code_desc, 'Miscellaneous')         AS gics_ind_class_dcde_desc,
    NVL(giind.code_desc, 'Miscellaneous')         AS gics_ind_grp_dcde_desc,
    NVL(gicsub.code_desc, 'Miscellaneous')        AS gics_sub_ind_dcde_desc,
    NVL(cd.code_desc, 'Unknown')                  AS cntry_risk_dcde_desc,
    NVL(incrp.code_desc, 'Unknown')               AS cntry_incrp_dcde_desc,
    NVL(quote.code_desc, 'Unknown')               AS cntry_quote_dcde_desc,
    NVL(curr.code_desc, 'Unknown')                AS denom_curr_dcde_desc,
    pmt.code_desc                                 AS pymt_freq_dcde_desc,
    NVL(st.code_desc, 'Unknown')                  AS st_incrp_dcde_desc,
    CASE
        WHEN ((ast.iss_type IN ('DPSTACK','DPSTCD','DPSTCHK','DPSTICK','DPSTMMD','DPSTSAV') AND ast.data_src_id = 5)
           OR (ast.iss_type IN ('LOANINL','LOANMOL') AND ast.data_src_id = 10))
        THEN 'N'
        ELSE 'Y'
    END                                           AS ast_short_long_desc_flg,
    REGEXP_REPLACE(ast.ast_long_desc, ' ', ' ')   AS ast_lng_description,
    ast.gics_econ_sectr_dcde                      AS gics_econ_sectr_dcde,
    mkt.code_desc                                 AS mkt_cap_curr_dcde_desc,
    lcl.code_desc                                 AS prc_curr_dcde_desc,
    eps.code_desc                                 AS eps_curr_dcde_desc,
    moody.code_desc                               AS moody_qual_dcde_desc,
    ex.code_desc                                  AS prim_trd_exch_dcde_desc,
    sp.code_desc                                  AS sp_qual_dcde_desc
FROM UAT_wpa_asset_db.core.npf_asset ast
JOIN INSTR_IDS I
    ON ast.INSTR_ID = I.INSTR_ID
LEFT JOIN UAT_WPA_REPORT_DB.core.wpa_code_desc_vw cd
    ON cd.code = ast.cntry_risk_dcde        AND cd.catg     = 'CNTRY'
LEFT JOIN UAT_WPA_REPORT_DB.core.wpa_code_desc_vw quote
    ON quote.code = ast.cntry_quote_dcde    AND quote.catg  = 'CNTRY'
LEFT JOIN UAT_WPA_REPORT_DB.core.wpa_code_desc_vw incrp
    ON incrp.code = ast.cntry_incrp_dcde    AND incrp.catg  = 'CNTRY'
LEFT JOIN UAT_WPA_REPORT_DB.core.wpa_code_desc_vw st
    ON st.code = ast.st_incrp_dcde          AND st.catg     = 'STATE'
LEFT JOIN UAT_WPA_REPORT_DB.core.wpa_code_desc_vw curr
    ON curr.code = ast.denom_curr_dcde      AND curr.catg   = 'CURR'
LEFT JOIN UAT_WPA_REPORT_DB.core.wpa_code_desc_vw mkt
    ON mkt.code = ast.mkt_cap_curr_dcde     AND mkt.catg    = 'CURR'
LEFT JOIN UAT_WPA_REPORT_DB.core.wpa_code_desc_vw lcl
    ON lcl.code = ast.prc_curr_dcde         AND lcl.catg    = 'CURR'
LEFT JOIN UAT_WPA_REPORT_DB.core.wpa_code_desc_vw eps
    ON eps.code = ast.eps_curr_dcde         AND eps.catg    = 'CURR'
LEFT JOIN UAT_WPA_REPORT_DB.core.wpa_code_desc_vw gise
    ON UPPER(TRIM(gise.code::VARCHAR)) = UPPER(TRIM(ast.gics_econ_sectr_dcde::VARCHAR))
   AND gise.catg = 'GICSECTR'
LEFT JOIN UAT_WPA_REPORT_DB.core.wpa_code_desc_vw giind
    ON giind.code = ast.gics_ind_grp_dcde   AND giind.catg  = 'GICSINDGRP'
LEFT JOIN UAT_WPA_REPORT_DB.core.wpa_code_desc_vw gicls
    ON UPPER(TRIM(gicls.code::VARCHAR)) = UPPER(TRIM(ast.gics_ind_class_dcde::VARCHAR))
   AND gicls.catg = 'GICSINDCLS'
LEFT JOIN UAT_WPA_REPORT_DB.core.wpa_code_desc_vw gicsub
    ON gicsub.code = ast.gics_sub_ind_dcde  AND gicsub.catg = 'GICSSUBIND'
LEFT JOIN UAT_WPA_REPORT_DB.core.wpa_code_desc_vw pmt
    ON pmt.code = ast.pymt_freq_dcde        AND pmt.catg    = 'PMTFREQ'
LEFT JOIN UAT_WPA_REPORT_DB.core.wpa_code_desc_vw moody
    ON moody.code = ast.moody_qual_dcde     AND moody.catg  = 'MOODY'
LEFT JOIN UAT_WPA_REPORT_DB.core.wpa_code_desc_vw ex
    ON ex.code = ast.prim_trd_exch_dcde     AND ex.catg     = 'EXCHANGE'
LEFT JOIN UAT_WPA_REPORT_DB.core.wpa_code_desc_vw sp
    ON sp.code = ast.sp_qual_dcde           AND sp.catg     = 'SP'
LEFT JOIN UAT_WPA_REPORT_DB.core.wpa_code_desc_vw region
    ON region.code = ast.cntry_risk_dcde    AND region.catg = 'REGION';



    create or replace dynamic table UAT_WPA_ASSET_DB.CORE.WPA_CUSTOM_SCHEMA_DYN(
	SCHEMA_ID,
	SORT_NBR,
	CUST_SK,
	INSTR_ID,
	CSTM_SUPCATG_CODE,
	CSTM_SUPCATG_DESC,
	CSTM_SUBCATG_CODE,
	CSTM_SUBCATG_DESC
) target_lag = '1 minute' refresh_mode = AUTO initialize = ON_SCHEDULE warehouse = UAT_WPA_DYNAMICTABLE_VWH
 as
SELECT schma.schema_id
			,cust_schma.sort_nbr
	                , cust_schma.cust_sk
	                , schma.instr_id
	                , schma.cstm_supcatg_code
	                , schma.cstm_supcatg_desc
	                , schma.cstm_subcatg_code
	                , schma.cstm_subcatg_desc
	            FROM UAT_WPA_ASSET_DB.CORE.NPF_CUST_CSTM_SCHEMA cust_schma
	            INNER JOIN UAT_WPA_ASSET_DB.CORE.NPF_CSTM_SCHEMA schma
	            ON cust_schma.schema_id = schma.schema_id
	            WHERE end_dt           IS NULL;