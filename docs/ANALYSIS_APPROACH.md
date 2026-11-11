# Analysis Approach - Northstar Data Quality Investigation

## 1. Business problem and analytical objective

Finance, Operations and Sales reported different revenue-related figures for the same period. The investigation examined transaction-level records across operational systems rather than assuming that any one system was authoritative.

The objectives were to identify inconsistencies, measure their financial impact, test plausible explanations and recommend controls for more reliable reporting. This is a simulated business investigation.

## 2. Data sources and tools

Five imported SQL Server tables were used:

| Table | Records | Role in the investigation |
|---|---:|---|
| `customers` | 1,800 | Customer reference data |
| `orders` | 42,000 | Quantities, unit prices, discounts and order statuses |
| `payments` | 40,986 | Payment amounts and statuses |
| `refunds` | 2,197 | Refund transactions |
| `crm_export` | 41,880 | CRM deal values and statuses |

SQL Server Management Studio (T-SQL) was used for validation and reconciliation. Power BI was used to present the investigation results to a business audience.

## 3. Source validation

Before comparing financial values, I checked table row counts, column types and the uniqueness of technical IDs (`customer_id`, `order_id`, `payment_id`, `refund_id` and `crm_record_id`). I also tested `order_id` as a business key in the CRM export: a unique technical record ID does not guarantee a unique underlying transaction.

Financial columns in `crm_export`, `payments` and `refunds` were converted to `DECIMAL(18,2)` and their types checked again. These checks are documented in [`02_data_validation.sql`](../sql/02_data_validation.sql).

## 4. CRM duplication investigation

I grouped CRM records by `order_id` to identify business transactions represented more than once. I then isolated `Closed Won` records and estimated duplicated deal value as the sum of recorded values minus one retained value (the maximum deal value) for each duplicated order ID.

The investigation found **373 duplicated CRM order IDs**. Within `Closed Won` records, **356 affected orders** represented **£1,083,232.41** of duplicated deal value under this calculation. This is a *potential overstatement in CRM deal reporting*, not evidence of cash received or lost.

## 5. Cross-system status and refund checks

I compared order-status and payment-status distributions, linked completed payments to their associated orders and aggregated refunds by `order_id` before joining them to payment records. This enabled comparison of completed payment values, refund values and net cash by order status.

These checks matter because an order marked `Completed`, a completed payment, a CRM deal value and net cash are distinct measures. Refund activity and completed payments were also observed across different order statuses.

## 6. Payment-to-order reconciliation

For each linked order and completed payment, I calculated the expected order value:

```text
Expected order value = quantity × unit_price × (1 − discount)
Variance = completed payment amount − expected order value
```

The SQL reconciliation classified variances within **±£0.01** as matches, variances below **−£0.01** as underpayments and variances above **£0.01** as overpayments. The one-penny threshold allows for minor rounding differences.

Among **39,999 completed payment records**, **36,014 (90.04%)** matched and **3,985 (9.96%)** had material differences. All material mismatches were underpayments, totalling **£5,194,735.32** in negative variance. This is a reconciliation difference against calculated order value; the available data does not establish that the amount is a confirmed financial loss.

## 7. Hypothesis testing and anomaly profiling

Rather than attributing the differences to a cause without evidence, I examined several possible explanations:

- **Order status:** **3,769 of 3,985 underpayments (94.6%)** were linked to orders marked `Completed`. Operational completion therefore did not guarantee payment reconciliation.
- **Discount usage:** underpayment rates were **10.08%** for discounted orders and **9.82%** for non-discounted orders. The similar rates did not support discounting as the main explanation.
- **Payment coverage:** I grouped underpayments by payment-to-order-value ratio to look for recurring patterns. The differences occurred across multiple ratio bands, without one ratio explaining the issue.
- **Refund activity:** I compared refunds and payments across order statuses to distinguish gross payment amounts from net cash.

These tests identified where discrepancies were concentrated but **did not establish a definitive single root cause**. Investigation of upstream payment-processing and data-transfer logic would require additional system evidence.

## 8. Power BI communication

The Power BI report translates SQL findings into an executive-facing investigation. Its **Executive Summary** presents reconciliation counts, financial variance, CRM duplication and underpayment patterns. Its **Investigation Findings** page communicates the principal findings, business implications, recommendations and limitations.

The report is provided in [`Northstar_Data_Quality_Investigation.pbix`](../power_bi/Northstar_Data_Quality_Investigation.pbix).

## 9. Recommendations

1. Add automated CRM checks for repeated `order_id` values before aggregating deal values.
2. Reconcile completed payments against calculated order values before management reporting.
3. Flag exceptions outside an agreed variance tolerance and monitor both their number and value.
4. Review payment-generation, processing and cross-system transfer logic for affected orders.
5. Agree and document separate business definitions for CRM deal value, order value, completed payments, refunds and net cash.

## 10. Limitations and interpretation

The available operational data supports detection, quantification and profiling of inconsistencies, but not a confirmed explanation of how the payment differences arose. Likewise, duplicated CRM deal values indicate a reporting risk, not necessarily duplicate underlying sales. Findings should not be interpreted as verified revenue loss without further operational and financial investigation.

## Supporting project files

- [`01_database_setup.sql`](../sql/01_database_setup.sql) — database setup.
- [`02_data_validation.sql`](../sql/02_data_validation.sql) — source validation and CRM business-key checks.
- [`03_revenue_reconciliation.sql`](../sql/03_revenue_reconciliation.sql) — cross-system reconciliation, anomaly profiling and hypothesis tests.
- [`README.md`](../README.md) — project overview, findings and business context.
