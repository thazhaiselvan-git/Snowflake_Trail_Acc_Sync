PACKAGE BODY         NPF_CUST_SCHEMA_RULE_EVALUATION_PKG
AS
    PROCEDURE RULE_EVALUATION(
        p_cstm_ast_schema_id      IN  NUMBER,
        p_ast_sup_catg_desc       IN  VARCHAR2,
        p_ast_sub_catg_desc       IN  VARCHAR2,
        p_cntry_of_risk_desc      IN  VARCHAR2,
        p_cstm_ast_sup_catg_desc  OUT VARCHAR2,
        p_cstm_ast_sub_catg_desc  OUT VARCHAR2,
        p_cstm_cntry_of_risk_desc OUT VARCHAR2
    )
    AS
        v_res VARCHAR2(100);
        v_rule_cnt NUMBER := 0;
        v_cstm_ast_sup_catg_desc_1 VARCHAR2(254);
        v_cstm_ast_sup_catg_desc_2 VARCHAR2(254);
        v_cstm_ast_sub_catg_desc_1 VARCHAR2(254);
        v_cstm_ast_sub_catg_desc_2 VARCHAR2(254);

BEGIN
FOR rule IN (
            SELECT *
            FROM npfdbo.npf_cstm_rule_mstr
            WHERE schema_id = p_cstm_ast_schema_id
             -- AND (rule_stat = 'A' OR (rule_stat = 'I' AND rule_del_opt = 'CUSTOM'))
              AND rule_stat = 'A'
            ORDER BY rule_sk
        )
        LOOP
            DECLARE
has_OR    BOOLEAN := FALSE;
                v_cnt     NUMBER := 0;
                v_cond_cnt NUMBER := 0;

BEGIN
FOR cond IN (
                    SELECT c.*, COUNT(1) OVER(PARTITION BY rule_sk ORDER BY rule_sk) cnt
                    FROM npfdbo.npf_cstm_rule_cond c
                    WHERE rule_sk = rule.rule_sk
                    ORDER BY cond_order
                )
                LOOP
                    IF (cond.RULE_FLD_NAME = 'CSTM_SUPCATG_DESC') THEN
                        IF (cond.RULE_OPER = 'EQUAL' AND p_ast_sup_catg_desc = cond.RULE_FLD_VALUE)
                            OR (cond.RULE_OPER = 'NOTEQUAL' AND p_ast_sup_catg_desc != cond.RULE_FLD_VALUE) THEN
                            v_cnt := v_cnt + 1;
END IF;
                    ELSIF (cond.RULE_FLD_NAME = 'CSTM_SUBCATG_DESC') THEN
                        IF (cond.RULE_OPER = 'EQUAL' AND p_ast_sub_catg_desc = cond.RULE_FLD_VALUE)
                            OR (cond.RULE_OPER = 'NOTEQUAL' AND p_ast_sub_catg_desc != cond.RULE_FLD_VALUE) THEN
                            v_cnt := v_cnt + 1;
END IF;
                    ELSIF (cond.RULE_FLD_NAME = 'CSTM_CNTRY_RISK_DESC') THEN
                        IF (cond.RULE_OPER = 'EQUAL' AND p_cntry_of_risk_desc = cond.RULE_FLD_VALUE)
                            OR (cond.RULE_OPER = 'NOTEQUAL' AND p_cntry_of_risk_desc != cond.RULE_FLD_VALUE) THEN
                            v_cnt := v_cnt + 1;
END IF;
END IF;

                    IF cond.LOGICAL_OPER = 'OR' THEN
                        has_OR := TRUE;
END IF;

                    v_cond_cnt := cond.cnt;
END LOOP;
                IF ((has_OR AND v_cnt > 0)) OR ((NOT has_OR AND v_cnt = v_cond_cnt)) THEN

                    IF (v_rule_cnt = 0) THEN

                    v_cstm_ast_sup_catg_desc_1 := rule.RULE_CSTM_SUPCATG_DESC;
                    v_cstm_ast_sub_catg_desc_1 := rule.RULE_CSTM_SUBCATG_DESC;

ELSE

                    v_cstm_ast_sup_catg_desc_2 := rule.RULE_CSTM_SUPCATG_DESC;
                    v_cstm_ast_sub_catg_desc_2 := rule.RULE_CSTM_SUBCATG_DESC;

END IF;

                    v_rule_cnt := v_rule_cnt + 1;
                    p_cstm_cntry_of_risk_desc := p_cntry_of_risk_desc;
ELSE
                    p_cstm_ast_sup_catg_desc := p_ast_sup_catg_desc;
                    p_cstm_ast_sub_catg_desc := p_ast_sub_catg_desc;
                    p_cstm_cntry_of_risk_desc := p_cntry_of_risk_desc;
END IF;


EXCEPTION
                WHEN NO_DATA_FOUND THEN
                NULL;
END;

END LOOP;

                p_cstm_ast_sup_catg_desc := COALESCE(v_cstm_ast_sup_catg_desc_2, v_cstm_ast_sup_catg_desc_1, p_ast_sup_catg_desc);
                p_cstm_ast_sub_catg_desc := COALESCE(v_cstm_ast_sub_catg_desc_2, v_cstm_ast_sub_catg_desc_1, p_ast_sub_catg_desc);

END RULE_EVALUATION;
END NPF_CUST_SCHEMA_RULE_EVALUATION_PKG;
