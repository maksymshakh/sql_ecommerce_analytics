WITH email_metrics AS (  -- у даному запиті я порахував всі агрегатні ф-ції, які стосуються email (я поділив запит на дві частини де в першій рахував всі мтрики по листам, а в другій всі метрики по акаунтам).
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


account_metrics AS (  -- цей етап мав абсолютно такуж логігу як і частина з розрахунками для листів
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


union_data AS ( --в цій частині я вже об`єднував cte які відносяться до листів з cte які відносяться до акаунтів
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


merged AS (  -- в цьому cte я назад об'єднав всі рядки, щоб не залишалося пустих значеннь NULL, які не коректно вплинуть на результат після обчисленнь віконних ф-цій
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


metrics AS (  -- у цьому cte я підрахував загаьну к-ть відправлених листів та к-ть акаунтів у розрізі країн
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


ranked AS (  --цей cte я виокремлював для підрахунку рейтингу країн та к-ті акаунтів за кількістю створених акаунтів
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


SELECT *   -- у фінальному cte я відфільтрував усі дані де попадють країни або акаунти з рейтингом, який менше або дорівнює 10 та вивів всі потрібні колонки
FROM ranked
WHERE rank_total_country_sent_cnt <= 10
 or rank_total_country_account_cnt <= 10
