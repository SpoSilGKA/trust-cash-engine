# Trust & Custodial Cash-Sweep Optimization Engine

## Project Overview
This project provides a localized proof-of-concept (POC) for a **Trust & Custodial Cash Management and Fixed-Income Roll Engine**. It simulates an enterprise-level wealth management system (mirroring a cash management solution, devised and implemented, during my tenure at Chase Manhattan Bank) designed to systematically eliminate idle cash drag while enforcing strict fiduciary risk boundaries. 

The architecture demonstrates a comprehensive, cross-platform design. It pairs a **Core Transactional Ledger Layer (MUMPS)** with a **Modern Analytics Layer (T-SQL)**, showcasing how data seamlessly moves from high-throughput transactional backends to relational reporting warehouses.

---

## Part 1: Relational Analytics Layer (T-SQL Executive Summary as well as SQL dialects: Oracle PS/SQL; PostgreSQL; MySQL)

### 1. The Operational Problem
Manually managing idle cash and maturing short-term Treasury positions across a large book of Trust and Custodial accounts creates two compounding costs:

* **Yield Drag:** Uninvested principal sitting in low-yield checking sweeps (often 0.05%) rather than a short-term vehicle earning materially more accrues a real, quantifiable opportunity cost every single day it goes unaddressed. Manual, periodic (e.g., weekly or monthly) review cycles are structurally too slow to catch this leakage in real time.
* **Structural Compliance Risk:** When fiduciary rate ceilings and sweep eligibility rules live only in an analyst's memory, a policy document, or an ad hoc spreadsheet, there is no reliable barrier preventing an Irrevocable trust account from being swept into a vehicle its governing terms don't permit. This represents a severe, potential breach of fiduciary duty that manual oversight cannot systematically protect against.

### 2. The Structural Innovation
Two key design decisions remove human calculation error from this process entirely, rather than just making it faster:

* **The Principal/Income Split:** Splitting the Principal and Income cash ledgers at the point of maturity—routing final coupon payments to `Income_Cash` and redemption proceeds to `Principal_Cash` based on instrument type—ensures downstream accounting reflects the correct character of the cash automatically. This is a crucial distinction across a mixed book of discount instruments (Bills) and coupon-bearing instruments (Notes/Bonds).
* **Table-Driven Rule Governance:** Moving fiduciary rate ceilings out of hardcoded logic and into a governed lookup table (`Fiduciary_Sweep_Rules`) means compliance policy is no longer embedded in code that only engineering can see or change. Trust and Compliance officers can maintain the actual legal ceilings directly in data, entirely eliminating "stale code" risk.

### 3. The Control Architecture
The engine uses a fail-safe control framework to handle the exact scenario a purely manual or naively-coded process is most likely to get wrong: unmapped account types.

* **`LEFT JOIN` Safety Net:** Using a `LEFT JOIN` rather than an `INNER JOIN` against the rules table guarantees that every idle-cash account remains visible in the output. An `INNER JOIN` would silently drop unmapped accounts from the report entirely. In institutional risk terms, silent omission is worse than an explicit error.
* **Compliance Routing:** Unmatched accounts are automatically routed to a `COMPLIANCE_HOLD` action code instead of a sweep recommendation. 
* **Distinct Null Routing:** The yield-lift figure for holds is returned as `NULL` rather than `0.00` to prevent downstream dashboard or ETL processes from misreading a blocked account as a zero-balance account.
* **Prioritized Exception Sorting:** The output places `COMPLIANCE_HOLD` rows at the absolute top of the report, ensuring a human reviewer sees the exceptions before routine recommendations. The system's default behavior under uncertainty is always to stop and flag, never to proceed silently.

### 4. The Financial & Risk Impact
Calculating yield lift on a daily, **Actual/360** basis—the correct institutional money-market convention—reframes idle cash as a live, per-diem cost of inaction rather than an abstract annual number. This gives operations teams a concrete, prioritizable figure for triaging queues.

Critically, every yield-lift figure this engine produces is already constrained by the applicable fiduciary rate cap before it's ever displayed—an Irrevocable trust account never shows a lift number computed against a rate it isn't legally permitted to access.

---

## Part 2: Core Ledger Layer (MUMPS Architecture & Integration Summary)

### 1. Functional Equivalence in NoSQL
To prove full system portability, the exact financial and compliance logic was translated into a core transactional **MUMPS (NoSQL)** routine. Because hierarchical databases lack relational tables and declarative joins, the load-bearing controls were rebuilt using native multi-dimensional tree mechanics:

* **`$ORDER` Traversal Loops:** Replaces relational `SELECT/WHERE` scans to sequentially step through nested account and position data.
* **`$PIECE` Field Unpacking:** Safely extracts specific fields (like face value or maturity date) from string data nodes delimited by carets (`^Account`).
* **`$DATA` Compliance Safety Net:** Serves as the direct structural equivalent of the T-SQL `LEFT JOIN`. The `$DATA` function explicitly checks if the `^Rules(FiduciaryType)` node exists. If it returns 0, the program immediately halts execution for that account and branches to a `COMPLIANCE_HOLD` state.
* **Null Value Mapping:** Setting `DailyYieldLift=""` (the closest MUMPS native equivalent to a relational database `NULL`) guarantees that blocked accounts remain visually and systematically distinct from legitimate zero-balance accounts.

### 2. Live System Architecture & Technical Stack
The production-ready proof of concept is deployed across a containerized, hybrid-OS data pipeline, separating transactional recording from executive BI reporting:



┌──────────────────────────────────────┐
│ CORE TRANSACTION TIER │ --> Runs on Core Systems
│ MUMPS NoSQL Database Ledger │
└──────────────────┬───────────────────┘
│
│ (Data Replication via ETL/CDC)
▼
┌──────────────────────────────────────┐
│ ANALYTICAL STORAGE TIER │ --> Hosted on Linux
│ Microsoft SQL Server (MS SQL) │ Podman Container
└──────────────────┬───────────────────┘
│
│ (Orchestrated via Model Context Protocol / MCP)
▼
┌──────────────────────────────────────┐
│ EXECUTIVE REPORTING TIER │ --> Rendered on Windows 11
│ Power BI Desktop Dashboard │
└──────────────────────────────────────┘

#### Technical Stack Breakdown:
* **Core Transaction Ledger (MUMPS NoSQL):** The high-throughput system of record handling live trust accounts (`^Portfolio`), multi-currency balances (`^Ledger`), and fixed-income assets (`^Inventory`).
* **Containerized Analytics Warehouse (MS SQL Server on Podman):** A secure, isolated MS SQL Server database running inside a Linux Podman container. This isolates heavy analytical queries (`LEFT JOIN` compliance logic and fiduciary lookup tables) away from live transactional core systems.
* **Orchestration Layer (Model Context Protocol - MCP):** Utilizing the Model Context Protocol (MCP) tool-context mapping to bridge data-layer connections securely, allowing analytical engines to read schemas dynamically.
* **Executive Visualization Layer (Power BI on Windows 11):** A Power BI Desktop suite running natively on Windows 11, connecting via standard database connectors to the Podman MS SQL instance to transform raw daily Actual/360 yield lift metrics into executive-facing operational dashboards.
### 3. Cross-Layer Data Consistency
Data is replicated dynamically out of the core transactional backend into the relational warehouse using ETL or Change Data Capture (CDC) pipelines. This setup permits advanced risk modeling, compliance reviews, and comprehensive auditing without ever slowing down the live core database. 

By mirroring the identical "flag and hold, never silently drop" safety philosophy across both layers (`$DATA` in MUMPS and `LEFT JOIN` in T-SQL), the system ensures complete architectural alignment and cross-layer consistency—exactly what an auditor expects to see documented in a production control environment.

---

## Repository Structure
* **`README.md`**: Architectural documentation and business summary (this file).
* **`analytics/analytics_warehouse.sql`**: Relational database script written in production-grade T-SQL.
* **`core_ledger/core_ledger.mps`**: Transactional database routine written in clean, readable MUMPS syntax.
* **`ai_workflow/claude_config.md`**: Prompt engineering documentation detailing the risk-control guidelines used to guide the AI configuration.
