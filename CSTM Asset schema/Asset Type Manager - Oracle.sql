
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