
WITH ED AS (
    SELECT DISTINCT MRN, BENE_ID, CLM_FROM_DT,  CLM_THRU_DT
    FROM (
        SELECT   MRN, BENE_ID,   
             CASE WHEN PREV_FROM_DT is null then CLM_FROM_DT
                  WHEN PREV_FROM_DT IS NOT NULL AND CLM_FROM_DT BETWEEN PREV_FROM_DT AND PREV_TO_DT + 1 THEN NULL
                  ELSE CLM_FROM_DT END CLM_FROM_DT,
             CASE WHEN PREV_FROM_DT IS NULL 
                      THEN CASE WHEN NXT_FROM_DT IS NULL THEN CLM_THRU_DT
                                ELSE CASE WHEN NXT_FROM_DT BETWEEN CLM_FROM_DT AND CLM_THRU_DT + 1 THEN GREATEST(NXT_TO_DT,CLM_THRU_DT) ELSE CLM_THRU_DT END
                                END
                      ELSE CASE WHEN CLM_FROM_DT BETWEEN PREV_FROM_DT AND PREV_TO_DT + 1 THEN NULL ELSE CLM_THRU_DT END
                      END CLM_THRU_DT  
        FROM (      
           select DISTINCT MRN, BENE_ID,  CLM_FROM_DT, CLM_THRU_DT,  
                   LEAD(CLM_FROM_DT,1)  OVER (PARTITION BY BENE_ID  ORDER BY  CLM_FROM_DT,CLM_THRU_DT) NXT_FROM_DT,
                   LAG(CLM_FROM_DT,1)  OVER (PARTITION BY BENE_ID  ORDER BY  CLM_FROM_DT,CLM_THRU_DT) PREV_FROM_DT,
                   LEAD(CLM_THRU_DT,1)  OVER (PARTITION BY BENE_ID  ORDER BY  CLM_FROM_DT,CLM_THRU_DT) NXT_TO_DT,
                   LAG(CLM_THRU_DT,1)  OVER (PARTITION BY BENE_ID  ORDER BY  CLM_FROM_DT,CLM_THRU_DT) PREV_TO_DT
             FROM (  
                    select distinct MRN, BENE_ID,  CLM_FROM_DT, MAX(CLM_THRU_DT) CLM_THRU_DT
                    from ( 
                            select   distinct MRN, BENE_ID, CAL_DT,CLM_FROM_DT, CLM_THRU_DT,
                                   LEAD(CLM_FROM_DT,1)  OVER (PARTITION BY BENE_ID  ORDER BY cal_dt, CLM_FROM_DT,CLM_THRU_DT) NXT_FROM_DT,
                                   LAG(CLM_FROM_DT,1)  OVER (PARTITION BY BENE_ID  ORDER BY cal_dt, CLM_FROM_DT,CLM_THRU_DT) PREV_FROM_DT,
                                   LEAD(CLM_THRU_DT,1)  OVER (PARTITION BY BENE_ID  ORDER BY cal_dt, CLM_FROM_DT,CLM_THRU_DT) NXT_TO_DT,
                                   LAG(CLM_THRU_DT,1)  OVER (PARTITION BY BENE_ID  ORDER BY cal_dt, CLM_FROM_DT,CLM_THRU_DT) PREV_TO_DT ,
                                   LEAD(CAL_DT,1) OVER (PARTITION BY BENE_ID ORDER BY CAL_DT) NXT_CAL_DT,
                                   LAG(CAL_DT,1) OVER (PARTITION BY BENE_ID ORDER BY CAL_DT) PREV_CAL_DT 
                            FROM      ( SELECT  MRN, BENE_ID,  MIN(CLM_FROM_DT) CLM_FROM_DT, CLM_THRU_DT  
                                             FROM    (
                                                SELECT  MRN, BENE_ID,  CLM_FROM_DT, MAX(CLM_THRU_DT)  CLM_THRU_DT  
                                                FROM    ( 
                                                        select  MRN,  p.BENE_ID,  CLM_FROM_DT,  CLM_THRU_DT 
                                                        from    aco_owner.MSSP_PT_B_PHYSICIAN@dblink_dwcsmgp p 
                                                                inner join DS_OWNER.temp_mssp_454@dblink_idxgcs6 g
                                                                on p.BENE_ID = g.BENE_ID
                                                        WHERE  CLM_POS_CD = '23'       
                                                        and CLM_FROM_DT between '01-JAN-2016' and '31-DEC-2016'  
                                                        and  DEATH_DT  - CLM_FROM_DT <= 30    
                                                        UNION
                                                        select  MRN, A.BENE_ID,    CLM_FROM_DT,   CLM_THRU_DT 
                                                        from ACO_OWNER.MSSP_PT_A_CLAIM_HEADER@dblink_dwcsmgp a 
                                                                 inner join DS_OWNER.temp_mssp_454@dblink_idxgcs6  g
                                                                on a.BENE_ID = g.BENE_ID
                                                        where  (CLM_OP_SRVC_TYPE_CD = '1' or CLM_ADMSN_TYPE_CD = '1')   
                                                        and CLM_FROM_DT between '01-JAN-2016' and '31-DEC-2016'  
                                                        and  DEATH_DT  - CLM_FROM_DT <= 30 
                                                        )    
                                                 GROUP BY  MRN, BENE_ID,  CLM_FROM_DT
                                                 )  
                                            GROUP BY  MRN, BENE_ID,  CLM_THRU_DT order by 1,3
                                           )    s1
                                right outer join ds_owner.dt_dim@dblink_idxgcs6 S2  
                                    on s2.cal_dt between s1. CLM_FROM_DT and  s1.CLM_THRU_DT
                            WHERE  CAL_DT BETWEEN '01-JAN-2016' and '31-DEC-2016' 
                            )  
                    where (  prev_cal_dt is null 
                              or  (nxt_cal_dt is null and clm_from_dt not between prev_from_dt and prev_to_dt)
                              or   clm_from_dt not between prev_from_dt and prev_to_dt    )
                    and bene_id is not null
                    GROUP BY  MRN, BENE_ID,   CLM_FROM_DT        
                    ) 
            )       
        )
    WHERE  CLM_THRU_DT is not null 
    GROUP BY MRN, BENE_ID, CLM_FROM_DT,  CLM_THRU_DT
) 
, ED_VISIT_DATEs AS (
SELECT  MRN, BENE_ID,  
    TO_DATE(SUBSTR(ER_VISIT_DTS, 1,10), 'MM/DD/YYYY') AS ED_VISIT_1,
    CASE WHEN INSTR(ER_VISIT_DTS, ' ') > 0 THEN TO_DATE(SUBSTR(ER_VISIT_DTS, INSTR(ER_VISIT_DTS, ' ')+1,10) , 'MM/DD/YYYY') ELSE null END AS ED_VISIT_2,
    CASE WHEN INSTR(ER_VISIT_DTS, ' ', INSTR(ER_VISIT_DTS, ' ')+1) > 0 THEN SUBSTR(ER_VISIT_dTS, INSTR(ER_VISIT_DTS, ' ', INSTR(ER_VISIT_DTS, ' ')+1))  ELSE NULL END AS ED_VISIT_3
FROM (
        SELECT MRN, BENE_ID, LISTAGG(to_char(CLM_FROM_DT,'MM/DD/YYYY'),' ') WITHIN GROUP (ORDER BY CLM_FROM_DT) as ER_VISIT_DTS
        FROM ED
        GROUP BY MRN, BENE_ID
        )  
)
, ICU_ADMITS AS (
    SELECT DISTINCT MRN, A.BENE_ID, a.CLM_FROM_DT ,a.CLM_THRU_DT  
    from ACO_OWNER.MSSP_PT_A_CLAIM_DETAIL@dblink_dwcsmgp a 
            inner join DS_OWNER.temp_mssp_454@dblink_idxgcs6 d  -- Apply BENE_DEMO up through MARCH '17 data file just as measure 454
                on a.BENE_ID = d.BENE_ID
    where  (PROD_REV_CTR_CD  like '020_' or PROD_REV_CTR_CD  like '021_')  -- ICU Admit
    and a.CLM_FROM_DT between '01-JAN-2016' and '31-DEC-2016'
    and  DEATH_DT  - a.CLM_FROM_DT <= 30
)
, ICU_ADMIT_DATES AS (
    SELECT MRN, BENE_ID, LISTAGG(to_char(CLM_FROM_DT,'mm/dd/yy'),', ') WITHIN GROUP (ORDER BY CLM_FROM_DT) as ICU_ADMIT_DTS
    FROM ICU_ADMITS
    GROUP BY MRN, BENE_ID
)
, ALL_ED_ICU_HOS_PAL AS (
    select DISTINCT 'ICU' as SVC_TYPE, MRN, BENE_ID, CLM_FROM_DT, CLM_THRU_DT  
    from ICU_ADMITS
    UNION 
    select DISTINCT 'ED' as SVC_TYPE, MRN, BENE_ID, CLM_FROM_DT, CLM_THRU_DT  
    from ED
    UNION
    select DISTINCT 'HOS' as SVC_TYPE, MRN, A.BENE_ID, CLM_FROM_DT,  CLM_FROM_DT 
    from ACO_OWNER.MSSP_PT_A_CLAIM_HEADER@dblink_dwcsmgp a 
         inner join DS_OWNER.temp_mssp_454@dblink_idxgcs6  g
            on a.BENE_ID = g.BENE_ID
    where  CLM_TYPE_CD = '50'  -- HOSPICE 
    and CLM_FROM_DT between '01-JAN-2016' and '31-DEC-2016'
    and  DEATH_DT  - CLM_FROM_DT <= 30
    UNION 
    select DISTINCT 'HOS' as SVC_TYPE, MRN, p.BENE_ID,CLM_FROM_DT, CLM_FROM_DT 
    from    aco_owner.MSSP_PT_B_PHYSICIAN@dblink_dwcsmgp p 
         inner join DS_OWNER.temp_mssp_454@dblink_idxgcs6 g
            on p.BENE_ID = g.BENE_ID
    WHERE  CLM_POS_CD = '34'  -- HOSPICE     
    and CLM_FROM_DT between '01-JAN-2016' and '31-DEC-2016'
    and  DEATH_DT  - CLM_FROM_DT <= 30        
    UNION -- No data if use CLM_POS_CD = '49'
    select DISTINCT 'HOS' as SVC_TYPE, MRN, p.BENE_ID,   CLM_FROM_DT, CLM_FROM_DT 
    from    aco_owner.MSSP_PT_B_PHYSICIAN@dblink_dwcsmgp p 
        inner join DS_OWNER.temp_mssp_454@dblink_idxgcs6 g
            on p.BENE_ID = g.BENE_ID
    WHERE  CLM_LINE_HCPCS_CD in ('99497','99498')  -- PALLIATIVE CARE     
    and CLM_FROM_DT between '01-JAN-2016' and '31-DEC-2016'
    and  DEATH_DT  - CLM_FROM_DT <= 30                    
) 
, ED_ICU_HOS_PAL as (
    SELECT  MRN,  BENE_ID,
            Chronol_Order,
            HOS_pos,  HOS_DT_pos, HOS2_pos, HOS2_DT_pos,
            ED_pos,  ED_DT_pos, ED2_pos,  ED2_DT_pos,    
            ICU_pos, ICU_DT_pos,   ICU_DT2_pos, ICU2_pos, ICU2_DT_pos,  ICU2_DT2_pos,
            CASE WHEN HOS_DT_pos > 0 then substr(Chronol_Order, HOS_DT_pos,6) ELSE NULL END HOS_DT,                    
            CASE WHEN HOS2_DT_pos > 0 then substr(Chronol_Order, HOS2_DT_pos,6)  ELSE NULL END  HOS2_DT,  
            CASE WHEN ED_DT_pos > 0 then substr(Chronol_Order, ED_DT_pos,6)  ELSE NULL END  ED_DT,                     
            CASE WHEN ED2_DT_pos > 0 then substr(Chronol_Order, ED2_DT_pos,6) ELSE NULL END   ED2_DT,  
            CASE WHEN ICU_DT_pos > 0 then substr(Chronol_Order, ICU_DT_pos,6)  ELSE NULL END  ICU_DT,   
            CASE WHEN ICU_DT2_pos > 0 then  substr(Chronol_Order, ICU_DT2_pos,6) ELSE NULL END   ICU_DT2,
            CASE WHEN ICU2_DT_pos > 0 then substr(Chronol_Order, ICU2_DT_pos,6) ELSE NULL END   ICU2_DT, 
            CASE WHEN ICU2_DT2_pos > 0 then substr(Chronol_Order, ICU2_DT2_pos,6) ELSE NULL END   ICU2_DT2
    FROM (
        Select MRN,  BENE_ID, 
                Chronol_Order,
               instr(Chronol_Order, 'HOS') as HOS_pos,  
               CASE WHEN instr(Chronol_Order, 'HOS') > 0 THEN  instr(Chronol_Order, 'HOS(')+4 ELSE 0 END as HOS_DT_pos,
               instr(Chronol_Order, 'HOS', instr(Chronol_Order,'HOS')+4) as HOS2_pos,  
               CASE WHEN instr(Chronol_Order, 'HOS', instr(Chronol_Order,'HOS')+4) > 0 THEN  instr( Chronol_Order,'HOS(', instr(Chronol_Order, 'HOS')+4)+4  ELSE 0 END HOS2_DT_pos,

               instr(Chronol_Order, 'ED') as ED_pos,  
               CASE WHEN instr(Chronol_Order, 'ED') > 0   THEN  instr(Chronol_Order, 'ED(')+3  ELSE 0 END as ED_DT_pos,
               instr(Chronol_Order, 'ED', instr(Chronol_Order,'ED')+3) as ED2_pos,  
               CASE WHEN instr(Chronol_Order, 'ED', instr(Chronol_Order,'ED')+3) > 0 THEN  instr( Chronol_Order,'ED(', instr(Chronol_Order, 'ED')+3)+3  ELSE 0 END ED2_DT_pos,

               instr(Chronol_Order, 'ICU') as ICU_pos, 
               CASE WHEN instr(Chronol_Order, 'ICU') > 0 THEN  instr(Chronol_Order, 'ICU(')+4 ELSE 0 END as ICU_DT_pos,  
               CASE WHEN instr(Chronol_Order, 'ICU') > 0 THEN  instr(Chronol_Order, 'ICU(')+11 ELSE 0 END as ICU_DT2_pos,
               instr(Chronol_Order, 'ICU', instr(Chronol_Order,'ICU')+4) as ICU2_pos,  
               CASE WHEN instr(Chronol_Order, 'ICU', instr(Chronol_Order,'ICU')+4) > 0 THEN  instr( Chronol_Order,'ICU(', instr(Chronol_Order, 'ICU')+4)+4  ELSE 0 END ICU2_DT_pos,
               CASE WHEN instr(Chronol_Order, 'ICU', instr(Chronol_Order,'ICU')+4) > 0 THEN  instr( Chronol_Order,'ICU(', instr(Chronol_Order, 'ICU')+4)+11  ELSE 0 END ICU2_DT2_pos
        from (    --s2    
            select  MRN,  BENE_ID,  
                  LISTAGG(SVC_TYPE || '('||  case when svc_type in('ED', 'ICU' ) then TO_CHAR(CLM_FROM_DT,'YYMMDD') || '-' || TO_CHAR(CLM_THRU_DT,'YYMMDD') 
                                                  ELSE TO_CHAR(CLM_FROM_DT,'YYMMDD') END || ')' , '; ' ) 
                          WITHIN GROUP (ORDER BY CLM_FROM_DT, CLM_THRU_DT)  Chronol_Order 
            from ALL_ED_ICU_HOS_PAL 
           GROUP BY MRN,  BENE_ID  
            )    --s2      
        )  
)        
, FLAGS AS (
    select  MRN, BENE_ID, 
        CASE WHEN ICU_pos > 0 THEN 1 ELSE 0 END ICU_MET_MEASURE,
         CASE WHEN HOS_pos = 0 THEN 0 
                 ELSE  CASE WHEN ( HOS_pos < ICU_pos )   OR (HOS_pos < ICU2_pos )  
                                   THEN 1 ELSE 0 END END  as HOS_BF_ICU_OR_DEATH,                             
        CASE WHEN HOS_DT is null THEN 0
                 WHEN  HOS_pos > 0 and ICU_pos > 0  and (HOS_DT between  nvl(ICU_DT,'888888') and nvl(ICU_DT2,'888888')) THEN 1
                 WHEN  HOS_pos > 0 and ICU_pos > 0 and HOS_pos > ICU_pos then 1
                 WHEN  HOS_pos > 0 and ICU2_pos > 0 and HOS_pos > ICU2_pos then 1
                 WHEN HOS2_DT is null THEN 0
                 WHEN HOS2_pos > 0 and ICU_pos > 0 and (HOS2_DT BETWEEN   nvl(ICU2_DT,'888888') and nvl(ICU2_DT2,'888888')) THEN 1
                 WHEN  HOS2_pos > 0 and ICU_pos > 0 and HOS2_pos > ICU_pos then 1
                 WHEN  HOS2_pos > 0 and ICU2_pos > 0 and HOS2_pos > ICU2_pos then 1
                 ELSE 0 
       END as HOS_DURING_ICU_OR_AFTER_ICU,

       CASE WHEN ED2_pos > 0 THEN 1 ELSE 0 END ED_MET_MEASURE,
        CASE WHEN HOS_pos = 0 THEN 0 
                 WHEN ED2_pos > 0 AND (HOS_pos  BETWEEN ED_pos and ED2_pos OR  HOS2_pos BETWEEN ED_pos and ED2_pos)  THEN 1
                 WHEN ED2_pos = 0 AND ED_pos > 0 AND HOS_pos < ED_pos THEN 1
                 ELSE 0
       END  as HOS_BF_2nd_ED_OR_1st_ED,
                        
        CASE WHEN HOS_POS = 0 THEN 0
                 WHEN ED2_pos > 0 AND (HOS_pos > ED2_pos OR HOS2_pos > ED2_pos) THEN 1 
                 ELSE 0 END as HOS_AF_2nd_ED,
                 
        Chronol_Order               
FROM   ED_ICU_HOS_PAL a
)           
, HEMA_ONC_NPI_ICU AS (
    SELECT MRN,BENE_ID,  RNDRG_PROV_NPI_NUM,  
           RANK() OVER (PARTITION BY  MRN ORDER BY LATEST_ENCOUNTER_DT DESC,ENCOUNTERS_CNT DESC)  RANK_MOST_RECENT_ENC,
           RANK() OVER (PARTITION BY  MRN ORDER BY ENCOUNTERS_CNT DESC, LATEST_ENCOUNTER_DT DESC) RANK_MOST_ENC
    FROM (
        SELECT G.BENE_ID, MRN, RNDRG_PROV_NPI_NUM, MAX(CLM_FROM_DT) LATEST_ENCOUNTER_DT,  count(distinct CLM_FROM_DT) Encounters_Cnt  
        FROM   ACO_OWNER.MSSP_PT_B_PHYSICIAN@DBLINK_DWCSMGP P
          inner JOIN DS_OWNER.TEMP_MSSP_455_ICU_Metric@DBLINK_IDXGCS6 G
             ON P.BENE_ID = G.BENE_ID
        WHERE CLM_PROV_SPCLTY_CD IN ('82','83','90')  
        and  p.CLM_LINE_HCPCS_CD    like '99___'       
        and  CLM_FROM_DT < nvl(ICU_DT1, '01-DEC-4000')
        GROUP BY G.BENE_ID, MRN, RNDRG_PROV_NPI_NUM 
    )
)
, HEMA_ONC_NPI_ED AS (
    SELECT MRN,BENE_ID,  RNDRG_PROV_NPI_NUM,  
           RANK() OVER (PARTITION BY  MRN ORDER BY LATEST_ENCOUNTER_DT DESC,ENCOUNTERS_CNT DESC)  RANK_MOST_RECENT_ENC,
           RANK() OVER (PARTITION BY  MRN ORDER BY ENCOUNTERS_CNT DESC, LATEST_ENCOUNTER_DT DESC) RANK_MOST_ENC
    FROM (
        SELECT G.BENE_ID, MRN, RNDRG_PROV_NPI_NUM, MAX(CLM_FROM_DT) LATEST_ENCOUNTER_DT,  count(distinct CLM_FROM_DT) Encounters_Cnt  
        FROM   ACO_OWNER.MSSP_PT_B_PHYSICIAN@DBLINK_DWCSMGP P
          inner JOIN DS_OWNER.TEMP_MSSP_455_ED_Metric@DBLINK_IDXGCS6 G
             ON P.BENE_ID = G.BENE_ID
        WHERE CLM_PROV_SPCLTY_CD IN ('82','83','90')  
        and  p.CLM_LINE_HCPCS_CD   like '99___' 
        and  CLM_FROM_DT < nvl(ED_DT2, nvl(ED_DT1,'01-DEC-4000'))
        GROUP BY G.BENE_ID, MRN, RNDRG_PROV_NPI_NUM 
    )
)
, HEMA_ONC_NM_ICU AS (
    SELECT E1.MRN, E1.BENE_ID, OCN_MOST_ENC_BF_ICU, ONC_MOST_RECENT_ENC_BF_ICU 
    FROM (
            SELECT MRN, BENE_ID, TRIM(PR_FIRST_NM) || ' ' || TRIM(PR_LAST_NM) AS OCN_MOST_ENC_BF_ICU  
            FROM   HEMA_ONC_NPI_ICU A INNER JOIN  APPL_CLIENT.NPI_DATA B
                ON A.RNDRG_PROV_NPI_NUM = B.NPI
            WHERE  RANK_MOST_ENC = 1
           ) E1 
      INNER JOIN ( 
            SELECT MRN, BENE_ID, TRIM(PR_FIRST_NM) || ' ' || TRIM(PR_LAST_NM) AS ONC_MOST_RECENT_ENC_BF_ICU          
            FROM   HEMA_ONC_NPI_ICU C INNER JOIN  APPL_CLIENT.NPI_DATA D
                ON C.RNDRG_PROV_NPI_NUM = D.NPI        
            WHERE RANK_MOST_RECENT_ENC = 1     
           ) E2   
     ON E1.BENE_ID = E2.BENE_ID
)           
, HEMA_ONC_NM_ED AS (
   SELECT E3.MRN, E3.BENE_ID, ONC_MOST_ENC_BF_2nd_ED, ONC_MOST_RECENT_ENC_BF_2nd_ED 
    FROM (
            SELECT MRN, BENE_ID, TRIM(PR_FIRST_NM) || ' ' || TRIM(PR_LAST_NM) AS ONC_MOST_ENC_BF_2nd_ED 
            FROM   HEMA_ONC_NPI_ED A INNER JOIN  APPL_CLIENT.NPI_DATA B
                ON A.RNDRG_PROV_NPI_NUM = B.NPI
            WHERE  RANK_MOST_ENC = 1
           ) E3 
      INNER JOIN ( 
            SELECT MRN, BENE_ID, TRIM(PR_FIRST_NM) || ' ' || TRIM(PR_LAST_NM) AS ONC_MOST_RECENT_ENC_BF_2nd_ED          
            FROM   HEMA_ONC_NPI_ED C INNER JOIN  APPL_CLIENT.NPI_DATA D
                ON C.RNDRG_PROV_NPI_NUM = D.NPI        
            WHERE RANK_MOST_RECENT_ENC = 1     
           ) E4  
     ON E3.BENE_ID = E4.BENE_ID     
)
, SURG_ONC_NPI AS ( 
    SELECT MRN, BENE_ID, RNDRG_PROV_NPI_NUM,   
           RANK() OVER (PARTITION BY  MRN ORDER BY LATEST_ENCOUNTER_DT DESC,ENCOUNTERS_CNT DESC) RANK_MOST_RECENT_ENC
    FROM (
        SELECT G.BENE_ID, MRN, RNDRG_PROV_NPI_NUM, MAX(CLM_FROM_DT) LATEST_ENCOUNTER_DT,  count(distinct CLM_FROM_DT) Encounters_Cnt  
        FROM   ACO_OWNER.MSSP_PT_B_PHYSICIAN@DBLINK_DWCSMGP P
          inner JOIN DS_OWNER.TEMP_MSSP_454@DBLINK_IDXGCS6 G
             ON P.BENE_ID = G.BENE_ID
        WHERE CLM_PROV_SPCLTY_CD = '91'
        GROUP BY G.BENE_ID, MRN, RNDRG_PROV_NPI_NUM
        ) 
)
, SURG_ONC_NM AS (
    SELECT MRN, BENE_ID,  PR_FIRST_NM || ' ' || PR_LAST_NM as SURG_ONCOLOGIST  
    FROM SURG_ONC_NPI so1
       INNER JOIN APPL_CLIENT.NPI_DATA so2
          on so1.RNDRG_PROV_NPI_NUM = so2.NPI
   WHERE RANK_MOST_RECENT_ENC = 1
)
SELECT s1.MRN, s1.BENE_ID,HIC_NUM, DOB,  FIRST_NM,  MI,  LAST_NM, DEATH_DT ,
        ICU_ADMIT_DTS AS ICU_ADMISSION_DATE,
        NVL(ICU_MET_MEASURE,0)  ICU_MET_MEASURE ,
        NVL(HOS_BF_ICU_OR_DEATH,0) HOS_BF_ICU_OR_DEATH,
        NVL(HOS_DURING_ICU_OR_AFTER_ICU,0) HOS_DURING_ICU_OR_AFTER_ICU ,
        OCN_MOST_ENC_BF_ICU, ONC_MOST_RECENT_ENC_BF_ICU,
            
        ED_VISIT_1, ED_VISIT_2, ED_VISIT_3,
        NVL(ED_MET_MEASURE,0) ED_MET_MEASURE ,
        NVL(HOS_BF_2nd_ED_OR_1st_ED,0) HOS_BF_2nd_ED_OR_1st_ED,
        NVL(HOS_AF_2nd_ED,0) HOS_AF_2nd_ED,
        ONC_MOST_ENC_BF_2nd_ED, ONC_MOST_RECENT_ENC_BF_2nd_ED, 
        SURG_ONCOLOGIST,
        Chronol_Order
FROM   DS_OWNER.temp_mssp_454@dblink_idxgcs6 s1
    LEFT OUTER JOIN   HEMA_ONC_NM_ICU S2
        ON S1.BENE_ID = S2.BENE_ID
    LEFT OUTER JOIN   HEMA_ONC_NM_ED S3
        ON S1.BENE_ID = S3.BENE_ID
    LEFT OUTER JOIN    SURG_ONC_NM S4
        ON S1.BENE_ID = S4.BENE_ID       
    LEFT OUTER JOIN FLAGS s6
        ON s1.BENE_ID = s6.BENE_ID     
    LEFT OUTER JOIN ICU_ADMIT_DATEs S7
        ON S1.BENE_ID = S7.BENE_ID          
    LEFT OUTER JOIN ED_VISIT_DATEs S7
        ON S1.BENE_ID = S7.BENE_ID          
order by MRN
 