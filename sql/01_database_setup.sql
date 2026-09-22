/*
Northstar Office Supplies
Data Quality & Revenue Reconciliation Investigation
01 - Database setup
*/
IF DB_ID('NorthstarDataQuality') IS NULL
BEGIN
    CREATE DATABASE NorthstarDataQuality;
END;
GO
USE NorthstarDataQuality;
GO
