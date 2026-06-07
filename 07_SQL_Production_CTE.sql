/*******************************************************************************
  FORENSIC DATA AUDIT — PRODUCTION CTE
  LEAD ANALYST: Robert Hoye-Logan
  VERSION: 1.6
  PROJECT: Patient No-Show Analysis (Google Capstone)
  GOAL: Quantify fiscal leakage driven by patient no-show behavior across 
all operational dimensions. Confirmed total fiscal leak: $4,453,920 
($4,144,560 Out-of-Pocket + $309,360 Medicaid) based on Scholarship 
segmentation and 2026 Washington State reimbursement benchmarks.

  PURPOSE: This is the employer-facing production architecture — a single
  coherent CTE chain that mirrors all eight analytical dimensions from the
  Master Logic Trail. Each audit dimension is independently queryable via
  the commented SELECT blocks at the end of this file.
  For the step-by-step forensic workbench, see 06_SQL_Master_StepByStep.sql.

  CTE MAP (mirrors 06_SQL_Master_StepByStep.sql):
    PRE-STEP : Data Integrity Verification (Duplicate Check)
    CTE 1    : base_appointments        → Step 1  (data clean + lead_time engineering)
    CTE 2    : appointment_segmentation → Steps 2–4 (segmentation: trust wall, acuity,
                                                     advocacy type, disability status)
    CTE 3    : trust_wall_audit         → Step 5  (Trust Wall threshold classification)
    CTE 4    : sms_ghost_audit          → Step 6  (Digital Ghost / SMS failure analysis)
    CTE 5    : accessibility_audit      → Step 7  (Accessibility Pressure Test)
    CTE 6    : guardian_advocacy_audit  → Step 8  (Guardian-Advocacy Pivot / Pediatric Penalty)
    CTE 7    : revenue_leak_summary     → Final aggregation (fiscal impact + share layer)

  SUPPLEMENTAL QUERIES (appointments_enriched_v2):
    SUPP 4A  : triple_threat_lead_time  → Step 4A (Condition Combination Lead Time Analysis)
    SUPP 6A  : sms_rate_comparison      → Step 6A (SMS No-Show Rate Comparison)

  NOTE: Column 'Handcap' retains dataset-origin spelling throughout all queries
        to maintain query integrity. Correct spelling 'Handicap' is used in all
        narrative documentation. See 04_Data_Dictionary for full explanation.
*******************************************************************************/


-- PRE-STEP: DATA INTEGRITY VERIFICATION (Duplicate Check)
-- Goal: Confirm zero duplicate appointment records before analysis begins.
SELECT
    COUNT(*) AS total_records,
    COUNT(DISTINCT AppointmentID) AS distinct_appointments
FROM `healthcare_operations.appointments_raw`;
-- Result: 110,527 = 110,527 — zero duplicates confirmed. ✅


-- PRODUCTION CTE (Steps 1–8)
WITH

-- CTE 1: BASE APPOINTMENTS — Data Standardization & Lead Time Engineering
-- Mirrors: STEP 1 — THE FISCAL BASELINE (Volume & Velocity)
-- Calculates lead_time once here so it is never re-computed downstream.
-- Excludes: negative lead times (data artifact) and null PatientIDs (1 record).
-- Final working dataset: 110,521 records.
base_appointments AS (
    SELECT
        AppointmentID,
        PatientId,
        Gender,
        Age,
        Scholarship,
        Hipertension,
        Diabetes,
        Alcoholism,
        Handcap,
        SMS_received,
        `No-show`                                                          AS no_show_status,
        CAST(ScheduledDay AS DATE)                                         AS scheduled_date,
        CAST(AppointmentDay AS DATE)                                       AS appointment_date,
        DATE_DIFF(
            CAST(AppointmentDay AS DATE),
            CAST(ScheduledDay AS DATE),
            DAY
        )                                                                  AS lead_time
    FROM `healthcare_operations.appointments_raw`
    WHERE
        DATE_DIFF(
            CAST(AppointmentDay AS DATE),
            CAST(ScheduledDay AS DATE),
            DAY
        ) >= 0
        AND PatientId IS NOT NULL
),

-- CTE 2: APPOINTMENT SEGMENTATION — Behavioral & Clinical Labeling
-- Mirrors: STEP 2 — THE SELF-ADVOCACY PIVOT (Gender & Churn Velocity)
--          STEP 3 — THE ACUITY PRESSURE TEST (Chronic Conditions)
--          STEP 4 — CO-MORBIDITY DEEP DIVE (Triple Threat Volume)
-- Derives all segmentation labels once here for use across all downstream CTEs.
-- Note: lead_time >= 10 reflects the actual behavioral inflection point
--       identified in Step 5A of the Master Logic Trail.
appointment_segmentation AS (
    SELECT
        *,
        CASE
            WHEN lead_time >= 10 THEN 'Beyond Trust Wall'
            ELSE 'Operational Safe Zone'
        END AS trust_wall_status,
        CASE
            WHEN Hipertension = 1 AND Diabetes = 1 AND Alcoholism = 1 THEN 'Triple Threat'
            WHEN Hipertension = 1 AND Diabetes = 1                     THEN 'High-Acuity'
            ELSE                                                             'Baseline'
        END AS acuity_tier,
        CASE
            WHEN Age < 18 THEN 'Guardian-Advocate (Minor)'
            ELSE               'Self-Advocate (Adult)'
        END AS advocacy_type,
        CASE
            WHEN Handcap > 0 THEN 1
            ELSE                  0
        END AS is_disabled
    FROM base_appointments
),

-- CTE 3: TRUST WALL AUDIT — Step 5
-- Mirrors: STEP 5 — THE TRUST WALL STRESS TEST (Operational Ceiling)
-- Goal: Explicitly count patients sitting beyond the 10-day threshold
--       by scholarship status.
trust_wall_audit AS (
    SELECT
        Scholarship,
        trust_wall_status,
        no_show_status,
        COUNT(*)                 AS total_patient_volume,
        ROUND(AVG(lead_time), 1) AS avg_lead_time
    FROM appointment_segmentation
    GROUP BY 1, 2, 3
),

-- CTE 4: SMS GHOST AUDIT — Step 6
-- Mirrors: STEP 6 — THE DIGITAL GHOST AUDIT (SMS Failure Analysis)
-- Goal: Expose the SMS failure across trust wall zones.
-- Finding: SMS recipients no-showed at 27.6% vs. 16.7% for non-recipients,
-- confirming SMS alone is not a reliable retention lever beyond the Trust Wall.
-- Average lead time for SMS recipients with no-show: 20.0 days.
-- Note: Revenue fiscal leak is based on Scholarship segmentation — see CTE 7.
sms_ghost_audit AS (
    SELECT
        SMS_received,
        trust_wall_status,
        no_show_status,
        COUNT(*)                 AS total_patient_volume,
        ROUND(AVG(lead_time), 1) AS avg_lead_time
    FROM appointment_segmentation
    GROUP BY 1, 2, 3
),

-- CTE 5: ACCESSIBILITY AUDIT — Step 7
-- Mirrors: STEP 7 — THE ACCESSIBILITY PRESSURE TEST (Handicap Volume)
-- Goal: Determine if disability status compresses the Trust Wall threshold.
-- Finding: Disabled patients no-show at avg 13.0 days vs 15.9 days baseline
-- (~3 days earlier). Reinforces the self-advocacy churn theory.
-- Note: ~2% of total volume. Supplementary finding, not a primary Trust Wall driver.
accessibility_audit AS (
    SELECT
        is_disabled,
        trust_wall_status,
        no_show_status,
        COUNT(*)                 AS total_patient_volume,
        ROUND(AVG(lead_time), 1) AS avg_lead_time
    FROM appointment_segmentation
    GROUP BY 1, 2, 3
),

-- CTE 6: GUARDIAN-ADVOCACY AUDIT — Step 8
-- Mirrors: STEP 8 — THE GUARDIAN-ADVOCACY PIVOT (Pediatric Penalty Audit)
-- Goal: Identify the trust-erosion gap between parents and self-advocating adults.
-- Finding: Guardian-Advocate (Minor) no-show rate 21.9% vs Self-Advocate (Adult) 19.63%.
-- Result: A 2.27% variance (11.5% higher failure rate) for families confirms
--         that advocacy type is a primary driver of service failure.
guardian_advocacy_audit AS (
    SELECT
        advocacy_type,
        trust_wall_status,
        no_show_status,
        COUNT(*)                 AS total_patient_volume,
        ROUND(AVG(lead_time), 1) AS avg_lead_time
    FROM appointment_segmentation
    GROUP BY 1, 2, 3
),

-- CTE 7: REVENUE LEAK SUMMARY — Fiscal Impact & Share Layer
-- Combines all segmentation dimensions into a single executive-ready output.
-- modeled_revenue_impact: fiscal exposure per segment.
--   $120 = Medicaid/Scholarship benchmark (Washington State 2026)
--   $210 = Commercial/Out-of-Pocket benchmark (Washington State 2026)
-- pct_of_total_volume: each segment's share of total patient volume.
revenue_leak_summary AS (
    SELECT
        Scholarship,
        Gender,
        trust_wall_status,
        acuity_tier,
        SMS_received,
        no_show_status,
        COUNT(*)                 AS total_patient_volume,
        ROUND(AVG(lead_time), 1) AS avg_lead_time,
        CASE
            WHEN Scholarship = 1 THEN COUNT(*) * 120
            ELSE                      COUNT(*) * 210
        END                      AS modeled_revenue_impact,
        ROUND(
            100.0 * COUNT(*) / SUM(COUNT(*)) OVER(),
            2
        )                        AS pct_of_total_volume
    FROM appointment_segmentation
    GROUP BY 1, 2, 3, 4, 5, 6
)


-- FINAL OUTPUT — Uncomment one block to run that audit dimension.
-- Each CTE is independently queryable. Revenue Leak Summary is active by default
-- as the executive dashboard feed for Tableau visualization.

-- Trust Wall Audit (Step 5):
-- SELECT * FROM trust_wall_audit ORDER BY Scholarship, trust_wall_status, no_show_status;

-- SMS Ghost Audit (Step 6):
-- SELECT * FROM sms_ghost_audit ORDER BY SMS_received, trust_wall_status, no_show_status;

-- Accessibility Audit (Step 7):
-- SELECT * FROM accessibility_audit ORDER BY is_disabled, trust_wall_status, no_show_status;

-- Guardian-Advocacy Audit (Step 8):
-- SELECT * FROM guardian_advocacy_audit ORDER BY advocacy_type, trust_wall_status, no_show_status;

-- Revenue Leak Summary (Executive Dashboard Feed — default active):
SELECT
    Scholarship,
    Gender,
    trust_wall_status,
    acuity_tier,
    SMS_received,
    no_show_status,
    total_patient_volume,
    avg_lead_time,
    modeled_revenue_impact,
    pct_of_total_volume
FROM revenue_leak_summary
ORDER BY
    Scholarship DESC,
    trust_wall_status,
    acuity_tier,
    no_show_status;


/*******************************************************************************
  SUPPLEMENTAL QUERIES — ENRICHED DATASET ANALYSIS
  Note: The following queries run against appointments_enriched_v2 rather than
  appointments_raw. Results are validated against and complement the main CTE
  chain above.
*******************************************************************************/


-- SUPP 4A: TRIPLE THREAT LEAD TIME BY CONDITION COMBINATION
-- Mirrors: STEP 4A of 06_SQL_Master_StepByStep.sql
-- Goal: Validate whether clinical complexity compresses the Trust Wall threshold.
-- Finding: Triple Threat patients (all three conditions) hit the Trust Wall sooner,
-- averaging 12.2 days vs. 16.1 days for patients with no conditions.
SELECT
    has_diabetes,
    has_hypertension,
    has_alcoholism,
    ROUND(AVG(lead_time), 1) AS avg_lead_time_no_show,
    COUNT(*) AS total_no_shows
FROM `no-show-strategy.healthcare_operations.appointments_enriched_v2`
WHERE missed_appointment = 1
GROUP BY 1, 2, 3
ORDER BY 1, 2, 3;
-- Result: Triple Threat patients average 12.2 days vs. 16.1 days baseline. ✅


-- SUPP 6A: SMS NO-SHOW RATE COMPARISON
-- Mirrors: STEP 6A of 06_SQL_Master_StepByStep.sql
-- Goal: Compare no-show rates between SMS recipients and non-recipients.
-- Finding: SMS recipients no-showed at a higher rate — 27.6% vs. 16.7% for
-- non-recipients, confirming SMS alone is not a reliable retention tool.
SELECT
    sms_received,
    ROUND(AVG(CASE WHEN missed_appointment = 1 THEN 1.0 ELSE 0 END) * 100, 1) AS no_show_rate,
    COUNT(*) AS total_appointments
FROM `no-show-strategy.healthcare_operations.appointments_enriched_v2`
GROUP BY 1
ORDER BY 1;
-- Result: SMS received = 27.6% no-show rate vs. 16.7% without SMS. ✅