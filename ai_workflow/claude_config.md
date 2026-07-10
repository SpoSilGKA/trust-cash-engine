markdown
# Claude AI Configuration & Prompt Workflow

## Overview
This document logs the specific prompt engineering strategy and system configuration rules used to collaborate with Claude AI. It demonstrates how to guide an LLM to build a regulation-compliant financial engine while bypassing false-positive security guardrails through precise mock environment framing.

## The Prompting Challenge
Initially, presenting unconfigured tools or corporate database names caused the AI model to default to a high-caution mode. It broke character, refused to assume system context, and flagged the request as an operational risk (fearing unauthorized backend data access).

## The Strategic Solution
To overcome this roadblock, the workflow shifted from broad corporate framing to **explicit, mock-data sandbox configuration**. By providing the AI with granular technical rules, it successfully unblocked its security guardrails and generated production-grade logic.

### 1. The Fiduciary-Aware Engineering Rules
To force the AI to understand wealth management constraints over standard retail banking, the following prompt boundaries were fed into the model:
* **The Threshold Rule:** Enforce an operational floor (e.g., $5,000) to stop transaction churn on negligible cash balances.
* **The Settlement Drag Screen:** Check for mid-settlement locks (`PendingSettlementDrag '= 0`) to suppress roll alerts on un-executable funds.
* **The Principal/Income Split:** Mandate conditional branching (`CASE` statements / `$PIECE` indexing) to parse discount instruments (Bills) from coupon-bearing instruments (Notes/Bonds) to separate ledger positions.

### 2. The Fail-Safe Compliance Prompt
To mirror institutional audit requirements, the model was instructed to build a table-driven compliance rule matrix. The critical prompt constraint required a `LEFT JOIN` (SQL) / `$DATA` check (MUMPS) to handle unmapped portfolio variables:
> *"If an account type lacks a matching compliance rule in the lookup system, the engine must systematically route it to a `COMPLIANCE_HOLD` code and pass a `NULL` yield value, rather than silently omitting it from the queue."*

## Outcome & Portfolio Value
By documenting this setup alongside the `analytics_warehouse.sql` and `core_ledger.mps` files, this repository showcases full cross-functional capability: bridging legacy transaction platforms, modern cloud data analysis, and advanced generative AI systems collaboration.

Step 2: Update Your ai_workflow/claude_config.md File
Since your original issue with Claude was a "Tool Guardrail" restriction regarding an unconfigured database tool, the fact that you use the Model Context Protocol (MCP) is the exact technical explanation for how you configure your AI environment.
Run nano ai_workflow/claude_config.md and append this section to the bottom of the file to document your stack setup:
markdown
## Local Container & Dashboard Environment Setup

### 1. Podman Container Configuration (MS SQL Server)
The relational analytics tier is hosted locally inside an isolated Linux container using Podman to prevent local system resource drag.
* **Image:** `://microsoft.com`
* **Container Command:** 
  ```bash
  podman run -e "ACCEPT_EULA=Y" -e "MSSQL_SA_PASSWORD=YourSecurePassword123!" -p 1433:1433 --name mssql-trust-db -d ://microsoft.com
  ```

### 2. Model Context Protocol (MCP) Bridging
To allow the AI assistant to interface directly with this sandbox environment, an **MCP Database Tool Server** (`mssql-database`) is mapped in the local environment config (`mcp-config.json`):
```json
{
  "mcpServers": {
    "mssql-database": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-mssql"],
      "env": {
        "MSSQL_CONNECTION_STRING": "Server=localhost,1433;Database=TrustAnalytics;User Id=sa;Password=YourSecurePassword123!;Encrypt=false;"
      }
    }
  }
}
```

### 3. Power BI Analytics Engine (Windows 11)
A Windows 11 native Power BI instance queries the Podman container via the standard SQL Server Database Connector. 
* **Data Refresh Cadence:** Daily batch processing following the close of the short-term Treasury auction window.
* **Primary Visualizations:** Per-diem Total Cost of Inaction (Actual/360), Portfolio Compliance Audits (filtering out `COMPLIANCE_HOLD` records to top-level cards), and Maturing Treasury Ladders (7-day outlook).
