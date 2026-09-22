/*
Northstar Office Supplies
02 - Data validation
Purpose: validate source volumes, data types, technical keys and CRM business-key duplication.
Assumption: customers, orders, payments, refunds and crm_export have been imported.
*/
USE NorthstarDataQuality;
GO

-- 1. SOURCE ROW COUNTS
SELECT 'customers' AS table_name, COUNT(*) AS row_count FROM customers
UNION ALL SELECT 'orders', COUNT(*) FROM orders
UNION ALL SELECT 'payments', COUNT(*) FROM payments
UNION ALL SELECT 'refunds', COUNT(*) FROM refunds
UNION ALL SELECT 'crm_export', COUNT(*) FROM crm_export;

-- 2. DATA TYPE VALIDATION
SELECT TABLE_NAME, COLUMN_NAME, DATA_TYPE, NUMERIC_PRECISION, NUMERIC_SCALE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME IN ('customers','orders','payments','refunds','crm_export')
ORDER BY TABLE_NAME, ORDINAL_POSITION;

-- 3. CORRECT FINANCIAL DATA TYPES
ALTER TABLE crm_export ALTER COLUMN deal_value DECIMAL(18,2) NOT NULL;
ALTER TABLE payments ALTER COLUMN amount DECIMAL(18,2) NOT NULL;
ALTER TABLE refunds ALTER COLUMN refund_amount DECIMAL(18,2) NOT NULL;

-- Verify financial fields
SELECT TABLE_NAME, COLUMN_NAME, DATA_TYPE, NUMERIC_PRECISION, NUMERIC_SCALE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE (TABLE_NAME='crm_export' AND COLUMN_NAME='deal_value')
   OR (TABLE_NAME='payments' AND COLUMN_NAME='amount')
   OR (TABLE_NAME='refunds' AND COLUMN_NAME='refund_amount')
   OR (TABLE_NAME='orders' AND COLUMN_NAME IN ('unit_price','discount'))
ORDER BY TABLE_NAME, COLUMN_NAME;

-- 4. TECHNICAL KEY UNIQUENESS
SELECT 'customers' AS table_name, COUNT(*) total_rows, COUNT(DISTINCT customer_id) unique_ids FROM customers
UNION ALL SELECT 'orders', COUNT(*), COUNT(DISTINCT order_id) FROM orders
UNION ALL SELECT 'payments', COUNT(*), COUNT(DISTINCT payment_id) FROM payments
UNION ALL SELECT 'refunds', COUNT(*), COUNT(DISTINCT refund_id) FROM refunds
UNION ALL SELECT 'crm_export', COUNT(*), COUNT(DISTINCT crm_record_id) FROM crm_export;

-- 5. CRM BUSINESS KEY CHECK
SELECT order_id, COUNT(*) crm_records, ROUND(SUM(deal_value),2) total_deal_value
FROM crm_export
GROUP BY order_id
HAVING COUNT(*) > 1
ORDER BY crm_records DESC, total_deal_value DESC;

SELECT COUNT(*) duplicated_order_ids, SUM(crm_records-1) excess_crm_records
FROM (
    SELECT order_id, COUNT(*) crm_records
    FROM crm_export
    GROUP BY order_id
    HAVING COUNT(*) > 1
) d;
