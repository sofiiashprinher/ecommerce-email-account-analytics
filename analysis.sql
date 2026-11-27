-- 1. Базова інформація про акаунти
WITH account_base AS (
  SELECT
    ac.id AS account_id,
    s.date AS account_date,
    sp.country,
    ac.send_interval,
    ac.is_verified,
    ac.is_unsubscribed


  FROM `DA.account` ac
  JOIN `DA.account_session` acs
    ON ac.id = acs.account_id
  JOIN `DA.session` s
    ON acs.ga_session_id = s.ga_session_id
  JOIN `DA.session_params` sp
    ON sp.ga_session_id = s.ga_session_id
),


-- 2. Метрики створених акаунтів
account_metrics AS (
  SELECT
    account_date AS date,
    country,
    send_interval,
    is_verified,
    is_unsubscribed,
    COUNT(DISTINCT account_id) AS account_cnt,
    0 AS sent_msg,
    0 AS open_msg,
    0 AS visit_msg


  FROM account_base
  GROUP BY
    date,
    country,
    send_interval,
    is_verified,
    is_unsubscribed
),


-- 3. Базова інформація про відправлені листи
email_sent_base AS (
  SELECT
    es.id_message AS message_id,
    es.id_account AS account_id,
    DATE_ADD(s.date, INTERVAL es.sent_date DAY) AS date,
    sp.country,
    ac.send_interval,
    ac.is_verified,
    ac.is_unsubscribed


  FROM `DA.email_sent` es
  JOIN `DA.account` ac
    ON es.id_account = ac.id
  JOIN `DA.account_session` acs
    ON ac.id = acs.account_id
  JOIN `DA.session` s
    ON acs.ga_session_id = s.ga_session_id
  JOIN `DA.session_params` sp
    ON sp.ga_session_id = s.ga_session_id
),


-- 4. Метрики по email
email_metrics AS (
  SELECT
    es.date,
    es.country,
    es.send_interval,
    es.is_verified,
    es.is_unsubscribed,
    0 AS account_cnt,
    COUNT(DISTINCT es.message_id) AS sent_msg,
    COUNT(DISTINCT CASE WHEN eo.id_message IS NOT NULL THEN es.message_id
      END
    ) AS open_msg,
    COUNT(DISTINCT CASE WHEN ev.id_message IS NOT NULL THEN es.message_id
      END
    ) AS visit_msg
   
  FROM email_sent_base es
  LEFT JOIN `DA.email_open` eo
    ON es.message_id = eo.id_message
  LEFT JOIN `DA.email_visit` ev
    ON es.message_id = ev.id_message
  GROUP BY
    es.date,
    es.country,
    es.send_interval,
    es.is_verified,
    es.is_unsubscribed
),


-- 5. Об'єдную метрики акаунтів та email через Union
united_data AS (
  SELECT
    date,
    country,
    send_interval,
    is_verified,
    is_unsubscribed,
    account_cnt,
    sent_msg,
    open_msg,
    visit_msg
  FROM account_metrics


  UNION ALL


  SELECT
    date,
    country,
    send_interval,
    is_verified,
    is_unsubscribed,
    account_cnt,
    sent_msg,
    open_msg,
    visit_msg
  FROM email_metrics
),


-- 6. Підсумовую метрики
aggregated_data AS (
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


  FROM united_data
  GROUP BY
    date,
    country,
    send_interval,
    is_verified,
    is_unsubscribed
),


-- 7. Рахую загальні значення по кожній країні
country_totals AS (
  SELECT *,
    SUM(account_cnt) OVER (PARTITION BY country) AS total_country_account_cnt,
    SUM(sent_msg) OVER (PARTITION BY country) AS total_country_sent_cnt


  FROM aggregated_data
),


-- 8. Рахую рейтинг країн за кількістю акаунтів та кількістю відправлених листів
country_ranks AS (
  SELECT *,
    DENSE_RANK() OVER (ORDER BY total_country_account_cnt DESC) AS rank_total_country_account_cnt,
    DENSE_RANK() OVER (ORDER BY total_country_sent_cnt DESC) AS rank_total_country_sent_cnt


  FROM country_totals
)


-- 9. Залишаю країни, які входять у топ 10 хоча б за одним із двох рейтингів
SELECT
  date,
  country,
  send_interval,
  is_verified,
  is_unsubscribed,
  account_cnt,
  sent_msg,
  open_msg,
  visit_msg,
  total_country_account_cnt,
  total_country_sent_cnt,
  rank_total_country_account_cnt,
  rank_total_country_sent_cnt


FROM country_ranks


WHERE
  rank_total_country_account_cnt <= 10
  OR rank_total_country_sent_cnt <= 10


ORDER BY
  date,
  country;
