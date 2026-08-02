WITH email_metrics AS (  -- in this query, I counted all aggregate functions related to email (I split the query into two parts: in the first part, I counted all metrics for emails, and in the second part, I counted all metrics for accounts).
   SELECT
       DATE_ADD(s.date, INTERVAL es.sent_date DAY) AS date,
       sp.country,
       a.send_interval,
       a.is_verified,
       a.is_unsubscribed,
       COUNT(DISTINCT es.id_message) AS sent_msg,
       COUNT(DISTINCT eo.id_message) AS open_msg,
       COUNT(DISTINCT ev.id_message) AS visit_msg
   FROM `DA.email_sent` es
   JOIN `DA.account` a
       ON es.id_account = a.id
   JOIN `DA.account_session` acs
       ON es.id_account = acs.account_id
   JOIN `DA.session` s
       ON acs.ga_session_id = s.ga_session_id
   JOIN `DA.session_params` sp
       ON s.ga_session_id = sp.ga_session_id
   LEFT JOIN `DA.email_open` eo
       ON es.id_message = eo.id_message
   LEFT JOIN `DA.email_visit` ev
       ON es.id_message = ev.id_message
   GROUP BY 1,2,3,4,5
),


account_metrics AS (  -- this stage followed exactly the same logic as the section with the calculations for the letters
   SELECT
       s.date,
       sp.country,
       a.send_interval,
       a.is_verified,
       a.is_unsubscribed,
       COUNT(DISTINCT a.id) AS account_cnt
   FROM `DA.account_session` acs
   JOIN `DA.session_params` sp
       ON acs.ga_session_id = sp.ga_session_id
   JOIN `DA.session` s
       ON acs.ga_session_id = s.ga_session_id
   JOIN `DA.account` a
       ON acs.account_id = a.id
   GROUP BY 1,2,3,4,5
),


union_data AS ( -- in this section, I have already combined the CTEs related to emails with the CTEs related to accounts
   SELECT
       date,
       country,
       send_interval,
       is_verified,
       is_unsubscribed,
       NULL AS account_cnt,
       sent_msg,
       open_msg,
       visit_msg
   FROM email_metrics


   UNION ALL


   SELECT
       date,
       country,
       send_interval,
       is_verified,
       is_unsubscribed,
       account_cnt,
       NULL AS sent_msg,
       NULL AS open_msg,
       NULL AS visit_msg
   FROM account_metrics
),


merged AS (  -- in this CTE, I concatenated all the rows again to ensure there were no NULL values left, which would incorrectly affect the result after the window functions are evaluated.
   SELECT
       date,
       country,
       send_interval,
       is_verified,
       is_unsubscribed,
       SUM(account_cnt) AS account_cnt,
       SUM(sent_msg) AS sent_msg,
       SUM(open_msg) AS open_msg,
       SUM(visit_msg) AS visit_msg
   FROM union_data
   GROUP BY 1,2,3,4,5
),


metrics AS (  -- in this CTE, I calculated the total number of emails sent and the number of accounts by country
   SELECT
       *,
       SUM(sent_msg)
           OVER(PARTITION BY country)
           AS total_country_sent_cnt,


       SUM(account_cnt)
           OVER(PARTITION BY country)
           AS total_country_account_cnt
   FROM merged
),


ranked AS (  -- I isolated this CTE to calculate country rankings and the number of accounts based on the number of accounts created
   SELECT
       *,
       DENSE_RANK()
           OVER(ORDER BY total_country_sent_cnt DESC)
           AS rank_total_country_sent_cnt,


       DENSE_RANK()
           OVER(ORDER BY total_country_account_cnt DESC)
           AS rank_total_country_account_cnt
   FROM metrics
)


SELECT *   -- in the final CTE, I filtered out all data containing countries or accounts with a rating less than or equal to 10 and returned all the necessary columns
FROM ranked
WHERE rank_total_country_sent_cnt <= 10
 or rank_total_country_account_cnt <= 10
