# SPEC: {{project_name}}

The contract between the Fabric, Power BI and Power Platform layers of this repository. **Update this file first** when you rename, retype or remove anything listed here, then update every consumer. Agents treat it as the source of truth: a change that is not reflected here is a defect, and a name that is not listed here has no owner.

Status: DRAFT. Replace the example rows, and delete a section that does not apply. Keep it short: a table that nobody maintains is worse than none.

## 1. Data (Fabric)

| Object | Kind | Where | Grain / purpose |
|---|---|---|---|
| `sales_fact` | Delta table | Lakehouse `Core` | one row per order line |

## 2. Semantic model

| Table | Column or measure | Kind | Expression or source | Used by |
|---|---|---|---|---|
| `Sales` | `Total Sales` | measure | `SUM(Sales[Amount])` | Overview report |

**Relationships.** Name each one, its cardinality and filter direction. Record why any bidirectional or many-to-many relationship is needed; without a reason it is a defect.

## 3. Reports

| Report | Page | Visual | Fields it binds (table.column or measure) |
|---|---|---|---|
| `Overview` | `Summary` | Total sales card | `Sales.Total Sales` |

## 4. Dataverse (Power Platform)

| Table | Column | Type | Notes |
|---|---|---|---|

## 5. Environment variables and connection references

Write where a value **comes from**, never a value that is specific to one environment.

| Name | Kind | Source per environment | Used by |
|---|---|---|---|
| `new_ApiBaseUrl` | environment variable (text) | deployment settings | flow `Sync orders` |

## 6. Flows and apps

| Name | Trigger or entry point | Reads | Writes | Notes |
|---|---|---|---|---|

## 7. Decisions

Decisions an agent must not reverse silently: date, decision, reason.

- _none yet_
