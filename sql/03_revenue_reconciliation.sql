/*
Northstar Office Supplies
03 - Revenue reconciliation

Business problem:
Finance, Operations and Sales report different revenue figures for the same period.

Objective:
Trace discrepancies across CRM, order, payment and refund data, quantify
financial impact and identify controls needed for reliable reporting.
*/
USE NorthstarDataQuality;
GO

-- 1. CRM DUPLICATION: FINANCIAL IMPACT
WITH duplicated_orders AS (
    SELECT order_id, COUNT(*) record_count,
           MAX(deal_value) single_deal_value,
           SUM(deal_value) reported_deal_value
    FROM crm_export
    GROUP BY order_id
    HAVING COUNT(*) > 1
)
SELECT COUNT(*) affected_orders,
       ROUND(SUM(reported_deal_value-single_deal_value),2) duplicated_deal_value
FROM duplicated_orders;

-- 2. CRM STATUS REVIEW
SELECT deal_status, COUNT(*) record_count, ROUND(SUM(deal_value),2) total_deal_value
FROM crm_export
GROUP BY deal_status
ORDER BY total_deal_value DESC;

WITH closed_won_duplicates AS (
    SELECT order_id, COUNT(*) record_count,
           MAX(deal_value) valid_deal_value,
           SUM(deal_value) reported_deal_value
    FROM crm_export
    WHERE deal_status='Closed Won'
    GROUP BY order_id
    HAVING COUNT(*) > 1
)
SELECT COUNT(*) affected_orders,
       ROUND(SUM(reported_deal_value-valid_deal_value),2) closed_won_duplicated_value
FROM closed_won_duplicates;

-- 3. ORDER AND PAYMENT STATUS REVIEW
SELECT order_status, COUNT(*) order_count,
       ROUND(SUM(quantity*unit_price*(1-discount)),2) order_value
FROM orders GROUP BY order_status ORDER BY order_value DESC;

SELECT payment_status, COUNT(*) payment_count, ROUND(SUM(amount),2) payment_value
FROM payments GROUP BY payment_status ORDER BY payment_value DESC;

-- 4. COMPLETED PAYMENTS VS ORDER STATUS
SELECT o.order_status, COUNT(*) payment_count,
       ROUND(SUM(p.amount),2) completed_payment_value
FROM payments p
LEFT JOIN orders o ON p.order_id=o.order_id
WHERE p.payment_status='Completed'
GROUP BY o.order_status
ORDER BY completed_payment_value DESC;

-- 5. REFUND RECONCILIATION BY ORDER STATUS
WITH refund_totals AS (
    SELECT order_id, SUM(refund_amount) total_refund
    FROM refunds GROUP BY order_id
)
SELECT o.order_status, COUNT(*) completed_payments,
       ROUND(SUM(p.amount),2) payment_value,
       COUNT(r.order_id) payments_with_refund,
       ROUND(SUM(COALESCE(r.total_refund,0)),2) refund_value,
       ROUND(SUM(p.amount)-SUM(COALESCE(r.total_refund,0)),2) net_cash
FROM payments p
JOIN orders o ON p.order_id=o.order_id
LEFT JOIN refund_totals r ON p.order_id=r.order_id
WHERE p.payment_status='Completed'
GROUP BY o.order_status
ORDER BY payment_value DESC;

-- 6. ORDER VS PAYMENT STATUS MATRIX
SELECT o.order_status, p.payment_status, COUNT(*) record_count,
       ROUND(SUM(p.amount),2) payment_value
FROM orders o
LEFT JOIN payments p ON o.order_id=p.order_id
GROUP BY o.order_status,p.payment_status
ORDER BY o.order_status,p.payment_status;

-- 7. ORDER VALUE VS COMPLETED PAYMENT RECONCILIATION
WITH reconciliation AS (
    SELECT o.order_id,o.order_status,
           ROUND(o.quantity*o.unit_price*(1-o.discount),2) order_value,
           p.amount payment_value,
           ROUND(p.amount-(o.quantity*o.unit_price*(1-o.discount)),2) variance
    FROM orders o JOIN payments p ON o.order_id=p.order_id
    WHERE p.payment_status='Completed'
)
SELECT COUNT(*) completed_payments,
       SUM(CASE WHEN ABS(variance)<=0.01 THEN 1 ELSE 0 END) exact_matches,
       SUM(CASE WHEN ABS(variance)>0.01 THEN 1 ELSE 0 END) mismatches,
       ROUND(SUM(variance),2) total_variance
FROM reconciliation;

-- 8. LARGEST PAYMENT MISMATCHES
WITH reconciliation AS (
    SELECT o.order_id,o.order_status,
           ROUND(o.quantity*o.unit_price*(1-o.discount),2) order_value,
           p.amount payment_value,
           ROUND(p.amount-(o.quantity*o.unit_price*(1-o.discount)),2) variance
    FROM orders o JOIN payments p ON o.order_id=p.order_id
    WHERE p.payment_status='Completed'
)
SELECT TOP 20 order_id,order_status,order_value,payment_value,variance
FROM reconciliation
WHERE ABS(variance)>0.01
ORDER BY ABS(variance) DESC;

-- 9. PAYMENT MISMATCH PROFILE
WITH reconciliation AS (
    SELECT o.order_id,o.order_status,
           ROUND(o.quantity*o.unit_price*(1-o.discount),2) order_value,
           p.amount payment_value,
           ROUND(p.amount-(o.quantity*o.unit_price*(1-o.discount)),2) variance
    FROM orders o JOIN payments p ON o.order_id=p.order_id
    WHERE p.payment_status='Completed'
)
SELECT CASE WHEN variance < -0.01 THEN 'Underpayment'
            WHEN variance > 0.01 THEN 'Overpayment'
            ELSE 'Exact match' END variance_type,
       COUNT(*) record_count, ROUND(SUM(variance),2) total_variance,
       ROUND(AVG(variance),2) avg_variance,
       ROUND(MIN(variance),2) min_variance,
       ROUND(MAX(variance),2) max_variance
FROM reconciliation
GROUP BY CASE WHEN variance < -0.01 THEN 'Underpayment'
              WHEN variance > 0.01 THEN 'Overpayment'
              ELSE 'Exact match' END
ORDER BY record_count DESC;

-- 10. UNDERPAYMENTS BY ORDER STATUS
WITH reconciliation AS (
    SELECT o.order_id,o.order_status,
           ROUND(o.quantity*o.unit_price*(1-o.discount),2) order_value,
           p.amount payment_value,
           ROUND(p.amount-(o.quantity*o.unit_price*(1-o.discount)),2) variance
    FROM orders o JOIN payments p ON o.order_id=p.order_id
    WHERE p.payment_status='Completed'
)
SELECT order_status, COUNT(*) underpayment_count,
       ROUND(SUM(variance),2) total_underpayment,
       ROUND(AVG(variance),2) avg_underpayment
FROM reconciliation
WHERE variance < -0.01
GROUP BY order_status
ORDER BY underpayment_count DESC;

-- 11. ROOT-CAUSE TEST: DISCOUNT VS UNDERPAYMENT
WITH reconciliation AS (
    SELECT o.order_id,o.order_status,o.discount,
           ROUND(o.quantity*o.unit_price*(1-o.discount),2) order_value,
           p.amount payment_value,
           ROUND(p.amount-(o.quantity*o.unit_price*(1-o.discount)),2) variance
    FROM orders o JOIN payments p ON o.order_id=p.order_id
    WHERE p.payment_status='Completed'
)
SELECT CASE WHEN discount=0 THEN 'No discount'
            WHEN discount>0 THEN 'Discount applied'
            ELSE 'Unknown' END discount_group,
       COUNT(*) payment_count,
       SUM(CASE WHEN variance < -0.01 THEN 1 ELSE 0 END) underpayment_count,
       ROUND(100.0*SUM(CASE WHEN variance < -0.01 THEN 1 ELSE 0 END)/COUNT(*),2) underpayment_pct,
       ROUND(AVG(CASE WHEN variance < -0.01 THEN variance END),2) avg_underpayment
FROM reconciliation
GROUP BY CASE WHEN discount=0 THEN 'No discount'
              WHEN discount>0 THEN 'Discount applied'
              ELSE 'Unknown' END;

-- 12. ROOT-CAUSE TEST: PAYMENT RATIO
WITH reconciliation AS (
    SELECT o.order_id,o.order_status,
           ROUND(o.quantity*o.unit_price*(1-o.discount),2) order_value,
           p.amount payment_value,
           ROUND(p.amount-(o.quantity*o.unit_price*(1-o.discount)),2) variance
    FROM orders o JOIN payments p ON o.order_id=p.order_id
    WHERE p.payment_status='Completed'
),
underpayments AS (
    SELECT *, ROUND((payment_value/NULLIF(order_value,0))*100,2) payment_pct
    FROM reconciliation WHERE variance < -0.01
)
SELECT CASE WHEN payment_pct=0 THEN '0%'
            WHEN payment_pct<25 THEN '0-25%'
            WHEN payment_pct<50 THEN '25-50%'
            WHEN payment_pct<75 THEN '50-75%'
            WHEN payment_pct<90 THEN '75-90%'
            ELSE '90-100%' END payment_ratio_band,
       COUNT(*) underpayment_count,
       ROUND(AVG(payment_pct),2) avg_payment_pct,
       ROUND(AVG(variance),2) avg_underpayment
FROM underpayments
GROUP BY CASE WHEN payment_pct=0 THEN '0%'
              WHEN payment_pct<25 THEN '0-25%'
              WHEN payment_pct<50 THEN '25-50%'
              WHEN payment_pct<75 THEN '50-75%'
              WHEN payment_pct<90 THEN '75-90%'
              ELSE '90-100%' END
ORDER BY MIN(payment_pct);



-- ============================================================
-- 13. POWER BI RECONCILIATION DATASET
-- ============================================================

SELECT
    o.order_id,
    o.order_status,
    o.quantity,
    o.unit_price,
    o.discount,
    ROUND(
        o.quantity * o.unit_price * (1 - o.discount),
        2
    ) AS order_value,
    p.payment_status,
    p.amount AS payment_value,
    ROUND(
        p.amount - (o.quantity * o.unit_price * (1 - o.discount)),
        2
    ) AS variance,
    CASE
        WHEN p.payment_status = 'Completed'
             AND p.amount - (o.quantity * o.unit_price * (1 - o.discount)) < -0.01
            THEN 'Underpayment'
        WHEN p.payment_status = 'Completed'
             AND p.amount - (o.quantity * o.unit_price * (1 - o.discount)) > 0.01
            THEN 'Overpayment'
        WHEN p.payment_status = 'Completed'
            THEN 'Exact match'
        ELSE 'Not completed'
    END AS reconciliation_status
FROM orders o
LEFT JOIN payments p
    ON o.order_id = p.order_id;

/*
KEY FINDINGS

- 373 order IDs appeared more than once in the CRM export.
- 356 duplicated Closed Won orders represented £1,083,232.41 of duplicated deal value.
- 3,985 completed payment records did not reconcile to calculated order value.
- All 3,985 material mismatches were underpayments; no material overpayments were identified.
- Total underpayment variance was £5,194,735.32.
- Average underpayment was £1,303.57.
- 3,769 underpayments (94.6%) related to orders marked Completed.
- Discount applied: 10.08% underpayment rate; no discount: 9.82%.
- No single payment-ratio pattern explained the discrepancies.

CONCLUSION

The analysis identified two separate reconciliation risks:
1. duplicated CRM business transactions that can inflate Sales deal value if raw CRM records are summed; and
2. material differences between completed payment amounts and calculated order values.

The available data does not establish one root cause for the payment variance.

RECOMMENDATIONS

1. Add an automated order_id duplicate check to CRM reporting.
2. Reconcile completed payments to expected order values before management reporting.
3. Flag variances above an agreed tolerance for review.
4. Investigate source-system logic for affected order IDs.
5. Monitor exception count and financial value as data-quality KPIs.
6. Document agreed definitions of deal value, order value, completed payment, refund and net cash.
*/
