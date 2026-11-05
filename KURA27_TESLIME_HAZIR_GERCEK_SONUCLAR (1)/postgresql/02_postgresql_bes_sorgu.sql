-- KURA #27 - 5 zorunlu sorgu + nihai rapor + 500 satir denetimi
-- Yalnizca CSV aktarimindan sonra calistirin.

-- ODEV SORGU 1: Model ve goruntunun baskin paket turu: tespit sayisi + ort. guven.
SELECT md.model_name,
       lower(btrim(i.package_type)) AS package_type,
       COUNT(*) AS tespit_sayisi,
       ROUND(AVG(md.confidence), 4) AS ortalama_guven
FROM model_detections md
JOIN images i ON i.id=md.goruntu_id
GROUP BY md.model_name, lower(btrim(i.package_type))
ORDER BY md.model_name, package_type;

-- ODEV SORGU 2: Modellerin sifir tespit urettigi kare sayisi ve orani.
-- Modelin o kareyi gercekten isledigini 'model_inference_runs' kanitlar.
SELECT model_name, COUNT(*) AS islenen_goruntu,
       COUNT(*) FILTER (WHERE tespit_sayisi=0) AS tespitsiz_goruntu,
       ROUND(100.0*COUNT(*) FILTER (WHERE tespit_sayisi=0)/NULLIF(COUNT(*),0),2)
            AS tespitsiz_oran_yuzde
FROM model_inference_runs
GROUP BY model_name
ORDER BY model_name;

-- ODEV SORGU 3: En az 50 tespiti olan model / paket turu gruplari.
SELECT md.model_name, lower(btrim(i.package_type)) AS package_type,
       COUNT(*) AS tespit_sayisi
FROM model_detections md
JOIN images i ON i.id=md.goruntu_id
GROUP BY md.model_name, lower(btrim(i.package_type))
HAVING COUNT(*) >= 50
ORDER BY md.model_name, tespit_sayisi DESC;

-- ODEV SORGU 4: Milisaniye cinsinden GERCEK kare-bazli gecikme dagilimi.
-- Ornek sinirlar: <100 fast, 100-300 medium, >300 slow.
WITH gecikme AS (
 SELECT model_name,
   CASE WHEN latency_ms < 100 THEN 'fast'
        WHEN latency_ms <= 300 THEN 'medium' ELSE 'slow' END AS hiz
 FROM model_inference_runs
)
SELECT model_name, hiz, COUNT(*) AS goruntu_sayisi,
       ROUND(100.0*COUNT(*)/SUM(COUNT(*)) OVER (PARTITION BY model_name),2)
         AS oran_yuzde
FROM gecikme
GROUP BY model_name, hiz
ORDER BY model_name, CASE hiz WHEN 'fast' THEN 1 WHEN 'medium' THEN 2 ELSE 3 END;

-- ODEV SORGU 5: Paket turu bazinda TESPIT dogrulugu: sinif + IoU>=0.5.
SELECT model_name, package_type,
       COUNT(*) FILTER (WHERE durum='TP') AS dogru_tp,
       COUNT(*) FILTER (WHERE durum='FP') AS yanlis_fp,
       COUNT(*) FILTER (WHERE durum='FN') AS kacirilan_fn,
       ROUND(100.0*COUNT(*) FILTER (WHERE durum='TP') /
              NULLIF(COUNT(*) FILTER (WHERE durum IN ('TP','FP')),0),2)
            AS precision_yuzde,
       ROUND(100.0*COUNT(*) FILTER (WHERE durum='TP') /
              NULLIF(COUNT(*) FILTER (WHERE durum IN ('TP','FN')),0),2)
            AS recall_yuzde
FROM detection_matches
GROUP BY model_name,package_type
ORDER BY package_type, model_name;

-- DONEM SONU: iki modelin gercek precision/recall ve gecikmesinin yan yana ozeti.
-- Dolar maliyeti olculmedi: bilerek NULL birakildi.
WITH basari AS (
 SELECT model_name,
  COUNT(*) FILTER (WHERE durum='TP') AS tp,
  COUNT(*) FILTER (WHERE durum='FP') AS fp,
  COUNT(*) FILTER (WHERE durum='FN') AS fn
 FROM detection_matches GROUP BY model_name
), hiz AS (
 SELECT model_name, ROUND(AVG(latency_ms),3) AS ort_gecikme_ms,
        COUNT(*) AS islenen_goruntu
 FROM model_inference_runs GROUP BY model_name
), satir AS (
 SELECT model_name,COUNT(*) AS tespit_sayisi FROM model_detections GROUP BY model_name
)
SELECT m.model_name,
       COALESCE(s.tespit_sayisi,0) AS tespit_sayisi,
       ROUND(100.0*b.tp/NULLIF(b.tp+b.fp,0),2) AS precision_yuzde,
       ROUND(100.0*b.tp/NULLIF(b.tp+b.fn,0),2) AS recall_yuzde,
       h.ort_gecikme_ms, h.islenen_goruntu,
       NULL::NUMERIC AS gercek_maliyet_usd
FROM models m
LEFT JOIN basari b USING (model_name)
LEFT JOIN hiz h USING (model_name)
LEFT JOIN satir s USING (model_name)
ORDER BY m.model_name;

-- SON KONTROL: asgari 500 gercek tespit satiri ve iki ayri model.
SELECT COUNT(*) AS tespit_satiri,
       COUNT(DISTINCT model_name) AS model_sayisi,
       (COUNT(*)>=500 AND COUNT(DISTINCT model_name)=2) AS odev_kosulu_saglandi
FROM model_detections;
