SELECT * FROM northwind.customers;
use northwind;
select *from customers limit 5;
select  * from employees;

select * from orders limit 3;

-- 1. To find the average time gap of customers from previous buy. identify trends in order frequency over time. are there customers whose purchase frequency sharply declines before churn?

with orderFrequency as (select
     customer_id,
     order_date,
     Lag(order_date) over (partition by customer_id order by order_date) as prev_order,
     datediff(order_date, Lag(order_date) over (partition by customer_id order by order_date) )
      as time_gap
from orders)   
select
   customer_id,
   avg(time_gap) as average_time_gap
from orderFrequency
group by customer_id
order by average_time_gap desc;

-- 2. Calculate metrics like average time between orders for different customer segments.
with orderFrequency as (select
     customer_id,
     order_date,
     Lag(order_date) over (partition by customer_id order by order_date) as prev_order,
     datediff(order_date, Lag(order_date) over (partition by customer_id order by order_date) )
      as time_gap
from orders),

-- 3.Analyze average order value for churning and non-churning customers. Do customers typically reduce their order size before churning?

customerSegment as (select
    customer_id,
    case
        when avg(time_gap)<=30 then 'Frequent Buyer'
        when avg(time_gap)<=90 then 'Regular Buyer'
        ELSE 'Infrequent Buyer'
     END as segment
from orderFrequency
group by customer_id)

select
    segment,
    avg(time_gap) as avg_time_gap
from orderFrequency o
join customerSegment cs on o.customer_id = cs.customer_id 
group by segment;

-- 3 analyze avg order value for churning and non-churning customers.Do customers typically reduce their order size before churning;
with churnStatus as(select c.id,
       case 
          when o.customer_id is not null then 'non-churning'
          else 'Churning'
       end as churn_status
from Customers c 
left join orders o on c.id=o.customer_id
),
orderValue as (
select
    o.customer_id,
    sum(od.quantity*od.unit_price) as order_value
    from orders o
    join order_details od on o.id=od.order_id
    group by o.customer_id
    )
 select 
     cs.churn_status,
     avg(ov.order_value) as avg_order_value
 from churnStatus cs
 join orderValue ov on cs.id=ov.customer_id
 group by cs.churn_status;

-- 4. Explore the distribution of order value.Are there customer groups consistently placing smaller orders, potentilly indicating a higher churn risk? 
with OrderValueDistribution as (select 
    c.id,
    sum(od.quantity*od.unit_price) as order_value
from customers c
left join orders o on c.id=o.customer_id
left join order_details od on o.id=od.order_id
group by c.id)
select 
      case
      when order_value <= 1000 then 'Low order value'
      when order_value <= 5000 then 'medium order value'
      when order_value >= 5000 then 'high order value'
      else 'Null order value'
 end as order_value_category,
 count(id) as customer_count
 from orderValueDistribution
 group by order_value_category;
 
 -- 5. idetify changes in product category preferences for customers do they stop buying specific categories altogether?
 select distinct c.id as customer_id,
        c.company as customer_name,
        p.category as churned_category,
        case when o.id is null then 'Churned' else 'Active' end as churn_status
 from customers c
 left join orders o on c.id=o.customer_id
 left join order_details od on o.id=od.order_id
 left join products p on od.product_id=p.id
 where c.id in (select customer_id from orders where status_id=3) -- churn customers
 and p.category not in (
 select distinct p.category
 from customers c
 join orders o on c.id=o.customer_id
 join order_details od on o.id=od.order_id
 join products p on od.product_id = p.id
 where c.id not in (select customer_id from orders where status_id=3) -- active customers
 );
 
 -- 6.analyze the most frequently purchased categories before and after churn events. did their buying habits shift towards different product lines?
  with churned_customers as (
  select distinct customer_id
  from orders
  where status_id=3
  )
  select p.category,
       count(case when o.customer_id in (select customer_id from churned_customers)
  then o.id end) as churned_count,
       count (case when o.customer_id not in (select customer_id from 
 churned_customers) then o.id end) as active_count
 from orders o
 join order_details od on o.id=od.order_id
 join products p on od.product_id=p.id
 group by p.categroy 
 order by churned_count desc;
 
 -- 7. Leverage customer location data to investigate churn rates by region. Are there specific locations with higher churn?
 
 with churned_customers as(
         select distinct customer_id
         from orders
         where status_id in(
             select id from orders_status where status_name='closed' or status_name='Shipped')),
             customer_locations as (
                  select c.id,
						 c.company,
                         c.city,
                         c.state_province,
                         c.country_region,
                         case when cc.customer_id is not null then 'Churned' else 'Active' end as customer_status
                         from customers c 
                         left join churned_customers cc on c.id=cc.customer_id)
    select country_region,
		   state_province,
           city,
           count(case when customer_status='Churned' then 1 end) as churned_count,
           count(case when customer_status='Active' then 1 end) as active_count,
           round((count(case when customer_status='Churned' then 1 end)*100.0))/count(*) as churn_rate
           from customer_locations
           group by country_region, state_province, city
           order by churn_rate desc;
 
-- 8. Eplore correlations between location and purchase behaviour. do buying patterns differ significantly across regions?

select 
     c.country_region,
     c.state_province,
     c.city,
     count(o.id) as total_orders,
     sum(od.quantity) as total_quantity,
     round(sum(od.quantity*od.unit_price),2) as total_revenue
from 
   customers c
join 
    orders o on c.id=o.customer_id
join 
   order_details od on o.id = od.order_id
 group by 
    c.country_region, c.state_province, c.city
order by 
    total_revenue desc ; 
 
 -- 9. Assign a "risk score" to each customer based on factors like purchase frequency decline, reduce order value, or specific product category abandonment.
 
 select 
     c.id as customer_id,
     c.company as company_name,
     count(o.id) as total_orders,
     sum(od.quantity*od.unit_price) as total_spent,
     case
        when count(o.id) >= 7 and sum(od.quantity * od.unit_price) >= 1000 then 'Low Risk'
        when count(o.id) between 4 and 7 and  sum(od.quantity * od.unit_price) between 500 and 999 then 'Medium Risk'
            else 'High Risk'
            end as risk_category
            from 
               customers c
            left join 
               orders o on c.id=o.customer_id
            left join 
               orders_details od on o.id=od.order_id
            group by 
                c.id, c.company
             order by 
                total_orders desc, total_spent desc;
                
-- 10. Utilize customer lifetime value (cltv) calculations to prioritize retention efforts. customers with high CLTV who exhibit concerning behaviour patterns might require immediate intervention.

-- step 1: Claculate customer order frequency over the last 6 month
select 
    c.id as customer_id,
    count(distinct o.id) as total_orders_last_6_months
 from 
    customers c
 left join 
    orders o on c.id=o.customer_id
 where 
   o.order_date>=date_sub((select max(order_date) from orders), interval 6 month) group by c.id;
   
-- Step 2: Idetify customers with a decrease in order frequency
select 
    c.id as customer_id,
    c.company,
    count(distinct o.id) as total_orders
    from 
       customers c
    join
       orders o on c.id=o.customer_id
    where
       o.order_date >= date_sub((select max(order_date) from orders), Interval 6 month) group by c.id,c.company
       having 
           count(distinct o.id) < (select avg(order_count) from (
      
													select
                                                     c.id as customer_id,
                                                     count(distinct o.id) as order_count
                                                     from
                                                        customers c
                                                      join 
                                                         orders o on c.id=o.customer_id
                                                      where 
                                                          o.order_date>=date_sub((select max(order_date)
                                                      from orders), interval 6 month) group by c.id) as order_counts);  
-- step 3. calculate customer lifetime value(CLTV)
select 
   c.id as customer_id,
   round(sum(od.quantity*od.unit_price *(1-od.discount)) - sum(o.shipping_fee + o.taxes),2 )as CLTV
   from customers c
   join 
   orders o on c.id=o.customer_id
   join
   order_details od on o.id=od.order_id
   group by 
   c.id;
           
-- 11. Personalized campained: Design targeted marketing campaigns based on customer purchase behavior and product prefrences. offer incentives to re-engeage customers at risk of churn.
-- step:-1 - we can identify customers at risk of churn

select 
    c.id,
    count(o.id) as totalorders,
    sum(od.unit_price*od.quantity) as TotalSpent
    from
       customers c
     left join 
        orders o on c.id=o.customer_id
     left join 
         order_details od on o.id=od.order_id
     group by
         c.id
     having
         totalOrders>=7 and totalSpent>=1000;
 -- step:-2  we can go for targeted marketing campaigns based on customer purchase behaviour and product preferences. 
 -- example:- offer discounts on frequently purchased products
 
 select 
     c.id,
     p.product_name,
     count(od.order_id) as purchases
 from 
     customers c
  join 
     orders o on c.id=o.customer_id
  join 
      order_details od on o.id=od.order_id
  join
	 products p on od.product_id=p.id
  group by 
     c.id, p.product_name
  order by 
      purchases desc;
            
-- 12. Loyalty Programs: develop loyalty programs or rewards specifically for customers exhibiting churn risk to encourage continued engagement.       
-- Identify customers at risk of churn
select 
     c.id,
     count(o.id) as TotalOrders,
     sum(od.unit_price*od.quantity) as TotalSpent
 from 
   customers c
 left join
    orders o on c.id=o.customer_id
 left join 
    order_details od on o.id=od.order_id
 group by
   c.id
   having
   TotalOrders>=7 and totalspent>=1000;
 -- Develop loyalty programs or rewards specifically for customers exhibiting churn risk
 -- Example: offer loyalty points or dixcounts on future purchase
  select
     c.id,
     coalesce(sum(od.unit_price*od.quantity),0) as TotalSpent,
  case
     when count(o.id) >= 7 and sum(od.unit_price*od.quantity)>=1000 then 'Gold'
     else 'Silver'
     end as LoyaltyTier
  from customers c
  left join 
     orders o on c.id=o.customer_id
  left join 
     order_details od on o.id=od.order_id
  group by 
    c.id;
 
 -- 13. Identify pain points: analyze the resons behind changingn purchase patterns. Are three customers service issues or product quality concerns that need addressing?
 -- Identify potential pain points and reasons behind changing purchase pattern
 select
     c.id as customer_id,
     c.company as company_name,
     o.id as order_id,
     o.order_date,
     od.product_id,
     p.product_name,
     od.quantity,
     od.unit_price,
     od.quantity * od.unit_price as total_price,
     o.ship_city as delivery_city,
     o.ship_country_region as delivery_country,
     case
        when od.quantity*od.unit_price = 0 then 'Product Unavailable'
        when p.discontinued =1 then 'Discontinued product'
		else 'High value'
     end as Purchase_category,
     case
        when od.quantity*od.unit_price=0 then 'product Unavailable'
        when p.discontinued = 1 then 'Discontinued Product'
        else 'Quality Issue'
     end as reson_for_change
   from 
      orders o
   join
       order_details od on o.id=od.order_id
   join 
       products p on od.product_id=p.id
   join
       customers c on o.customer_id=c.id
    where
       o.shipped_date is not null
     order by 
       o.order_date desc;
  
  -- 14. product adjustment: understand which product categories experience declining intrest. use this knowledge to guide product develpment and inventory management decisison.
  select 
      p.category,
      sum(od.quantity*od.unit_price) as total_sales
  from
     order_details od
  inner join
     products p on od.product_id=p.id
  inner join
     orders o on od.order_id=o.id
  where
     o.status_id=2
   group by 
     p.category
  order by
     total_sales asc;
     
  -- 15.  Services Improvements: Customer behavior isights can help assess effectiveness of customer service and support strategies. Indentify areas for improvement to customer experience.
  select
      os.status_name,
      count(o.id) as total_orders
   from
      orders o
   inner join
       orders_status os on o.status_id=os.id
   group by
       os.status_name
   order by 
       total_orders desc;
       
  -- 16. Briefly the problem of customer churn and its impact on Northwind
  select
      count(distinct c.id) as TotalCustomers,
      count(distinct case when o.customer_id is null then c.id end) as churnedCustomers,
      round((count(distinct case when o.customer_id is null then c.id end) / 
    count(distinct c.id))*100,2) as ChurnRate
    from 
     customers c
    left join
      orders o on c.id=o.customer_id;
      
  -- 17. Describe the key customer behaviour patterns you discovered that are linked to churn.
  select
      c.id,
      count(o.id) as TotalOrders,
      round(sum(od.unit_price*od.quantity),2) as TotalSpent
  from
    customers c
  left join
    orders o on c.id = o.customer_id
  left join
     order_details od on o.id=od.order_id
   group by
      c.id
   having
       TotalOrders >=7 and TotalSpent >=1000;
       
 -- 18. Present your churn prediction model and customer  segmentation strategy.
select
     c.id,
     coalesce(round(sum(od.unit_price*od.quantity),2),0) as TotalSpent,
  case
     when count(o.id) >= 7 and sum(od.unit_price*od.quantity)>=3000 then 'Gold'
     when count(o.id) >= 4 and sum(od.unit_price*od.quantity)>=1000 then 'Silver'
     else 'Copper'
     end as LoyaltyTier
  from customers c
  left join 
     orders o on c.id=o.customer_id
  left join 
     order_details od on o.id=od.order_id
  group by 
    c.id;
    
-- 19. Conclude with actionable recommendataions for Northwind, like targeted marketing campaigns or improved customer service, all based on your data analysis.
select 
   c.id,
   coalesce(round(avg(o.shipping_fee),2),0) as AvgShippingFee,
   coalesce(round(avg(o.taxes),2),0) as AvgTaxes,
   count(distinct o.order_date) as TotalOrders,
   coalesce(round(sum(od.unit_price*od.Quantity),2),0) as TotalSpent,
case
   when count(distinct o.order_date)>=5 and sum(od.unit_price* od.Quantity)>=3000 then 'Gold'
    else 'Silver'
    end as LoyaltyTier
 from customers c
 left join orders o on c.id=o.customer_id
 left join order_details od on o.id=od.order_id
 group by c.id;
   
   
 

  
       
                 
        
           
           
                         
      
    



     




   