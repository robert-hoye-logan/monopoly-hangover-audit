/*******************************************************************************
  FORENSIC DATA AUDIT (MASTER LOGIC TRAIL)
  LEAD ANALYST: Robert Hoye-Logan
  VERSION: 2.2
  PROJECT: Patient No-Show Analysis — Healthcare Operations Forensic Audit
  GOAL: Identify the internal operational rot driving revenue leaks.
  THEORY: The "Trust Wall" threshold is hit at 10 days — the point where retention fails across all patient segments.

  PURPOSE: This is the forensic workbench — standalone queries executed
  sequentially in BigQuery to audit each analytical dimension individually.
  Each step is self-contained and independently reproducible.
  For the production CTE architecture, see 07_SQL_Production_CTE.sql.

  STEP MAP:
    PRE-STEP : Data Integrity Verification (Duplicate Check)
    STEP 1   : The Fiscal Baseline         (Volume & Velocity)
    STEP 2   : The Self-Advocacy Pivot     (Gender & Churn Velocity)
    STEP 3   : The Acuity Pressure Test    (Chronic Volume)
    STEP 4A  : Triple Threat Lead Time     (Condition Combination Analysis)
    STEP 4   : Co-Morbidity Deep Dive      (Triple Threat Volume)
    STEP 5A  : The Trust Wall Derivation   (Threshold Calculation)
    STEP 5   : The Trust Wall Stress Test  (Operational Ceiling)
    STEP 6A  : SMS Rate Comparison         (No-Show Rate by SMS Status)
    STEP 6   : The Digital Ghost Audit     (SMS Failure Analysis)
    STEP 7   : The Accessibility Pressure Test (Handicap Volume)
    STEP 8   : The Guardian-Advocacy Pivot (Pediatric Penalty Audit)

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


-- STEP 1: THE FISCAL BASELINE (Volume & Velocity)
-- Goal: Identify the total patient volume and initial lead time floor.
-- Excludes negative lead times (same-day bookings with data entry artifacts).
-- Note: Queries run against appointments_raw (110,522 records post lead-time filter).
--       CTE production file additionally excludes 1 null PatientId record (110,521 final).
--       Minor count variance between files is expected and documented. See 05_Cleaning_Log.
SELECT 
    Scholarship,
    `No-show` AS no_show_status,
    COUNT(*) AS total_patient_volume, 
    ROUND(AVG(DATE_DIFF(CAST(AppointmentDay AS DATE), CAST(ScheduledDay AS DATE), DAY)), 1) AS avg_lead_time
FROM `healthcare_operations.appointments_raw`
WHERE DATE_DIFF(CAST(AppointmentDay AS DATE), CAST(ScheduledDay AS DATE), DAY) >= 0
GROUP BY 1, 2
ORDER BY 1, 2;


-- STEP 2: THE SELF-ADVOCACY PIVOT (Gender & Churn Velocity)
-- Goal: Quantify the Male Scholarship exit volume.
SELECT 
    Gender,
    Scholarship,
    `No-show` AS no_show_status,
    COUNT(*) AS total_patient_volume,
    ROUND(AVG(DATE_DIFF(CAST(AppointmentDay AS DATE), CAST(ScheduledDay AS DATE), DAY)), 1) AS avg_lead_time
FROM `healthcare_operations.appointments_raw`
WHERE DATE_DIFF(CAST(AppointmentDay AS DATE), CAST(ScheduledDay AS DATE), DAY) >= 0
GROUP BY 1, 2, 3
ORDER BY 1, 2, 3;


-- STEP 3: THE ACUITY PRESSURE TEST (Chronic Volume)
-- Goal: Does clinical urgency (Diabetes/Hypertension) lower the Wall?
SELECT 
    Diabetes,
    Hipertension,
    `No-show` AS no_show_status,
    COUNT(*) AS total_patient_volume,
    ROUND(AVG(DATE_DIFF(CAST(AppointmentDay AS DATE), CAST(ScheduledDay AS DATE), DAY)), 1) AS avg_lead_time
FROM `healthcare_operations.appointments_raw`
WHERE DATE_DIFF(CAST(AppointmentDay AS DATE), CAST(ScheduledDay AS DATE), DAY) >= 0
GROUP BY 1, 2, 3
ORDER BY 1, 2, 3;


-- STEP 4A: TRIPLE THREAT LEAD TIME BY CONDITION COMBINATION
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


-- STEP 4: CO-MORBIDITY DEEP DIVE (The "Triple Threat" Volume)
-- Goal: Quantify the risk to the most clinically complex patients.
SELECT 
    CASE 
        WHEN Hipertension = 1 AND Diabetes = 1 AND Alcoholism = 1 THEN 'Triple Threat'
        WHEN Hipertension = 1 AND Diabetes = 1 THEN 'High-Acuity'
        ELSE 'Baseline' 
    END AS patient_acuity,
    `No-show` AS no_show_status,
    COUNT(*) AS total_patient_volume,
    ROUND(AVG(DATE_DIFF(CAST(AppointmentDay AS DATE), CAST(ScheduledDay AS DATE), DAY)), 1) AS avg_lead_time
FROM `healthcare_operations.appointments_raw`
WHERE DATE_DIFF(CAST(AppointmentDay AS DATE), CAST(ScheduledDay AS DATE), DAY) >= 0
GROUP BY 1, 2
ORDER BY 1, 2;


-- STEP 5A: TRUST WALL DERIVATION (Threshold Calculation)
-- Goal: Find the actual lead-time day where no-show rate shows a sustained
--       behavioral inflection — the point where patient retention decays
--       from a stable baseline into an accelerated churn pattern.
-- Method: Bucket all appointments by lead time day and calculate no-show
--         rate at each interval across all 110,522 records.
-- Finding: No-show rate holds relatively stable at 21-28% through Day 9,
--          then jumps to a sustained 31-35%+ band beginning at Day 10.
--          Day 10 is confirmed as the Trust Wall threshold.
SELECT
    DATE_DIFF(CAST(AppointmentDay AS DATE), CAST(ScheduledDay AS DATE), DAY) AS lead_time_day,
    COUNT(*) AS total_appointments,
    COUNTIF(`No-show` = TRUE) AS total_noshows,
    COUNTIF(`No-show` = FALSE) AS total_shows,
    ROUND(COUNTIF(`No-show` = TRUE) / COUNT(*) * 100, 1) AS noshowrate_pct,
    ROUND(COUNTIF(`No-show` = FALSE) / COUNT(*) * 100, 1) AS show_rate_pct
FROM `healthcare_operations.appointments_raw`
WHERE DATE_DIFF(CAST(AppointmentDay AS DATE), CAST(ScheduledDay AS DATE), DAY) >= 0
GROUP BY 1
ORDER BY 1;
-- Result: Sustained no-show rate acceleration begins at Day 10. ✅
-- Note: Day 0 anomaly (4.6% no-show) reflects same-day booking behavior —
--       a distinct patient cohort excluded from Trust Wall interpretation.


-- STEP 5: THE TRUST WALL STRESS TEST (Operational Ceiling)
-- Goal: Explicitly count patients sitting beyond the 10-day threshold.
-- Note: lead_time >= 10 reflects the behavioral inflection point
--       derived in Step 5A above.
SELECT 
    Scholarship,
    CASE 
        WHEN DATE_DIFF(CAST(AppointmentDay AS DATE), CAST(ScheduledDay AS DATE), DAY) >= 10 THEN 'Beyond Trust Wall'
        ELSE 'Operational Safe Zone'
    END AS trust_wall_status,
    `No-show` AS no_show_status,
    COUNT(*) AS total_patient_volume,
    ROUND(AVG(DATE_DIFF(CAST(AppointmentDay AS DATE), CAST(ScheduledDay AS DATE), DAY)), 1) AS avg_lead_time
FROM `healthcare_operations.appointments_raw`
WHERE DATE_DIFF(CAST(AppointmentDay AS DATE), CAST(ScheduledDay AS DATE), DAY) >= 0
GROUP BY 1, 2, 3
ORDER BY 1, 2, 3;


-- STEP 6A: SMS NO-SHOW RATE COMPARISON
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


-- STEP 6: THE DIGITAL GHOST AUDIT (SMS Failure Analysis)
-- Goal: Expose the "Post-Mortem" scoreboard effect.
-- Finding: SMS recipients no-showed at 27.6% vs. 16.7% for non-recipients.
-- Average lead time for SMS recipients with no-show: 20.0 days.
-- Confirming SMS alone is not a reliable retention lever beyond the Trust Wall.
SELECT 
    SMS_received,
    `No-show` AS no_show_status,
    COUNT(*) AS total_patient_volume,
    ROUND(AVG(DATE_DIFF(CAST(AppointmentDay AS DATE), CAST(ScheduledDay AS DATE), DAY)), 1) AS avg_lead_time
FROM `healthcare_operations.appointments_raw`
WHERE DATE_DIFF(CAST(AppointmentDay AS DATE), CAST(ScheduledDay AS DATE), DAY) >= 0
GROUP BY 1, 2
ORDER BY 1, 2;


-- STEP 7: THE ACCESSIBILITY PRESSURE TEST (Handicap Volume)
-- Goal: Determine if disability status compresses the Trust Wall threshold.
-- Note: Using raw column name 'Handcap' to match dataset spelling.
-- Finding: Disabled patients no-show at avg 13.0 days vs 15.9 days baseline (~3 days earlier).
-- Supplementary finding — reinforces self-advocacy churn theory. ~2% of total volume.
SELECT 
    CASE WHEN Handcap > 0 THEN 1 ELSE 0 END AS is_disabled,
    `No-show` AS no_show_status,
    COUNT(*) AS total_patient_volume, 
    ROUND(AVG(DATE_DIFF(CAST(AppointmentDay AS DATE), CAST(ScheduledDay AS DATE), DAY)), 1) AS avg_lead_time
FROM `healthcare_operations.appointments_raw`
WHERE DATE_DIFF(CAST(AppointmentDay AS DATE), CAST(ScheduledDay AS DATE), DAY) >= 0
GROUP BY 1, 2
ORDER BY 1, 2;


-- STEP 8: THE GUARDIAN-ADVOCACY PIVOT (Pediatric Penalty Audit)
-- Goal: Identify the trust-erosion gap between parents and self-advocating adults.
-- Theory: Does the responsibility of a dependent's schedule increase the "Logistical Leak"?
-- Finding: Guardians (Minors) hit the Trust Wall at 21.9% vs. Adults at 19.63%.
-- Result: A 2.27% variance (11.5% higher failure rate) for families confirms
--         that advocacy type is a primary driver of service failure.
SELECT 
    CASE 
        WHEN Age < 18 THEN 'Guardian-Advocate (Minor)'
        ELSE 'Self-Advocate (Adult)' 
    END AS advocacy_type,
    `No-show` AS no_show_status,
    COUNT(*) AS total_patient_volume,
    ROUND(AVG(DATE_DIFF(CAST(AppointmentDay AS DATE), CAST(ScheduledDay AS DATE), DAY)), 1) AS avg_lead_time
FROM `healthcare_operations.appointments_raw`
WHERE DATE_DIFF(CAST(AppointmentDay AS DATE), CAST(ScheduledDay AS DATE), DAY) >= 0
GROUP BY 1, 2
ORDER BY 1, 2;
