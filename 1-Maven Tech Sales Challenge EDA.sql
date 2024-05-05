/*
Project Summary:
This SQL project focuses on data preparation and exploratory data analysis of MavenTech CRM data.
Skills used: Aggregate Functions, Subquery, CTEs, Temp Tables, Window Functions, 
Data Source: Maven Analytics (Maven Sales Current Challenge)
*/
---------------------------------------------------------------------------------------------------------------------
USE [Maven Tech Sales Performance Analysis];
---------------------------------------------------------------------------------------------------------------------
/*
-- Data Preparation Section
*/

-- 1. Quality Assurance the tables 
-- View the structure of the sales_pipeline table
SELECT * FROM sales_pipeline;

-- Check the data types of columns in the sales_pipeline table
SELECT 
    column_name,
    data_type
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'sales_pipeline' 
    AND TABLE_SCHEMA =  'dbo';

-- Standardize date columns to Date Format in the sales_pipeline table
ALTER TABLE sales_pipeline
ALTER COLUMN engage_date DATE;

ALTER TABLE sales_pipeline
ALTER COLUMN close_date DATE;

-- Normalize product names to ensure consistency
UPDATE sales_pipeline
SET product = 'GTX Pro'
WHERE product = 'GTXPro';

-- Normalize company names in the sales_pipeline and accounts tables
UPDATE sales_pipeline
SET account = 'Dambase'
WHERE account = 'dambase';

UPDATE accounts
SET account = 'Dambase'
WHERE account = 'dambase';

-- Populate empty account values as 'Not Available' since they represent missing values
UPDATE sales_pipeline
SET account = 'Not Available'
WHERE account IS NULL;

-- 2. Data Profiling 
-- Count the rows of each table
SELECT 
    'opportunities' AS field_name,
    COUNT(*) AS ttl_count 
FROM sales_pipeline
UNION ALL
SELECT 
    'sales_agent' AS field_name,
    COUNT(sales_agent) AS ttl_count 
FROM sales_teams 
UNION ALL
SELECT 
    'accounts_row' AS field_name,
    COUNT(*) AS ttl_count 
FROM accounts
UNION ALL 
SELECT 
    'products_row' AS field_name,
    COUNT(*) AS ttl_count 
FROM products
UNION ALL 
SELECT 
    'office_location' AS field_name,
     COUNT(DISTINCT office_location) AS ttl_count
FROM accounts;

-- Calculate AVG, MIN, MAX, SUM of close value per deal_stage and sales_agent
SELECT 
    deal_stage,
    ROUND(AVG(close_value), 2) AS avg_close_value,
    MIN(close_value) AS min_close_value,
    MAX(close_value) AS max_close_value,
    SUM(close_value) AS ttl_revenue
FROM sales_pipeline 
GROUP BY deal_stage;


/*
    Exploratory Data Analysis Section
*/

---------------------------------------------------------------------------------------------------------------------

/*
    Objective 1: Creating Temporary table for easy Sales Performance Analysis and remove repetitive joins
    1. Explore quarterly distribution of Opportunities per agent and team.
	2. Sales Trends:Total sales revenue per year and quarter, and sales variation by quarter. 
	3. Analyze sales distribution across products, sectors, office locations, regional offices, and accounts.
	4. Product Retail Price Vs Agent Close Value Range 
*/

-- Exploring the quarterly distribution of Opportunities per agent and team.
-- Ignoring the opportunities without date since we're quantifying them quarterly.

WITH QuarterlyOpportunities AS (
    SELECT 
        YEAR(engage_date) AS year,
        DATEPART(qq, engage_date) AS quarter,
        b.manager AS team_manager,
        a.sales_agent,
        COUNT(*) AS num_opportunities_agent,
        SUM(a.close_value) AS revenue,
        SUM(CASE WHEN deal_stage LIKE '%won%' THEN 1 ELSE 0 END) AS total_won_deals
    FROM sales_pipeline a
    LEFT JOIN sales_teams b ON a.sales_agent = b.sales_agent 
	GROUP BY YEAR(engage_date), DATEPART(qq, engage_date), b.manager, a.sales_agent
)
SELECT 
    *,
    SUM(num_opportunities_agent) OVER (PARTITION BY year, quarter, team_manager) AS num_opportunities_per_team, 
    SUM(revenue) OVER (PARTITION BY year, quarter, team_manager) AS total_revenue_per_team
FROM QuarterlyOpportunities
ORDER BY year, quarter, team_manager, sales_agent;

-- Merging the tables and creating a Temporary Table to use in Sales Performance (EDA)
DROP TABLE IF EXISTS #team_performance_table;

CREATE TABLE #team_performance_table (
    regional_office VARCHAR(50),
    team_manager VARCHAR(50),
    sales_agent VARCHAR(50),
    product VARCHAR(50),
    account VARCHAR(50),
    office_location VARCHAR(50),
    sector VARCHAR(50),
    deal_stage VARCHAR(50),
    engage_date DATE, 
    year INT,
    quarter INT,
    close_date DATE,
    days_taken_to_close INT,
    sales_price FLOAT,
    close_value FLOAT
);

-- Inserting data into the temporary table
INSERT INTO #team_performance_table
    SELECT 
        b.regional_office,
        'Team' + ' ' + LEFT(b.manager, CHARINDEX(' ', b.manager + 'team') - 1),
        a.sales_agent,
        a.product,
        a.account,
        d.office_location,
        d.sector,
        a.deal_stage,
        a.engage_date, 
        YEAR(engage_date),
        DATEPART(qq, engage_date) ,
        a.close_date,
        DATEDIFF(DAY, engage_date, close_date),
        c.sales_price,
        a.close_value
    FROM sales_pipeline a
    LEFT JOIN sales_teams b ON a.sales_agent = b.sales_agent
    LEFT JOIN products c ON a.product = c.product
    LEFT JOIN accounts d ON a.account = d.account
    WHERE engage_date IS NOT NULL;

-- Query the temp table for more sales performance analysis 
SELECT *
FROM #team_performance_table;


/*
    SALES TRENDS
*/

-- Overall Trends in Sales Over Time
-- Calculating total sales revenue per year
SELECT 
    year,
    SUM(close_value) AS total_sales
FROM #team_performance_table
GROUP BY year
ORDER BY year;

-- Sales Variation by Quarter
-- Calculate total sales revenue per quarter to show Seasonal Patterns or Fluctuations in Sales
SELECT 
    year,
    quarter,
    SUM(close_value) AS total_sales,
    ROUND((SUM(close_value) - LAG(SUM(close_value)) OVER (ORDER BY year, quarter)) / LAG(SUM(close_value)) OVER (ORDER BY year, quarter) * 100, 2) AS percentage_change
FROM  #team_performance_table
GROUP BY year, quarter
ORDER BY year, quarter;


/*
    SALES DISTRIBUTION for all time
*/

-- Distribution of Sales Across Different Products
SELECT 
    product,
    SUM(close_value) AS total_sales
FROM #team_performance_table
GROUP BY product
ORDER BY total_sales DESC;

-- Distribution of Revenue per Sector
SELECT 
    sector,
    SUM(close_value) AS total_revenue
FROM #team_performance_table
WHERE sector IS NOT NULL
GROUP BY sector
ORDER BY total_revenue DESC;

-- Distribution of Revenue per Office Location
SELECT 
    office_location,
    SUM(close_value) AS total_revenue
FROM #team_performance_table
WHERE office_location IS NOT NULL
GROUP BY office_location
ORDER BY total_revenue DESC;

-- Distribution of Revenue per Region
SELECT 
    regional_office,
    SUM(close_value) AS total_revenue
FROM #team_performance_table
GROUP BY regional_office
ORDER BY total_revenue DESC;

-- Distribution of Revenue per Account 
SELECT 
    account,
    SUM(close_value) AS total_revenue
FROM #team_performance_table
WHERE account <> 'Not Available'
GROUP BY account
ORDER BY total_revenue DESC;

-- Product Retail Price Vs Agent Close Value Range 
SELECT  
    team_manager,
    sales_agent,
    product,
    sales_price,
    MIN(close_value) AS min_close_value,
    MAX(close_value) AS max_close_value,
    ROUND(AVG(close_value), 2) AS avg_close_value
FROM #team_performance_table 
WHERE close_value <> 0 AND close_value IS NOT NULL
GROUP BY team_manager, sales_agent, product, sales_price;


/*
    Objective 2: Explore each team's quarterly performance in terms of 
    1. Calculate revenue, revenue growth, and its percentage change for each team
    2. Determine the total opportunities of each team
    3. Calculate the team win rate and average deal size
    4. Query for the team bringing the highest revenue in the latest quarter
    5. Compare revenue between the latest quarter and the last quarter to identify percentage change
    6. Store the results in a view for visualization in Power BI (Quarterly Overall Team Performance View)
*/

-- Create a view for overall team performance
CREATE VIEW TeamPerformance AS
WITH TeamPerformance AS 
(
    SELECT 
        b.regional_office,
        b.manager AS team_manager,
        YEAR(a.engage_date) AS year,
        DATEPART(qq, a.engage_date) AS quarter,
        SUM(a.close_value) AS total_revenue,
        LAG(SUM(a.close_value)) OVER (PARTITION BY b.manager ORDER BY YEAR(a.engage_date), DATEPART(qq, a.engage_date)) AS last_quarter_revenue,
        SUM(a.close_value) - LAG(SUM(a.close_value)) OVER (PARTITION BY b.manager ORDER BY YEAR(a.engage_date), DATEPART(qq, a.engage_date)) AS sales_growth,
        COUNT(*) AS total_opportunities,
        SUM(CASE WHEN a.deal_stage LIKE '%won%' THEN 1 ELSE 0 END) AS total_won_deals,
        ROUND(CAST(SUM(CASE WHEN a.deal_stage LIKE '%won%' THEN 1 ELSE 0 END) AS FLOAT) / COUNT(*) * 100, 2) AS team_win_rate,
        ROUND(CAST(SUM(a.close_value) AS FLOAT) / NULLIF(SUM(CASE WHEN a.deal_stage LIKE '%won%' THEN 1 ELSE 0 END), 0), 2) AS team_avg_deal_size
    FROM sales_pipeline a
    LEFT JOIN sales_teams b ON a.sales_agent = b.sales_agent
    WHERE a.engage_date IS NOT NULL
    GROUP BY b.regional_office, b.manager, YEAR(a.engage_date), DATEPART(qq, a.engage_date)
)

SELECT 
    *,
    ROUND((sales_growth / last_quarter_revenue) * 100 , 2) AS revenue_percentage_change
FROM TeamPerformance;

-- Querying the view table to check if total revenue per team is correct
SELECT 
    SUM(total_revenue) AS ttl_revenue
FROM TeamPerformance;

-- For the latest year and quarter, show the highest sales revenue garnered by a team
SELECT 
    MAX(total_revenue) AS highest_revenue
FROM TeamPerformance
WHERE year = 2017 AND quarter = 4;

-- Show the top-performing team and their details or metrics we calculate.
SELECT TOP 1 * 
FROM TeamPerformance
WHERE year = 2017 AND quarter = 4
ORDER BY total_revenue DESC;

-- Show all teams' sale revenue trend for 2017 4th quarter and compare it to the last quarter 
SELECT 
    team_manager,
    total_revenue,
    last_quarter_revenue,
    revenue_percentage_change
FROM TeamPerformance
WHERE year = 2017 AND quarter = 4
ORDER BY total_revenue DESC;


/*
    Objective 3: Explore Quarterly Performance of Each Sales Agent per Team
    1. View the distribution of opportunities and won deals of each sales agent
	2. Calculate performance metrics per sales agent: total close value, sales cycle length, win rate, and average deal size
	3. Store the results in a view for further analysis and visualization
	4. View for Identify High-Performing and Underperforming Salespeople
*/

CREATE VIEW TeamMembersPerformanceAnalysis AS
WITH AgentPerformanceDetails AS 
(
    SELECT 
        b.manager AS team_manager,
        a.sales_agent,
        YEAR(a.engage_date) AS year,
        DATEPART(qq, a.engage_date) AS quarter,
        a.product,
        DATEDIFF(DAY, a.engage_date, a.close_date) AS days_taken_to_close,
        SUM(a.close_value) AS revenue_per_product,
        SUM(SUM(a.close_value)) OVER (PARTITION BY YEAR(a.engage_date), DATEPART(qq, a.engage_date), a.sales_agent) AS quarterly_revenue,
        CASE WHEN a.deal_stage = 'Won' THEN 1 ELSE 0 END AS won_lost_status,
        SUM(CASE WHEN a.deal_stage = 'Won' THEN 1 ELSE 0 END) OVER (PARTITION BY YEAR(a.engage_date), DATEPART(qq, a.engage_date), a.sales_agent, a.product) AS won_deals_per_product,
        SUM(COUNT(*)) OVER (PARTITION BY YEAR(a.engage_date), DATEPART(qq, a.engage_date), a.sales_agent) AS num_opportunities_per_agent,
        SUM(SUM(CASE WHEN a.deal_stage = 'Won' THEN 1 ELSE 0 END)) OVER (PARTITION BY YEAR(a.engage_date), DATEPART(qq, a.engage_date), a.sales_agent) AS num_won_deals
    FROM sales_pipeline a
    LEFT JOIN sales_teams b ON a.sales_agent = b.sales_agent
    WHERE a.engage_date IS NOT NULL
    GROUP BY b.manager, a.sales_agent, a.product, a.engage_date ,a.close_date, a.deal_stage
)

SELECT DISTINCT
    team_manager,
    sales_agent,
    year,
    quarter,
    quarterly_revenue,
    num_won_deals,
    num_opportunities_per_agent,
    SUM(days_taken_to_close) OVER (PARTITION BY sales_agent, year, quarter) / num_won_deals AS sales_cycle_length,
    ROUND((CAST(num_won_deals AS FLOAT) / num_opportunities_per_agent) * 100, 2) AS agent_win_rate,
    ROUND(quarterly_revenue / NULLIF(num_won_deals, 0), 2) AS avg_deal_size
FROM AgentPerformanceDetails
WHERE days_taken_to_close IS NOT NULL
GROUP BY team_manager, sales_agent, year, quarter , days_taken_to_close, quarterly_revenue, num_won_deals, num_opportunities_per_agent;

-- Overview of the table
SELECT TOP 10 * FROM TeamMembersPerformanceAnalysis;

-- Sales Performance Variation Across Individual Team Members
SELECT 
    sales_agent,
    SUM(quarterly_revenue) AS total_revenue
FROM TeamMembersPerformanceAnalysis
GROUP BY sales_agent
ORDER BY total_revenue DESC;

-- Factors Influencing Individual Sales Performance 
-- Query to explore factors influencing individual sales performance (e.g., sales cycle length, win rate, average deal size)
SELECT 
    sales_agent,
    AVG(sales_cycle_length) AS avg_sales_cycle_length,
    AVG(agent_win_rate) AS avg_win_rate,
    AVG(avg_deal_size) AS avg_deal_size
FROM TeamMembersPerformanceAnalysis
GROUP BY sales_agent;

-- Distribution of quarterly revenue
SELECT 
    year,
    quarter,
    ROUND(AVG(quarterly_revenue), 2) AS avg_quarterly_revenue,
    MIN(quarterly_revenue) AS min_quarterly_revenue,
    MAX(quarterly_revenue) AS max_quarterly_revenue
FROM TeamMembersPerformanceAnalysis
GROUP BY year, quarter;

-- Distribution of the number of won deals
SELECT 
    year,
    quarter,
    AVG(num_won_deals) AS avg_num_won_deals,
    MIN(num_won_deals) AS min_num_won_deals,
    MAX(num_won_deals) AS max_num_won_deals
FROM TeamMembersPerformanceAnalysis
GROUP BY year, quarter;

-- Identify High-Performing and underperforming Salespeople based on Total Revenue per Quarter
CREATE VIEW SalesPerformanceView AS
WITH SalesPerformance AS (
    SELECT 
        team_manager,
        sales_agent,
        year,
        quarter,
        SUM(quarterly_revenue) AS total_revenue,
        NTILE(10) OVER (PARTITION BY year, quarter ORDER BY SUM(quarterly_revenue) ASC) AS revenue_percentile
	FROM TeamPerformanceAnalysis
    GROUP BY team_manager, sales_agent, year, quarter)

SELECT 
    *,
    CASE 
        WHEN revenue_percentile >= 9 THEN 'High-performing'
        WHEN revenue_percentile <= 1 THEN 'Consistently underperforming'
        ELSE 'Average performer'
    END AS performance_category
FROM SalesPerformance;
