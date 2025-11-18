Insurance Premium Schedule Engine

This project automates the generation of premium payment schedules for an insurance broker.
The aim is to replace the slow, error-prone month-end process—previously taking 3–5 days of manual adjustments—with a fully automated, ultra-precise calculation engine.

The solution handles the full payment lifecycle across multiple insurance products, including:

Monthly, quarterly, and annual payment structures

Mid-term upgrades, cancellations, and overlapping policies

Recalculations that must be accurate down to two decimal places

Allocation of payments into a cohort-style matrix (underwritten month × payment month)


✨ What This Project Delivers

🚀 Fully automated month-end payment schedules

🔍 Accurate allocation logic built from raw transactional data

🔄 Consistency across 5+ insurance products

📊 Optimised Power BI report using a hybrid approach (Power Query for heavy logic, DAX for final allocation)

📁 Audit-ready Excel extract, generated automatically at a precise time window

⚡ Faster iteration cycles using snapshotting of MySQL data for validation


🛠️ Built With

MySQL — raw transactional data source

Power BI Dataflows — centralised data ingestion and prep

Power Query (M) — main transformation and business logic engine

DAX — lightweight final allocation calculations

Power Automate — scheduled refresh + automated Excel export for audit

Performance Analyzer & DAX Studio — performance optimisation

Power BI Desktop — reporting and modelling layer

📌 Purpose of the Repository

This repo exists to:

Document the architecture used to automate premium payment allocation

Showcase the Power Query and DAX logic used to model complex insurance events

Provide a reference implementation for similar use cases

Highlight how upstream logic improvements drastically improve Power BI performance

Highlight how upstream logic improvements drastically improve Power BI performance
