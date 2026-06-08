The Monopoly Hangover Audit
Healthcare patient no-show forensic audit — Trust Wall analysis and $4.5M revenue impact
---
The Problem
A healthcare provider operating in a historically low-competition market developed operational habits that worked when patients had no alternatives. As the surrounding community grew and competition arrived, those habits became liabilities. Patients began leaving — not because of a single defining moment, but because a 10-day scheduling threshold was silently eroding the patient-provider relationship before anyone noticed.
This audit identifies that threshold, quantifies its cost, and presents a three-phase operational recovery framework.
Key Findings
The 10-Day Trust Wall — Patients who show average an 8-day wait. Patients who no-show average a 16-day wait. Day 10 is where the decision is already made.
$4.5M Revenue Gap — $309,360 in Medicaid guaranteed revenue and $4,144,560 in out-of-pocket growth potential lost to no-shows driven by the Trust Wall.
The SMS Paradox — SMS recipients no-showed at a higher rate than non-recipients — 27.6% vs. 16.7%. Without timestamp data, effectiveness cannot be properly evaluated. SMS alone is not a reliable retention tool.
Triple Threat Finding — Patients managing diabetes, hypertension, and alcoholism simultaneously hit the Trust Wall sooner, averaging 12 days vs. 16 days for patients with no conditions.
---
The Recovery Framework
Phase 1 — Stop the Revenue Leak (This analysis)
Implement the 8-Day Operational Framework, the Three-Point Handshake communication sequence, and telehealth extension to protect existing revenue.
Phase 2 — Recover Lost Revenue
Develop a patient win-back strategy using the data and operational discipline established in Phase 1.
Phase 3 — Increase Revenue
Pursue growth through expanded capacity, new patient acquisition, and competitive positioning in a growing market.
Tools & Methods
SQL / BigQuery — Forensic data analysis across 110,527 appointment records
Python / pandas — Full replication of the SQL audit in Python, confirming all findings independently and to the decimal
Tableau Public — Dashboard with four analytical assets visualizing the Trust Wall finding, SMS analysis, Triple Threat clinical friction, and revenue split.
Documentation — Executive summary, operational recommendations, validation report, and presentation framework
---
Repository Contents
File	Description
`06_SQL_Master_StepByStep.sql`	Forensic workbench — standalone queries executed sequentially for step-by-step audit
`07_SQL_Production_CTE.sql`	Production architecture — single coherent CTE chain covering all analytical dimensions
`08_Python_Audit_Notebook.ipynb`	Python replication — all SQL findings confirmed in pandas, structured as a Kaggle-ready notebook
---
Project Deliverables
📊 Tableau Dashboard — (link to be added upon public release)
📑 Presentation Slides — (link to be added upon public release)
---
About
Lead Analyst: Robert Hoye-Logan
Dataset: 110,527 appointment records — Vitória, Brazil (2016), applied as a behavioral proxy for small community provider dynamics in any high-growth market where monopoly conditions are transitioning to competition.
Analysis Date: May 2026
The no-show problem is not a patient compliance failure. It is a provider scheduling failure with a provider scheduling solution.
