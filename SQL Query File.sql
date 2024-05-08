
-- Lets check our main fact table: fact_sales_monthly
select * from fact_sales_monthly;

-- Add a generated column fiscal_year in fact_sales_monthly table using schema
-- fiscal_year= year(date_add(calender_date, interval 4 month));

-- To create a P&L statement we need, total gross price, net invoice sales amount, net sales amount, gross margin
-- Lets start with calculation total gross price and check our fact_gross_price table 
select * from fact_gross_price;

-- Join fact_sales_monthly and fact_gross_price using product_code and fiscal_year 
select 
	s.date, s.fiscal_year, s.product_code, s.customer_code, s.sold_quantity, 
    g.gross_price, Round(s.sold_quantity* g.gross_price,1) as tot_gross_price
from fact_sales_monthly s
join fact_gross_price g using (product_code, fiscal_year);

-- Add product and customer details to above table
select * from dim_product;
select * from dim_customer;
select 
	s.date, s.fiscal_year, s.product_code, 
    p.division ,p.product, p.variant, 
    s.customer_code, c.customer, c.market,c.region, 
    s.sold_quantity,Round(g.gross_price,1) as gross_price, 
    Round(s.sold_quantity* g.gross_price,1) as tot_gross_price
from fact_sales_monthly s
join fact_gross_price g using (product_code, fiscal_year)
join dim_product p using (product_code)
join dim_customer c using (customer_code);

-- create a view as tot_gross_price_view
-- Lets move forward to calculate net invoice sales amount. that is (total gross price - pre invoice deduction)

-- view fact_pre_invoice_deduction table
select * from fact_pre_invoice_deductions;

-- Join pre_invoice_discount_pct column to tot_gross_price_view using customer_code and fiscal_year
-- calculate net_invoice_sales_amount and create a view of this table as net_invoice_sales_view 
select 
	g.date, g.fiscal_year, g.product_code, 
    g.division ,g.product, g.variant, 
    g.customer_code, g.customer, g.market,g.region, 
    g.sold_quantity,Round(g.gross_price,1) as gross_price, 
    Round(g.sold_quantity* g.gross_price,1) as tot_gross_price,
    pre.pre_invoice_discount_pct,
    Round((g.tot_gross_price - g.tot_gross_price*pre.pre_invoice_discount_pct),1) as net_invoice_sales_amount
from tot_gross_price_view g
join fact_pre_invoice_deductions pre using (fiscal_year,customer_code);

-- Lets keep moving and calculate net sales amount. that is (net invoice sales amount - post invoice deduction)

-- check the fact_post_invoice_deductions table
select * from fact_post_invoice_deductions;

-- join discount_pct and other_deduction_pct in net_invoice_sales_view and create a new view called net_sales_view 
with cte1 as
(select 
	ni.*,
    po.discounts_pct*ni.net_invoice_sales_amount as post_invoice_discount, 
    po.other_deductions_pct*ni.net_invoice_sales_amount as post_invoice_other_deduction
from net_invoice_sales_view  ni
join fact_post_invoice_deductions po using (date,product_code,customer_code))
Select *, 
	(cte1.net_invoice_sales_amount-cte1.post_invoice_discount-cte1.post_invoice_other_deduction ) as net_sales_amount 
from cte1;


-- Now, its time to calculate gross margin that is  (net_sales_amount - total cogsc amount )
with cte as
(select ns.*,
	mc.manufacturing_cost,
    fc.freight_pct*ns.net_sales_amount as freight_cost,
    fc.other_cost_pct*ns.net_sales_amount as other_deductions
from net_sales_view ns
join fact_manufacturing_cost mc on ns.fiscal_year = mc.cost_year and ns.product_code=mc.product_code
join fact_freight_cost fc using (fiscal_year,market))
select *, 
	(cte.net_sales_amount-cte.manufacturing_cost-cte.freight_cost-cte.other_deductions) as gross_margin_amount
from cte;

-- Now we are done with our P&L statement. Lets review few problem statements asked by the stakeholders
/* Problem Statement 1
Create a product wise sales report (aggregated in a monthly basis at the product level) for Croma India for fiscal year 2021 to track individual product sales and run product analytics on it. The report should have the following columns
o	Month
o	Product name and variant
o	Sold Quantity
o	Gross price per item
o	Gross price total
*/ 
-- Lets take a look on the customer code of "croma" in the market "India" 
select * from dim_customer where customer like "%croma%" and market like "%india%";
# customer code of croma india = 90002002
-- lets create the report for croma India

select 
    s.date,s.product_code, s.fiscal_year, p.product,p.variant, 
    s.customer_code, s.sold_quantity, g.gross_price,
    Round((g.gross_price*s.sold_quantity),2) as total_gross_price
from fact_sales_monthly s
join dim_product p using (product_code)
join fact_gross_price g using (product_code,fiscal_year)
where customer_code = "90002002" and get_fiscal_year(s.date) = 2021;

select gp.date, gp.fiscal_year,gp.product_code, gp.product,
		gp.variant, gp.customer_code, gp.sold_quantity, 
        gp.gross_price,gp.tot_gross_price
from tot_gross_price_view gp 
where customer_code= 90002002 and fiscal_year=2021; 

/*Problem Statement 2.	
Create a stored procedure to determine the market badge based in the following logic. If total sold quantity > 5M that market is considered GOLD else it is SILVER
o	Input- Market and fiscal year
o	Output – Market badge
*/

select gp.market, sum(gp.sold_quantity) as qty_sold, 
	if(sum(gp.sold_quantity) > 5000000, "Gold", "silver") as market_badge
from tot_gross_price_view gp
where fiscal_year = 2021
group by gp.market
order by qty_sold desc;

-- Lets make a stored process for market_badge

/* Problem Statement 3.	
Create a report using stored procedure for top markets, products and customers by net sales 
	for a given financial year to analyse the financial performance and take any appropriate actions to 
    address any potential issues. 
    */
    
-- Lets view top 5 markets by revenue and create a view "top_n_market_by_net_sales"
select market, fiscal_year, Round(sum(net_sales_amount)/1000000,1) as tot_net_sales_mln
from net_sales_view ns
where fiscal_year= 2021
group by market
order by tot_net_sales_mln desc
limit 5;


-- Lets view top 5 customer by revenue and create a view "top_n_customer_by_net_sales"
select 
	customer, 
    fiscal_year, 
    Round(sum(net_sales_amount)/1000000,2) as tot_net_sales_mln
from net_sales_view
where fiscal_year= 2021
group by customer
order by tot_net_sales_mln desc
limit 5;


-- customer marketshare % by net sales
with cte1 as 
( select 
	customer, 
    round(sum(net_sales_amount),1) as tot_net_sales
from net_sales_view
where fiscal_year= 2021
group by customer)
select *,
	Round(tot_net_sales*100/sum(tot_net_sales) over(),1) as market_share
from cte1
order by market_share desc;

-- region market share by net sales
with cte1 as (
select  ns.customer, c.region, round(sum(ns.net_sales)/1000000,1)  as tot_net_sales
from net_sales ns
join dim_customer c using (customer_code)
where fiscal_year=2021
group by ns.customer, c.region)
select 
	*, 
    Round(tot_net_sales*100/sum(tot_net_sales) over(partition by region),1) as market_share
from cte1
order by region, market_share desc;



-- top n product in each division by the qty_sold in FY 2021 and create a view "top_n_product_by_division_for_qty_sold"
with cte1 as 
(select  
	p.division, 
	p.product, 
    sum(s.sold_quantity) as sold_qty,
    dense_rank() over(partition by division order by sum(s.sold_quantity) desc) as dn_rnk
from fact_sales_monthly s
join dim_product p using (product_code)
where fiscal_year=2021
group by p.product,p.division)
select *    
from cte1
where dn_rnk<=3;

-- Retrieve the top 2 markets in every region by their gross sales amount in FY=2021.
with cte1 as 
(select c.region, c.market, Round(sum(gp.tot_gross_price)/1000000,1) as tot_gross_sales,
	dense_rank() over(partition by region order by sum(gp.tot_gross_price) desc) as dn_rnk
from tot_gross_price gp
join dim_customer c using (customer_code)
where fiscal_year = 2021
group by c.market,c.region)
select * from cte1 where dn_rnk<=2 ;


-- Lets move on to the next analysis- Supply chain analytics
/* Problem Statemnt 4.	
Create an aggregate forecast accuracy report for all customer for a given fiscal year to track the forecast accuracy and take appropriate action to reduce the excess inventory and opportunity cost.  The report should have the following columns
o	Customer code, Name, market
o	Total sold Quantity
o	Total forecast Quantity
o	Net Error
o	Absolute Error
o	Forecast Accuracy %
*/
-- Let's start with creating a new table fact_act_est by joining the fact_sales_monthly table and fact_forecast_monthly table 
CREATE TABLE fact_act_est
(select 
	s.date,s.fiscal_year,s.product_code,s.customer_code,s.sold_quantity, f.forecast_quantity 
from fact_sales_monthly s 
left join fact_forecast_monthly f using (date, customer_code, product_code)
union
select 
	f.date,f.fiscal_year,f.product_code,f.customer_code,s.sold_quantity, f.forecast_quantity 
from fact_forecast_monthly f 
join fact_sales_monthly s using (date, customer_code, product_code)
);


-- Lets create a temporary table "Forecast_err_table"instead of a view or a cte to extract frecast accuracy from this table
DROP TEMPORARY TABLE IF EXISTS forecast_err_table;
CREATE TEMPORARY TABLE forecast_err_table AS
SELECT 
    customer_code, 
    SUM(sold_quantity) AS tot_sold_qty,
    SUM(forecast_quantity) AS tot_forecast_qty, 
    SUM(forecast_quantity - sold_quantity) AS net_error,
    SUM(forecast_quantity - sold_quantity) * 100 /sum(forecast_quantity) AS net_error_pct,
    SUM(ABS(forecast_quantity - sold_quantity)) AS abs_error,
    SUM(ABS(forecast_quantity - sold_quantity)) * 100 / Sum(forecast_quantity) AS abs_error_pct
FROM 
    fact_act_est
WHERE 
    fiscal_year = 2021
GROUP BY 
    customer_code;
    
-- Lets calculate the forecast accuracy from the above temporary table "forecast_err_table" adn create a stored procedure
select e.*, c.customer, c.market,
	If(abs_error_pct>100,0,(100-abs_error_pct)) as forecast_accuracy
from forecast_err_table e
join dim_customer c using (customer_code)
order by forecast_accuracy desc;

-- This marks the end of this project
    